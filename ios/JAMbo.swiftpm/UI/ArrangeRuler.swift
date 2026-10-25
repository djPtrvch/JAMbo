import SwiftUI

/// Касания линейки аранжировщика (S15d, решения пользователя). Номера тактов: тап — курсор на ближайшую линию сетки;
/// протяжка — выделить диапазон (с магнитом; он же диапазон петли — LOOP зацикливает его); край выделенного диапазона —
/// тянется; двойной тап внутри диапазона — меню LOOP / SECTION. Строка маркеров: двойной тап по маркеру — его окно
/// (имя, цвет, CURSOR HERE, DELETE), по пустому — новый маркер и окно с именем; маркер со сдвигом пальца —
/// перетаскивание (с магнитом; блоки не двигаются). Протяжка и перетаскивание — одна запись UNDO.
final class ArrRulerTouches {
    enum Mode { case bars, select, edge, marker, markerDrag, markerEmpty }

    private var mode: Mode = .bars
    private var start: CGPoint = .zero
    /// Маркер под пальцем; левый ли край диапазона тянут; начало протяжки (шаг); прошлый тап — для двойного.
    private var marker: Int = -1
    private var leftEdge: Bool = false
    private var anchor: Int = 0
    private var edgeDragging: Bool = false
    private var lastTap: (at: Date, point: CGPoint)? = nil

    static let edgeZone: CGFloat = 12

    func begin(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        start = p
        if p.y >= ArrMetrics.rulerH {
            marker = hitMarker(p, m, model)
            mode = marker >= 0 ? .marker : .markerEmpty
            return
        }
        mode = .bars
        let a: Arrangement = model.project.arrange
        if !a.hasLoop { return }
        let x0: CGFloat = m.stepX(Double(a.loopFrom))
        let x1: CGFloat = m.stepX(Double(a.loopTo))
        let d0: CGFloat = abs(p.x - x0)
        let d1: CGFloat = abs(p.x - x1)
        let zone: CGFloat = ArrRulerTouches.edgeZone
        if d0 <= zone || d1 <= zone {
            mode = .edge
            leftEdge = d0 < d1
        }
    }

    func move(_ p: CGPoint, _ port: inout ArrPort, _ m: ArrMetrics, _ model: AppModel) {
        let moved: Bool = hypot(p.x - start.x, p.y - start.y) > ArrTouches.slop
        let x: Int = Int(m.step(at: p.x).rounded())
        let v: Int = model.project.arrange.snapped(x)
        switch mode {
        case .bars:
            if moved {
                mode = .select
                anchor = model.project.arrange.snapped(Int(m.step(at: start.x).rounded()))
                model.beginGesture()
                model.arrSetLoop(anchor, v)
            }
        case .select:
            model.arrSetLoop(anchor, v)
        case .edge:
            if !moved && !edgeDragging { return }
            if !edgeDragging { model.beginGesture() }
            edgeDragging = true
            let a: Arrangement = model.project.arrange
            if leftEdge { model.arrSetLoop(v, a.loopTo) } else { model.arrSetLoop(a.loopFrom, v) }
        case .marker:
            if moved {
                mode = .markerDrag
                model.beginGesture()
                marker = model.arrMoveMarker(marker, to: x)
            }
        case .markerDrag:
            marker = model.arrMoveMarker(marker, to: x)
        case .markerEmpty:
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
        case .select, .markerDrag:
            model.endGesture()
        case .edge:
            if dragged {
                model.endGesture()
            } else if ended {
                tapBars(x, m, model)
            }
        case .bars:
            if ended { tapBars(x, m, model) }
        case .marker:
            if ended && isDouble() { model.arrMenu = .marker(index: marker, anchor: start) }
        case .markerEmpty:
            if ended && isDouble() { model.arrAddMarker(at: x, anchor: start) }
        }
    }

    /// Тап по номерам тактов: двойной внутри выделенного диапазона — меню диапазона, иначе — курсор.
    private func tapBars(_ x: Int, _ m: ArrMetrics, _ model: AppModel) {
        let a: Arrangement = model.project.arrange
        let inside: Bool = a.hasLoop && x >= a.loopFrom && x <= a.loopTo
        if isDouble() && inside {
            model.arrMenu = .range(anchor: start)
            return
        }
        model.setArrCursor(x)
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

    /// Маркер под пальцем: от его начала до следующего маркера (последний — 80 pt).
    private func hitMarker(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) -> Int {
        let list: [ArrMarker] = model.project.arrange.markers
        var k: Int = list.count - 1
        while k >= 0 {
            let x0: CGFloat = m.stepX(Double(list[k].at))
            var x1: CGFloat = x0 + 80
            if k + 1 < list.count { x1 = m.stepX(Double(list[k + 1].at)) }
            let inside: Bool = p.x >= x0 - 4 && p.x < x1
            if inside { return k }
            k -= 1
        }
        return -1
    }
}
