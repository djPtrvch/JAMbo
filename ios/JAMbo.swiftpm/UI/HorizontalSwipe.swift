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

/// Удержание и перетаскивание строки в прокручиваемом списке (порядок пресетов EQ и модулей мастера): распознаватель
/// удержания UIKit (0,4 с, палец почти на месте) на самой строке, рядом со свайпом SwipeRow, — до срабатывания
/// касание достаётся прокрутке (палец пошёл раньше — удержание отменяется), после — сдвиг пальца по вертикали.
/// Жест SwiftUI в ScrollView (iOS 18) забирает касание у прокрутки, а распознаватель снаружи строки проигрывал тапу
/// внутри неё — поэтому он здесь и висит на строке до тапа.
struct HoldDrag: UIGestureRecognizerRepresentable {
    var enabled: Bool = true
    let began: () -> Void
    /// Сдвиг пальца по вертикали от точки удержания.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    /// Строка без перетаскивания (проекты).
    static let off = HoldDrag(enabled: false, began: {}, changed: { _ in }, ended: {})

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        return Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0.4
        g.allowableMovement = 10
        g.delegate = context.coordinator
        g.isEnabled = enabled
        return g
    }

    func updateUIGestureRecognizer(_ g: UILongPressGestureRecognizer, context: Context) {
        if g.isEnabled != enabled { g.isEnabled = enabled }
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

        /// Вместе с тапом строки, но не с прокруткой списка и не со свайпом (оба — UIPanGestureRecognizer).
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return !(other is UIPanGestureRecognizer)
        }
    }
}
