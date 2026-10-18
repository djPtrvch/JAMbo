import SwiftUI

/// Куда пришлось касание сетки пианоролла.
enum RollHit {
    case none
    case empty(pos: Int, row: Int)
    case body(RollNote)
    case edge(RollNote)
}

extension RollMetrics {
    /// Рамка ноты (нота длиннее прохода — до его конца); nil — высоты нет среди строк.
    func rect(_ n: RollNote) -> CGRect? {
        guard let r = rows.firstIndex(of: n.pitch) else { return nil }
        let end: Int = min(n.pos + n.len, cols)
        let x0: CGFloat = colX(n.pos)
        let w: CGFloat = max(2, CGFloat(end - n.pos) * colW)
        return CGRect(x: x0, y: rowY(r), width: w, height: rowH)
    }

    /// Правый край ноты (длина) — полоса у края шириной до 18 px и чуть правее; иначе тело ноты; иначе пустая клетка.
    func hit(_ p: CGPoint, _ notes: [RollNote]) -> RollHit {
        for n in notes.reversed() {
            guard let rc = rect(n), p.y >= rc.minY, p.y < rc.maxY else { continue }
            let ew: CGFloat = min(18, max(8, rc.width / 3))
            if p.x >= rc.maxX - ew && p.x <= rc.maxX + 10 { return .edge(n) }
        }
        for n in notes.reversed() {
            guard let rc = rect(n) else { continue }
            if rc.contains(p) { return .body(n) }
        }
        let pos: Int = Int(((p.x + x) / colW).rounded(.down))
        let fromTop: Int = Int(((p.y + y) / rowH).rounded(.down))
        let row: Int = rows.count - 1 - fromTop
        if pos < 0 || pos >= cols || row < 0 || row >= rows.count { return .none }
        return .empty(pos: pos, row: row)
    }
}

/// Касания сетки пианоролла (S8c, S8d). Один палец: по пустому — сдвиг больше 8 px прокручивает, без сдвига — тап
/// ставит ноту; тап по ноте — удалить; правый край ноты — длина по GRID; удержание ноты (0,3 с) — перетащить по GRID
/// и по нотам гаммы (сдвиг до удержания — прокрутка). Два пальца — масштаб по одной оси: какая разошлась первой
/// (больше 10 px) — по горизонтали ширина шага, по вертикали высота строки; точка между пальцами стоит на месте.
final class RollTouches {
    enum Axis { case h, v }
    enum Mode { case idle, tap, press, scroll, zoom, move, resize }

    private var points: [SpatialEventCollection.Event.ID: CGPoint] = [:]
    private(set) var mode: Mode = .idle
    private var start: CGPoint = .zero
    private var axis: Axis? = nil
    private var spread0: CGSize = .zero
    private var mid: CGPoint = .zero
    private var base = RollPort()
    /// Нота под пальцем (как стоит сейчас), где она была в начале, звучащая нота (id).
    private var note: RollNote? = nil
    private var origin: RollNote? = nil
    private var emptyHit: (pos: Int, row: Int)? = nil
    private var soundId: Int? = nil
    private var serial: Int = 0

    static let slop: CGFloat = 8
    static let zoomSlop: CGFloat = 10
    static let hold: Double = 0.3

    /// Новые положения касаний; port — вид (прокрутка и масштаб), m — размеры до правки.
    func handle(_ events: SpatialEventCollection, port: inout RollPort, _ m: RollMetrics, _ notes: [RollNote],
                _ model: AppModel) {
        for e in events {
            if e.phase == .active {
                points[e.id] = e.location
                continue
            }
            if points.removeValue(forKey: e.id) != nil && points.isEmpty { finish(model, ended: e.phase == .ended) }
        }
        if points.isEmpty { return }
        let p: [CGPoint] = Array(points.values)
        if p.count >= 2 && mode != .zoom && mode != .move && mode != .resize {
            stopSound(model)
            beginZoom(p[0], p[1], m)
        } else if p.count == 1 && mode == .idle {
            begin(p[0], m, notes, model)
        }
        step(p, &port, m, model)
    }

    private func step(_ p: [CGPoint], _ port: inout RollPort, _ m: RollMetrics, _ model: AppModel) {
        switch mode {
        case .tap, .press:
            if hypot(p[0].x - start.x, p[0].y - start.y) > RollTouches.slop {
                mode = .scroll
                scroll(p[0], &port)
            }
        case .scroll:
            scroll(p[0], &port)
        case .zoom:
            if p.count >= 2 { zoom(p[0], p[1], &port, m) }
        case .move:
            move(p[0], m, model)
        case .resize:
            resize(p[0], m, model)
        case .idle:
            break
        }
    }

    /// Первое касание: что под пальцем.
    private func begin(_ p: CGPoint, _ m: RollMetrics, _ notes: [RollNote], _ model: AppModel) {
        start = p
        base = resolved(m)
        note = nil
        emptyHit = nil
        serial += 1
        switch m.hit(p, notes) {
        case .edge(let n):
            note = n
            mode = .resize
            model.beginGesture()
        case .body(let n):
            note = n
            mode = .press
            let s: Int = serial
            DispatchQueue.main.asyncAfter(deadline: .now() + RollTouches.hold) { [weak self, weak model] in
                guard let self = self, let model = model else { return }
                self.held(s, model)
            }
        case .empty(let pos, let row):
            emptyHit = (pos, row)
            mode = .tap
        case .none:
            mode = .tap
        }
    }

    /// Удержание ноты без сдвига — перетаскивание (нота звучит, пока её держат).
    private func held(_ s: Int, _ model: AppModel) {
        guard s == serial, mode == .press, let n = note else { return }
        mode = .move
        origin = n
        model.beginGesture()
        startSound(n, model)
    }

    /// Все пальцы отпущены.
    private func finish(_ model: AppModel, ended: Bool) {
        switch mode {
        case .tap:
            if ended, let h = emptyHit, h.row < model.rollRows.count { model.rollAdd(pos: h.pos, pitch: model.rollRows[h.row]) }
        case .press:
            if ended, let n = note { model.rollRemove(n) }
        case .move, .resize:
            model.endGesture()
        default:
            break
        }
        stopSound(model)
        mode = .idle
        note = nil
        origin = nil
        serial += 1
    }

    private func move(_ p: CGPoint, _ m: RollMetrics, _ model: AppModel) {
        guard let o = origin, let cur = note, let r0 = m.rows.firstIndex(of: o.pitch) else { return }
        let g: Int = model.settings.rollGrid
        let dc: Int = Int(((p.x - start.x) / m.colW / CGFloat(g)).rounded()) * g
        let dr: Int = Int((-(p.y - start.y) / m.rowH).rounded())
        let pos: Int = min(m.cols - 1, max(0, o.pos + dc))
        let row: Int = min(m.rows.count - 1, max(0, r0 + dr))
        let pitch: Int = m.rows[row]
        if pos == cur.pos && pitch == cur.pitch { return }
        guard let moved = model.rollMove(cur, pos: pos, pitch: pitch) else { return }
        note = moved
        if pitch != cur.pitch {
            stopSound(model)
            startSound(moved, model)
        }
    }

    private func resize(_ p: CGPoint, _ m: RollMetrics, _ model: AppModel) {
        guard let n = note else { return }
        let steps: Double = Double((p.x - m.colX(n.pos)) / m.colW)
        let len: Int = Roll.snapLen(steps: steps, grid: model.settings.rollGrid, pos: n.pos, cols: m.cols)
        if len == n.len { return }
        model.rollResize(n, len: len)
        note = RollNote(pos: n.pos, index: n.index, k: n.k, pitch: n.pitch, len: len, vel: n.vel)
    }

    private func startSound(_ n: RollNote, _ model: AppModel) {
        let id: Int = AppModel.nextRollId()
        soundId = id
        model.rollPreview(pitch: n.pitch, vel: n.vel, id: id)
    }

    private func stopSound(_ model: AppModel) {
        guard let id = soundId else { return }
        model.rollPreviewOff(id: id)
        soundId = nil
    }

    /// Вид с вычисленными по умолчанию значениями (ширина шага и прокрутка).
    private func resolved(_ m: RollMetrics) -> RollPort {
        return RollPort(colW: m.colW, rowH: m.rowH, x: m.x, y: m.y)
    }

    private func scroll(_ p: CGPoint, _ port: inout RollPort) {
        port.x = base.x - (p.x - start.x)
        port.y = (base.y ?? 0) - (p.y - start.y)
    }

    private func beginZoom(_ a: CGPoint, _ b: CGPoint, _ m: RollMetrics) {
        mode = .zoom
        axis = nil
        spread0 = CGSize(width: abs(a.x - b.x), height: abs(a.y - b.y))
        mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        base = resolved(m)
    }

    private func zoom(_ a: CGPoint, _ b: CGPoint, _ port: inout RollPort, _ m: RollMetrics) {
        let sx: CGFloat = abs(a.x - b.x)
        let sy: CGFloat = abs(a.y - b.y)
        if axis == nil {
            let dx: CGFloat = abs(sx - spread0.width)
            let dy: CGFloat = abs(sy - spread0.height)
            if max(dx, dy) < RollTouches.zoomSlop { return }
            axis = dx >= dy ? .h : .v
        }
        if axis == .h {
            let w0: CGFloat = base.colW ?? m.colW
            let k: CGFloat = sx / max(20, spread0.width)
            let w: CGFloat = RollZoom.colW(w0 * k, m)
            port.colW = w
            port.x = (base.x + mid.x) / w0 * w - mid.x
            port.y = base.y
        } else {
            let h0: CGFloat = base.rowH
            let k: CGFloat = sy / max(20, spread0.height)
            let h: CGFloat = RollZoom.rowH(h0 * k)
            port.rowH = h
            port.y = ((base.y ?? 0) + mid.y) / h0 * h - mid.y
            port.x = base.x
        }
    }
}

/// Пределы масштаба: шаг — от всего прохода (но не меньше 16 шагов) на ширину до 4 шагов; строка — 18…96 px.
enum RollZoom {
    static func colW(_ w: CGFloat, _ m: RollMetrics) -> CGFloat {
        let lo: CGFloat = m.size.width / CGFloat(max(16, m.cols))
        let hi: CGFloat = m.size.width / 4
        return min(hi, max(lo, w))
    }

    static func rowH(_ h: CGFloat) -> CGFloat {
        return min(96, max(18, h))
    }
}
