import SwiftUI

/// Касания таймлайна аранжировщика (S15c). Один палец по дорожкам: тап по блоку — выбор (по пустому — ничего),
/// двойной тап — меню блока или места; удержание блока 0,35 с — блок поднимается и едет за пальцем, при отпускании
/// встаёт на место (с магнитом — на линию сетки); край блока — длина сразу; сдвиг по пустому (или по блоку до
/// удержания) — прокрутка. По линейке: тап — курсор, сдвиг вбок — быстрая прокрутка (×3). Два пальца — масштаб по
/// одной оси (какая разошлась первой): по горизонтали — время (точка между пальцами на месте), по вертикали — высота строк.
final class ArrTouches {
    enum Axis { case h, v }
    enum Mode { case idle, tap, press, lift, edge, scroll, ruler, rulerScroll, zoom }

    private var points: [SpatialEventCollection.Event.ID: CGPoint] = [:]
    private var mode: Mode = .idle
    private var start: CGPoint = .zero
    private var base = ArrPort()
    private var axis: Axis? = nil
    private var spread0: CGSize = .zero
    private var mid: CGPoint = .zero
    /// Блок под пальцем (дорожка, номер, блок); край: левый (true) или правый; блоки дорожки до протяжки.
    private var hitTrack: Int = -1
    private var hitIndex: Int = -1
    private var hitBlock: ArrBlock? = nil
    private var leftEdge: Bool = false
    private var edgeBase: [ArrBlock] = []
    private var edgeMoved: Bool = false
    /// Касание-счётчик (таймер удержания срабатывает только для своего касания); прошлый тап — для двойного.
    private var serial: Int = 0
    private var lastTap: (at: Date, point: CGPoint)? = nil
    private var lastPoint: CGPoint = .zero

    static let slop: CGFloat = 8
    static let zoomSlop: CGFloat = 10
    static let hold: Double = 0.35
    static let doubleTap: Double = 0.3

    func handle(_ events: SpatialEventCollection, port: inout ArrPort, _ m: ArrMetrics, _ model: AppModel,
                lift: Binding<ArrLift?>) {
        for e in events {
            if e.phase == .active {
                points[e.id] = e.location
                continue
            }
            if points.removeValue(forKey: e.id) != nil && points.isEmpty {
                finish(model, m, lift: lift, ended: e.phase == .ended)
            }
        }
        if points.isEmpty { return }
        let p: [CGPoint] = Array(points.values)
        if p.count >= 2 && mode != .zoom && mode != .lift && mode != .edge {
            beginZoom(p[0], p[1], m)
        } else if p.count == 1 && mode == .idle {
            begin(p[0], m, model, lift: lift)
        }
        lastPoint = p[0]
        step(p, &port, m, model, lift: lift)
    }

    private func begin(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel, lift: Binding<ArrLift?>) {
        start = p
        base = ArrPort(stepW: m.stepW, x: m.x, rowH: m.rowH, y: m.y)
        hitBlock = nil
        serial += 1
        if p.y < ArrMetrics.top {
            mode = .ruler
            return
        }
        let t: Int = m.track(at: p.y)
        guard t >= 0, t < model.project.tracks.count else {
            mode = .tap
            return
        }
        hitTrack = t
        let blocks: [ArrBlock] = model.project.tracks[t].blocks
        for (i, b) in blocks.enumerated() {
            let r: CGRect = m.rect(t, b)
            let ew: CGFloat = min(14, max(6, r.width / 4))
            if p.x >= r.minX - 6 && p.x <= r.maxX + 6 && p.y >= r.minY && p.y <= r.maxY {
                hitIndex = i
                hitBlock = b
                if p.x <= r.minX + ew || p.x >= r.maxX - ew {
                    mode = .edge
                    leftEdge = p.x <= r.minX + ew
                    edgeBase = blocks
                    edgeMoved = false
                    model.beginGesture()
                    return
                }
                mode = .press
                armHold(model, m, lift: lift)
                return
            }
        }
        mode = .tap
    }

    /// Удержание без сдвига — блок поднимается.
    private func armHold(_ model: AppModel, _ m: ArrMetrics, lift: Binding<ArrLift?>) {
        let mine: Int = serial
        DispatchQueue.main.asyncAfter(deadline: .now() + ArrTouches.hold) { [weak self] in
            guard let self = self, self.serial == mine, self.mode == .press, let b = self.hitBlock else { return }
            self.mode = .lift
            model.arrMenu = nil
            model.arrSel = ArrSel(track: self.hitTrack, block: self.hitIndex)
            withAnimation(.easeOut(duration: 0.12)) {
                lift.wrappedValue = ArrLift(track: self.hitTrack, index: self.hitIndex, block: b, at: Double(b.start),
                                            target: b.start)
            }
        }
    }

    private func step(_ p: [CGPoint], _ port: inout ArrPort, _ m: ArrMetrics, _ model: AppModel, lift: Binding<ArrLift?>) {
        let moved: Bool = hypot(p[0].x - start.x, p[0].y - start.y) > ArrTouches.slop
        switch mode {
        case .tap, .press:
            if moved {
                mode = .scroll
                scroll(p[0], &port, k: 1)
            }
        case .ruler:
            if moved {
                mode = .rulerScroll
                scroll(p[0], &port, k: 3)
            }
        case .scroll:
            scroll(p[0], &port, k: 1)
        case .rulerScroll:
            scroll(p[0], &port, k: 3)
        case .zoom:
            if p.count >= 2 { zoom(p[0], p[1], &port, m) }
        case .lift:
            drag(p[0], m, model, lift: lift)
        case .edge:
            if moved { edgeMoved = true }
            if edgeMoved { edge(p[0], m, model) }
        case .idle:
            break
        }
    }

    private func drag(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel, lift: Binding<ArrLift?>) {
        guard var l = lift.wrappedValue, let b = hitBlock else { return }
        let ds: Double = Double((p.x - start.x) / m.stepW)
        l.at = max(0, Double(b.start) + ds)
        l.target = model.project.arrange.snapped(Int(l.at.rounded()))
        lift.wrappedValue = l
    }

    private func edge(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        guard let b = hitBlock else { return }
        let x: Int = Int(m.step(at: p.x).rounded())
        if leftEdge {
            model.arrResizeBlock(track: hitTrack, base: edgeBase, index: hitIndex, start: min(x, b.end - 1), end: b.end)
        } else {
            model.arrResizeBlock(track: hitTrack, base: edgeBase, index: hitIndex, start: b.start, end: max(x, b.start + 1))
        }
    }

    /// Все пальцы отпущены.
    private func finish(_ model: AppModel, _ m: ArrMetrics, lift: Binding<ArrLift?>, ended: Bool) {
        let was: Mode = mode
        mode = .idle
        serial += 1
        switch was {
        case .tap, .press:
            if ended { tapped(model, m) }
        case .ruler:
            if ended { model.setArrCursor(Int(m.step(at: start.x).rounded())) }
        case .lift:
            settle(model, lift: lift)
        case .edge:
            model.endGesture()
            // Край без сдвига — как тап по блоку (выбор, двойной — меню).
            if ended && !edgeMoved { tapped(model, m) }
        default:
            break
        }
        axis = nil
    }

    /// Тап: по блоку — выбор; двойной — меню блока или места на дорожке.
    private func tapped(_ model: AppModel, _ m: ArrMetrics) {
        let now = Date()
        let double: Bool = lastTap.map { now.timeIntervalSince($0.at) < ArrTouches.doubleTap
            && hypot($0.point.x - start.x, $0.point.y - start.y) < 30 } ?? false
        lastTap = double ? nil : (now, start)
        let t: Int = m.track(at: start.y)
        if hitBlock != nil {
            model.arrSel = ArrSel(track: hitTrack, block: hitIndex)
            if double { model.arrMenu = .block(track: hitTrack, block: hitIndex, anchor: start) }
            return
        }
        if double && t >= 0 {
            let x: Int = Int(m.step(at: start.x).rounded(.down))
            model.arrMenu = .lane(track: t, at: x, anchor: start)
        }
    }

    /// Отпустили поднятый блок: плавно встаёт на место, затем правка (одна запись UNDO).
    private func settle(_ model: AppModel, lift: Binding<ArrLift?>) {
        guard var l = lift.wrappedValue else { return }
        l.at = Double(l.target)
        withAnimation(.easeOut(duration: 0.15)) { lift.wrappedValue = l }
        let sel = ArrSel(track: l.track, block: l.index)
        let to: Int = l.target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if to != l.block.start { model.arrMoveBlock(sel, to: to) }
            lift.wrappedValue = nil
        }
    }

    private func scroll(_ p: CGPoint, _ port: inout ArrPort, k: CGFloat) {
        port.x = base.x - (p.x - start.x) * k
        if k == 1 { port.y = base.y - (p.y - start.y) }
    }

    private func beginZoom(_ a: CGPoint, _ b: CGPoint, _ m: ArrMetrics) {
        mode = .zoom
        axis = nil
        spread0 = CGSize(width: abs(a.x - b.x), height: abs(a.y - b.y))
        mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        base = ArrPort(stepW: m.stepW, x: m.x, rowH: m.rowH, y: m.y)
    }

    private func zoom(_ a: CGPoint, _ b: CGPoint, _ port: inout ArrPort, _ m: ArrMetrics) {
        let sx: CGFloat = abs(a.x - b.x)
        let sy: CGFloat = abs(a.y - b.y)
        if axis == nil {
            let dx: CGFloat = abs(sx - spread0.width)
            let dy: CGFloat = abs(sy - spread0.height)
            if max(dx, dy) < ArrTouches.zoomSlop { return }
            axis = dx >= dy ? .h : .v
        }
        if axis == .h {
            let w0: CGFloat = base.stepW ?? m.stepW
            let k: CGFloat = sx / max(20, spread0.width)
            let w: CGFloat = ArrMetrics.clampStep(w0 * k, width: m.size.width)
            port.stepW = w
            port.x = (base.x + mid.x) / w0 * w - mid.x
            port.y = base.y
        } else {
            let h0: CGFloat = base.rowH
            let k: CGFloat = sy / max(20, spread0.height)
            let h: CGFloat = ArrMetrics.clampRow(h0 * k)
            let my: CGFloat = mid.y - ArrMetrics.top
            port.rowH = h
            port.y = (base.y + my) / h0 * h - my
            port.x = base.x
        }
    }
}
