import SwiftUI
import UIKit

/// Горизонтальный жест в прокручиваемом списке (свайп строки, сдвиг значения вбок): распознаватель UIKit, который
/// начинается, только если палец пошёл вбок, — иначе касание сразу достаётся прокрутке. DragGesture SwiftUI внутри
/// ScrollView (iOS 18) иногда забирает касание и список не прокручивается, даже если в onChanged вертикальное
/// движение пропускается.
struct HorizontalSwipe: UIGestureRecognizerRepresentable {
    /// Сдвиг по горизонтали от начала жеста.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        return Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.maximumNumberOfTouches = 1
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        switch g.state {
        case .began, .changed:
            changed(g.translation(in: g.view).x)
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Начинается, только если движение явно вбок (иначе — прокрутка списка).
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v: CGPoint = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y) * 1.5
        }
    }
}

/// Удержание и перетаскивание строки в прокручиваемом списке (порядок пресетов и папок, ReorderDrag): распознаватель
/// удержания UIKit (0,4 с, палец почти на месте) — пока оно не сработало, касание достаётся прокрутке; после —
/// сдвиг пальца по вертикали от точки удержания. DragGesture SwiftUI (даже после LongPressGesture) внутри ScrollView
/// (iOS 18) забирает касание — список не прокручивается.
struct HoldDrag: UIGestureRecognizerRepresentable {
    let began: () -> Void
    /// Сдвиг пальца по вертикали от точки удержания.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        return Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0.4
        g.allowableMovement = 10
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UILongPressGestureRecognizer, context: Context) {
        let y: CGFloat = g.location(in: nil).y
        switch g.state {
        case .began:
            context.coordinator.y0 = y
            began()
        case .changed:
            changed(y - context.coordinator.y0)
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var y0: CGFloat = 0

        /// Вместе с жестами строки (тап, удержание, свайп), но не с прокруткой списка.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return !(other.view is UIScrollView)
        }
    }
}
