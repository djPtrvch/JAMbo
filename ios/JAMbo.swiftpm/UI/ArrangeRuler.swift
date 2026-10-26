import SwiftUI

/// Касания линейки аранжировщика (S15d, решения пользователя). Тап по линейке (номера тактов и строка секций) — курсор
/// на ближайшую линию сетки (после паузы двойного тапа: двойной тап курсор не ставит); двойной тап — меню линейки
/// (ArrRulerMenu): на секции — RENAME, SPLIT, DELETE SECTION, вне секции — ADD SECTION, SPLIT. Протяжка по номерам
/// тактов (сдвиг пальца) — выделить диапазон целыми тактами (он же диапазон петли — LOOP зацикливает его); край
/// выделенного диапазона тянется точнее — по сетке (с магнитом) или по шагу. Секция не перетаскивается — тянутся её края
/// (с магнитом; блоки не двигаются); плейхед (жёлтый пятиугольник) — перетаскивается, курсор за пальцем. Протяжка и края
/// — одна запись UNDO.
final class ArrRulerTouches {
    enum Mode { case bars, select, edge, marker, markerEdge, markerEmpty, playhead }

    private var mode: Mode = .bars
    private var start: CGPoint = .zero
    /// Маркер под пальцем; левый ли край диапазона тянут; начало протяжки (шаг); прошлый тап — для двойного.
    private var marker: Int = -1
    private var leftEdge: Bool = false
    private var anchor: Int = 0
    private var edgeDragging: Bool = false
    private var lastTap: (at: Date, point: CGPoint)? = nil
    /// Отложенный курсор одиночного тапа: новый тап его отменяет.
    private var tapSerial: Int = 0
    /// Протяжка выделения начинается со сдвига больше этого (тап с дрожью пальца — не выделение).
    static let selectSlop: CGFloat = 14

    static let edgeZone: CGFloat = 12

    func begin(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        start = p
        if p.y >= ArrMetrics.rulerH {
            beginMarkers(p, m, model)
            return
        }
        mode = .bars
        let a: Arrangement = model.project.arrange
        // Плейхед — во всю высоту линейки: у него (до 12 pt) палец берёт его, если не край диапазона.
        let nearHead: Bool = abs(p.x - m.stepX(Double(model.arrNow))) <= ArrRulerTouches.edgeZone
        if !a.hasLoop {
            if nearHead { mode = .playhead }
            return
        }
        let x0: CGFloat = m.stepX(Double(a.loopFrom))
        let x1: CGFloat = m.stepX(Double(a.loopTo))
        let d0: CGFloat = abs(p.x - x0)
        let d1: CGFloat = abs(p.x - x1)
        let zone: CGFloat = ArrRulerTouches.edgeZone
        if d0 <= zone || d1 <= zone {
            mode = .edge
            leftEdge = d0 < d1
        } else if nearHead {
            mode = .playhead
        }
    }

    func move(_ p: CGPoint, _ port: inout ArrPort, _ m: ArrMetrics, _ model: AppModel) {
        let moved: Bool = hypot(p.x - start.x, p.y - start.y) > ArrTouches.slop
        let x: Int = Int(m.step(at: p.x).rounded())
        let v: Int = model.project.arrange.snapped(x)
        switch mode {
        case .bars:
            if hypot(p.x - start.x, p.y - start.y) > ArrRulerTouches.selectSlop {
                mode = .select
                anchor = ArrRulerTouches.bar(m.step(at: start.x))
                model.beginGesture()
                model.arrSetLoop(anchor, ArrRulerTouches.bar(m.step(at: p.x)))
            }
        case .select:
            // Протяжка — целыми тактами (решение пользователя: широко; точно — краями).
            model.arrSetLoop(anchor, ArrRulerTouches.bar(m.step(at: p.x)))
        case .edge:
            if !moved && !edgeDragging { return }
            if !edgeDragging { model.beginGesture() }
            edgeDragging = true
            let a: Arrangement = model.project.arrange
            if leftEdge { model.arrSetLoop(v, a.loopTo) } else { model.arrSetLoop(a.loopFrom, v) }
        case .markerEdge:
            if !moved && !edgeDragging { return }
            if !edgeDragging { model.beginGesture() }
            edgeDragging = true
            model.arrMarkerEdge(marker, left: leftEdge, to: x)
        case .playhead:
            // Без сдвига — тап (двойной тап у курсора — меню); сдвинули — курсор за пальцем.
            if !moved && !edgeDragging { return }
            edgeDragging = true
            if v != model.arrCursor { model.setArrCursor(x) }
        case .marker, .markerEmpty:
            break
        }
    }

    func end(_ ended: Bool, _ m: ArrMetrics, _ model: AppModel) {
        let was: Mode = mode
        let dragged: Bool = edgeDragging
        mode = .bars
        anchor = 0
        edgeDragging = false
        let x: Int = Int(m.step(at: start.x).rounded())
        switch was {
        case .select:
            model.endGesture()
        case .markerEdge, .edge:
            if dragged {
                model.endGesture()
            } else if ended {
                tapRuler(x, model)
            }
        case .bars, .marker, .markerEmpty:
            if ended { tapRuler(x, model) }
        case .playhead:
            // Плейхед не сдвинули — это тап.
            if ended && !dragged { tapRuler(x, model) }
        }
    }

    /// Ближайшая линия такта к шагу s.
    static func bar(_ s: Double) -> Int {
        let n: Double = Double(ArrMetrics.stepsPerBar)
        return max(0, Int((s / n).rounded()) * ArrMetrics.stepsPerBar)
    }

    /// Строка секций: у плейхеда (до 12 pt) — он; у края секции — край (ближайший); внутри секции — она (двойной тап —
    /// окно); иначе — пусто.
    private func beginMarkers(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        let zone: CGFloat = ArrRulerTouches.edgeZone
        if abs(p.x - m.stepX(Double(model.arrNow))) <= zone {
            mode = .playhead
            return
        }
        let list: [ArrMarker] = model.project.arrange.markers
        var best: CGFloat = zone
        marker = -1
        for k in 0..<list.count {
            let d0: CGFloat = abs(p.x - m.stepX(Double(list[k].at)))
            if d0 <= best {
                best = d0
                marker = k
                leftEdge = true
            }
            if let e = model.project.sectionEnd(k) {
                let d1: CGFloat = abs(p.x - m.stepX(Double(e)))
                if d1 < best {
                    best = d1
                    marker = k
                    leftEdge = false
                }
            }
        }
        if marker >= 0 {
            mode = .markerEdge
            return
        }
        marker = hitMarker(p, m, model)
        mode = marker >= 0 ? .marker : .markerEmpty
    }

    /// Тап по линейке — курсор после паузы двойного тапа (второй тап отменяет); двойной — меню линейки.
    private func tapRuler(_ x: Int, _ model: AppModel) {
        tapSerial += 1
        if isDouble() {
            model.arrMenu = .ruler(anchor: start)
            return
        }
        let mine: Int = tapSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + ArrTouches.doubleTap) { [weak self] in
            guard let self = self, self.tapSerial == mine else { return }
            model.setArrCursor(x)
        }
    }

    /// Второй тап за 0,3 с рядом с первым.
    private func isDouble() -> Bool {
        let now = Date()
        var double: Bool = false
        if let l = lastTap {
            let dt: Double = now.timeIntervalSince(l.at)
            let d: CGFloat = hypot(l.point.x - start.x, l.point.y - start.y)
            double = dt < ArrTouches.doubleTap && d < 30
        }
        lastTap = double ? nil : (now, start)
        return double
    }

    /// Маркер под пальцем: вся его секция (до её конца; последняя без конца — до края окна).
    private func hitMarker(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) -> Int {
        let list: [ArrMarker] = model.project.arrange.markers
        var k: Int = list.count - 1
        while k >= 0 {
            let x0: CGFloat = m.stepX(Double(list[k].at))
            var x1: CGFloat = m.size.width
            if let e = model.project.sectionEnd(k) { x1 = m.stepX(Double(e)) }
            let inside: Bool = p.x >= x0 - 4 && p.x < x1
            if inside { return k }
            k -= 1
        }
        return -1
    }
}
