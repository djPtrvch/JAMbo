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
