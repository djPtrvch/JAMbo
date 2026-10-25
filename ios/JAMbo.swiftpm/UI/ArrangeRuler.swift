import SwiftUI

/// Касания линейки аранжировщика (S15d). Номера тактов: тап — курсор на ближайшую линию сетки; сдвиг вбок — быстрая
/// прокрутка (×3); удержание 0,35 с и протяжка — диапазон петли; край планки петли — тянется (с магнитом).
/// Строка маркеров: тап по пустому — маркер и сразу окно с именем; тап по маркеру — его окно; маркер со сдвигом
/// пальца — перетаскивание (с магнитом; блоки не двигаются). Перетаскивание и протяжка — одна запись UNDO.
final class ArrRulerTouches {
    enum Mode { case bars, loopSelect, loopEdge, scroll, marker, markerDrag, markerEmpty }

    private var mode: Mode = .bars
    private var start: CGPoint = .zero
    private var baseX: CGFloat = 0
    private var serial: Int = 0
    /// Маркер под пальцем; левый ли край петли тянут; начало протяжки петли (шаг).
    private var marker: Int = -1
    private var leftEdge: Bool = false
    private var anchor: Int = 0

    static let edgeZone: CGFloat = 12

    func begin(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        start = p
        baseX = m.x
        serial += 1
        if p.y >= ArrMetrics.rulerH {
            marker = hitMarker(p, m, model)
            mode = marker >= 0 ? .marker : .markerEmpty
            return
        }
        let a: Arrangement = model.project.arrange
        if a.hasLoop {
            let x0: CGFloat = m.stepX(Double(a.loopFrom))
            let x1: CGFloat = m.stepX(Double(a.loopTo))
            let d0: CGFloat = abs(p.x - x0)
            let d1: CGFloat = abs(p.x - x1)
            let zone: CGFloat = ArrRulerTouches.edgeZone
            if d0 <= zone || d1 <= zone {
                mode = .loopEdge
                leftEdge = d0 < d1
                model.beginGesture()
                return
            }
        }
        mode = .bars
        armHold(m, model)
    }

    /// Удержание номеров тактов без сдвига — протяжка петли.
    private func armHold(_ m: ArrMetrics, _ model: AppModel) {
        let mine: Int = serial
        let x: Int = Int(m.step(at: start.x).rounded())
        DispatchQueue.main.asyncAfter(deadline: .now() + ArrTouches.hold) { [weak self] in
            guard let self = self, self.serial == mine, self.mode == .bars else { return }
            self.mode = .loopSelect
            self.anchor = model.project.arrange.snapped(x)
            model.beginGesture()
        }
    }

    func move(_ p: CGPoint, _ port: inout ArrPort, _ m: ArrMetrics, _ model: AppModel) {
        let moved: Bool = hypot(p.x - start.x, p.y - start.y) > ArrTouches.slop
        let x: Int = Int(m.step(at: p.x).rounded())
        switch mode {
        case .bars, .markerEmpty:
            if moved {
                mode = .scroll
                scroll(p, &port)
            }
        case .scroll:
            scroll(p, &port)
        case .loopSelect:
            model.arrSetLoop(anchor, model.project.arrange.snapped(x))
        case .loopEdge:
            let a: Arrangement = model.project.arrange
            let v: Int = model.project.arrange.snapped(x)
            if leftEdge { model.arrSetLoop(v, a.loopTo) } else { model.arrSetLoop(a.loopFrom, v) }
        case .marker:
            if moved {
                mode = .markerDrag
                model.beginGesture()
                marker = model.arrMoveMarker(marker, to: x)
            }
        case .markerDrag:
            marker = model.arrMoveMarker(marker, to: x)
        }
    }

    func end(_ ended: Bool, _ m: ArrMetrics, _ model: AppModel) {
        let was: Mode = mode
        mode = .bars
        serial += 1
        let x: Int = Int(m.step(at: start.x).rounded())
        switch was {
        case .bars:
            if ended { model.setArrCursor(x) }
        case .loopSelect, .loopEdge, .markerDrag:
            model.endGesture()
        case .marker:
            if ended { model.arrMenu = .marker(index: marker, anchor: start) }
        case .markerEmpty:
            if ended { model.arrAddMarker(at: x, anchor: start) }
        case .scroll:
            break
        }
    }

    private func scroll(_ p: CGPoint, _ port: inout ArrPort) {
        port.x = baseX - (p.x - start.x) * 3
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
