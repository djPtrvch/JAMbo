import SwiftUI

/// Касания сетки пианоролла (S8c): один палец по пустому — прокрутка вперёд-назад и вверх-вниз (сдвиг больше 8 px;
/// без сдвига — тап, S8d); два пальца — масштаб только по одной оси: какая разошлась первой (больше 10 px) —
/// по горизонтали ширина шага, по вертикали высота строки; точка между пальцами остаётся на месте.
final class RollTouches {
    enum Axis { case h, v }
    enum Mode { case idle, tap, scroll, zoom }

    private var points: [SpatialEventCollection.Event.ID: CGPoint] = [:]
    private(set) var mode: Mode = .idle
    private var start: CGPoint = .zero
    private var axis: Axis? = nil
    private var spread0: CGSize = .zero
    private var mid: CGPoint = .zero
    private var base = RollPort()

    static let slop: CGFloat = 8
    static let zoomSlop: CGFloat = 10

    /// Новые положения касаний; port — вид (прокрутка и масштаб), m — размеры до правки. Возвращает точку тапа,
    /// когда отпущен палец, который не сдвинулся.
    func handle(_ events: SpatialEventCollection, port: inout RollPort, _ m: RollMetrics) -> CGPoint? {
        var tap: CGPoint? = nil
        for e in events {
            if e.phase == .active {
                points[e.id] = e.location
                continue
            }
            points[e.id] = nil
            if mode == .tap && points.isEmpty && e.phase == .ended { tap = start }
        }
        if points.isEmpty {
            mode = .idle
            return tap
        }
        let p: [CGPoint] = Array(points.values)
        if p.count >= 2 && mode != .zoom {
            beginZoom(p[0], p[1], m)
        } else if p.count == 1 && mode == .idle {
            mode = .tap
            start = p[0]
            base = resolved(m)
        }
        switch mode {
        case .tap:
            if hypot(p[0].x - start.x, p[0].y - start.y) > RollTouches.slop { mode = .scroll }
            if mode == .scroll { scroll(p[0], &port) }
        case .scroll:
            scroll(p[0], &port)
        case .zoom:
            if p.count >= 2 { zoom(p[0], p[1], &port, m) }
        case .idle:
            break
        }
        return nil
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
