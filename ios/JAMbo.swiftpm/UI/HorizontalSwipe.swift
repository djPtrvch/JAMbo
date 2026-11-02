import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

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

/// Удержание и перетаскивание строки (порядок пресетов EQ и модулей мастера, ReorderState.hold): что делать, когда
/// RowGesture решил, что строку держат. enabled = false — у строки нет перетаскивания (проекты).
struct HoldDrag {
    var enabled: Bool = true
    let began: () -> Void
    /// Сдвиг пальца по вертикали от точки удержания.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    static let off = HoldDrag(enabled: false, began: {}, changed: { _ in }, ended: {})
}

/// Жест строки списка SwipeRow — свайп и удержание одним распознавателем UIKit (два отдельных мешали друг другу:
/// удержание не начиналось, пока свайп ещё возможен). Палец сдвинулся больше чем на 10 pt раньше 0,4 с: вбок — свайп,
/// по вертикали — жест не начинается, касание достаётся прокрутке; стоит 0,4 с — удержание, дальше строка едет за
/// пальцем (прокрутка в это время не начинается). Отпустили, не сдвинув и раньше 0,4 с, — жест не начался, тап строки.
struct RowGesture: UIGestureRecognizerRepresentable {
    let swipeChanged: (CGFloat) -> Void
    let swipeEnded: () -> Void
    let hold: HoldDrag

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        return Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> RowRecognizer {
        let g = RowRecognizer()
        g.holdEnabled = hold.enabled
        g.delegate = context.coordinator
        return g
    }

    func updateUIGestureRecognizer(_ g: RowRecognizer, context: Context) {
        g.holdEnabled = hold.enabled
    }

    func handleUIGestureRecognizerAction(_ g: RowRecognizer, context: Context) {
        let p: CGPoint = g.location(in: nil)
        let dx: CGFloat = p.x - g.start.x
        let dy: CGFloat = p.y - g.start.y
        let end: Bool = g.state == .ended || g.state == .cancelled || g.state == .failed
        if g.holding {
            if g.state == .began { hold.began() }
            if end { hold.ended() } else { hold.changed(dy) }
        } else {
            if end { swipeEnded() } else { swipeChanged(dx) }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Вместе с тапом строки, но не с прокруткой списка.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return !(other is UIPanGestureRecognizer)
        }
    }
}

/// Распознаватель RowGesture: решает по первым 10 pt движения или по 0,4 с без движения.
final class RowRecognizer: UIGestureRecognizer {
    var holdEnabled: Bool = true
    /// Точка касания (в окне) и что решено: удержание (иначе — свайп).
    private(set) var start: CGPoint = .zero
    private(set) var holding: Bool = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touches.count > 1 || numberOfTouches > 1 {
            state = .failed
            return
        }
        guard let t = touches.first else { return }
        start = t.location(in: nil)
        holding = false
        stopTimer()
        if holdEnabled { perform(#selector(fire), with: nil, afterDelay: 0.4) }
    }

    /// 0,4 с без движения — удержание.
    @objc private func fire() {
        guard state == .possible else { return }
        holding = true
        state = .began
    }

    private func stopTimer() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fire), object: nil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touches.first else { return }
        if state == .began || state == .changed {
            state = .changed
            return
        }
        if state != .possible { return }
        let p: CGPoint = t.location(in: nil)
        let dx: CGFloat = p.x - start.x
        let dy: CGFloat = p.y - start.y
        if abs(dx) < 10 && abs(dy) < 10 { return }
        stopTimer()
        if abs(dx) > abs(dy) * 1.5 {
            state = .began
        } else {
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        stopTimer()
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        stopTimer()
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        stopTimer()
        holding = false
    }
}
