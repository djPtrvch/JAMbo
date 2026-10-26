import SwiftUI

/// Касания таймлайна аранжировщика (S15c). Один палец по дорожкам: тап по блоку — выбор (по пустому — снять выделение
/// рамкой), двойной тап — меню блока или места; удержание блока 0,35 с — блок поднимается и едет за пальцем, при
/// отпускании встаёт на место (с магнитом — на линию сетки; блок группы — переезжает вся группа); удержание по пустому —
/// рамка выделения (блоки на разных дорожках); край блока — длина сразу; сдвиг по пустому (или по блоку до удержания) —
/// прокрутка (по времени и, в EXPANDED, по дорожкам). Линейка и строка маркеров — ArrRulerTouches (S15d). INSERT: тап по
/// дорожке — клип для вставки, правый край вставленного блока — длина со сдвигом. Два пальца — масштаб по времени (точка
/// между пальцами на месте) и прокрутка; по вертикали масштаба нет (решение пользователя).
final class ArrTouches {
    enum Mode { case idle, tap, press, lift, edge, scroll, ruler, zoom, marquee, ref }

    private var points: [SpatialEventCollection.Event.ID: CGPoint] = [:]
    private var mode: Mode = .idle
    private var start: CGPoint = .zero
    private var base = ArrPort()
    private var zooming: Bool = false
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
    private let ruler = ArrRulerTouches()
    /// Строка REF: сдвиг начала файла до жеста (секунды).
    private var refBase: Double = 0
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
        if p.count >= 2 && mode != .zoom && mode != .lift && mode != .edge && mode != .ref {
            beginZoom(p[0], p[1], m)
        } else if p.count == 1 && mode == .idle {
            begin(p[0], m, model, lift: lift)
        }
        lastPoint = p[0]
        step(p, &port, m, model, lift: lift)
    }

    private func begin(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel, lift: Binding<ArrLift?>) {
        start = p
        base = ArrPort(stepW: m.stepW, x: m.x, y: m.y)
        hitBlock = nil
        serial += 1
        if p.y < ArrMetrics.top {
            mode = .ruler
            ruler.begin(p, m, model)
            return
        }
        // Строка REF: палец вбок — сдвиг начала файла (одна запись UNDO на жест).
        if m.inRef(p.y) {
            mode = .ref
            refBase = model.project.arrange.ref?.offset ?? 0
            model.beginGesture()
            return
        }
        let t: Int = m.track(at: p.y)
        guard t >= 0, t < model.project.tracks.count else {
            mode = .tap
            armMarquee(model)
            return
        }
        hitTrack = t
        let blocks: [ArrBlock] = model.project.tracks[t].blocks
        for (i, b) in blocks.enumerated() {
            let r: CGRect = m.rect(t, b)
            let ew: CGFloat = min(14, max(6, r.width / 4))
            let inX: Bool = p.x >= r.minX - 6 && p.x <= r.maxX + 6
            let inY: Bool = p.y >= r.minY && p.y <= r.maxY
            if inX && inY {
                hitIndex = i
                hitBlock = b
                if p.x <= r.minX + ew || p.x >= r.maxX - ew {
                    mode = .edge
                    leftEdge = p.x <= r.minX + ew
                    edgeBase = blocks
                    edgeMoved = false
                    model.arrGroup = []
                    model.beginGesture()
                    return
                }
                mode = .press
                armHold(model, m, lift: lift)
                return
            }
        }
        mode = .tap
        armMarquee(model)
    }

    /// Удержание по пустому без сдвига — рамка выделения от точки касания.
    private func armMarquee(_ model: AppModel) {
        if model.arrInsert { return }
        let mine: Int = serial
        DispatchQueue.main.asyncAfter(deadline: .now() + ArrTouches.hold) { [weak self] in
            guard let self = self, self.serial == mine, self.mode == .tap else { return }
            self.mode = .marquee
            model.arrMenu = nil
            model.arrSel = nil
            model.arrGroup = []
            model.arrMarquee = CGRect(origin: self.start, size: .zero)
        }
    }

    /// Рамка до пальца: выделены блоки, которых она касается.
    private func marquee(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        model.arrMarquee = r
        var list: [ArrSel] = []
        for (t, tr) in model.project.tracks.enumerated() {
            for (i, b) in tr.blocks.enumerated() where m.rect(t, b).intersects(r) {
                list.append(ArrSel(track: t, block: i))
            }
        }
        if list != model.arrGroup { model.arrGroup = list }
    }

    /// Удержание без сдвига — блок поднимается.
    private func armHold(_ model: AppModel, _ m: ArrMetrics, lift: Binding<ArrLift?>) {
        let mine: Int = serial
        DispatchQueue.main.asyncAfter(deadline: .now() + ArrTouches.hold) { [weak self] in
            guard let self = self, self.serial == mine, self.mode == .press, let b = self.hitBlock else { return }
            self.mode = .lift
            model.arrMenu = nil
            let s = ArrSel(track: self.hitTrack, block: self.hitIndex)
            let group: Bool = model.arrInGroup(s)
            if !group {
                model.arrSel = s
                model.arrGroup = []
            }
            withAnimation(.easeOut(duration: 0.12)) {
                lift.wrappedValue = ArrLift(track: self.hitTrack, index: self.hitIndex, block: b, at: Double(b.start),
                                            target: b.start, group: group)
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
            ruler.move(p[0], &port, m, model)
        case .scroll:
            scroll(p[0], &port, k: 1)
        case .zoom:
            if p.count >= 2 { zoom(p[0], p[1], &port, m) }
        case .lift:
            drag(p[0], m, model, lift: lift)
        case .marquee:
            marquee(p[0], m, model)
        case .ref:
            let ds: Double = Double((p[0].x - start.x) / m.stepW)
            model.setArrRefOffset(refBase + ds * model.arrStepSeconds)
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
        // INSERT: правый край только что вставленного блока — длина вставки, блоки правее сдвигаются вслед.
        if model.arrInsert && !leftEdge && model.arrInserted == ArrSel(track: hitTrack, block: hitIndex) {
            model.arrResizeInserted(track: hitTrack, base: edgeBase, index: hitIndex, end: max(x, b.start + 1))
            return
        }
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
            ruler.end(ended, m, model)
        case .ref:
            model.endGesture()
        case .lift:
            settle(model, lift: lift)
        case .edge:
            model.endGesture()
            // Край без сдвига — как тап по блоку (выбор, двойной — меню).
            if ended && !edgeMoved { tapped(model, m) }
        case .marquee:
            // Один блок в рамке — обычный выбор.
            model.arrMarquee = nil
            if model.arrGroup.count == 1 {
                model.arrSel = model.arrGroup[0]
                model.arrGroup = []
            }
        default:
            break
        }
        zooming = false
    }

    /// Тап: по блоку — выбор; двойной — меню блока или места на дорожке.
    private func tapped(_ model: AppModel, _ m: ArrMetrics) {
        let now = Date()
        var double: Bool = false
        if let l = lastTap {
            let dt: Double = now.timeIntervalSince(l.at)
            let d: CGFloat = hypot(l.point.x - start.x, l.point.y - start.y)
            double = dt < ArrTouches.doubleTap && d < 30
        }
        lastTap = double ? nil : (now, start)
        let t: Int = m.track(at: start.y)
        // INSERT: тап по дорожке — меню клипов для вставки в ближайшую линию сетки.
        if model.arrInsert && t >= 0 {
            let x: Int = Int(m.step(at: start.x).rounded())
            model.select(track: t)
            model.arrMenu = .insert(track: t, at: x, anchor: start)
            return
        }
        if hitBlock != nil {
            // Блок группы — группа остаётся (двойной тап — меню группы); другой блок — обычный выбор.
            let s = ArrSel(track: hitTrack, block: hitIndex)
            if !model.arrInGroup(s) {
                model.arrSel = s
                model.arrGroup = []
            }
            if double { model.arrMenu = .block(track: hitTrack, block: hitIndex, anchor: start) }
            return
        }
        model.arrGroup = []
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
            if l.group {
                model.arrMoveGroup(by: to - l.block.start)
            } else if to != l.block.start {
                model.arrMoveBlock(sel, to: to)
            }
            lift.wrappedValue = nil
        }
    }

    private func scroll(_ p: CGPoint, _ port: inout ArrPort, k: CGFloat) {
        port.x = base.x - (p.x - start.x) * k
        if k == 1 { port.y = base.y - (p.y - start.y) }
    }

    private func beginZoom(_ a: CGPoint, _ b: CGPoint, _ m: ArrMetrics) {
        mode = .zoom
        zooming = false
        spread0 = CGSize(width: abs(a.x - b.x), height: abs(a.y - b.y))
        mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        base = ArrPort(stepW: m.stepW, x: m.x, y: m.y)
    }

    /// Два пальца (решения пользователя): разошлись или сошлись по горизонтали — масштаб по времени (точка между
    /// пальцами на месте); сдвинулись вместе вбок — прокрутка по времени.
    private func zoom(_ a: CGPoint, _ b: CGPoint, _ port: inout ArrPort, _ m: ArrMetrics) {
        let sx: CGFloat = abs(a.x - b.x)
        let cx: CGFloat = (a.x + b.x) / 2
        port.y = base.y
        if !zooming {
            if abs(sx - spread0.width) < ArrTouches.zoomSlop {
                port.x = base.x - (cx - mid.x)
                return
            }
            zooming = true
        }
        let w0: CGFloat = base.stepW ?? m.stepW
        let k: CGFloat = sx / max(20, spread0.width)
        let w: CGFloat = ArrMetrics.clampStep(w0 * k, width: m.size.width)
        port.stepW = w
        port.x = (base.x + mid.x) / w0 * w - cx
    }
}
