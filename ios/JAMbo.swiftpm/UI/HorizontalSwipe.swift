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

/// Удержание и перетаскивание строки в прокручиваемом списке (порядок пресетов и папок, ReorderDrag): невидимый вид
/// фоном строки вешает распознаватель удержания UIKit (0,4 с, палец почти на месте) на прокручиваемый список над ним —
/// вне жестов SwiftUI: жест на строке снаружи (и представимый) не начинается, пока возможен тап внутри строки, а
/// DragGesture SwiftUI в ScrollView (iOS 18) забирает касание у прокрутки. Распознаватель берёт только касания в
/// границах своей строки; пока удержание не сработало, касание достаётся прокрутке и тапу.
struct HoldDragHost: UIViewRepresentable {
    let began: () -> Void
    /// Сдвиг пальца по вертикали от точки удержания.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator() -> HoldDragCoordinator {
        return HoldDragCoordinator()
    }

    func makeUIView(context: Context) -> HoldDragView {
        let v = HoldDragView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ v: HoldDragView, context: Context) {
        let c: HoldDragCoordinator = context.coordinator
        c.began = began
        c.changed = changed
        c.ended = ended
        c.attach(v)
    }

    static func dismantleUIView(_ v: HoldDragView, coordinator: HoldDragCoordinator) {
        coordinator.detach()
    }
}

/// Фон строки: попал в окно — распознаватель на ближайший прокручиваемый список (нет его — на окно).
final class HoldDragView: UIView {
    weak var coordinator: HoldDragCoordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { coordinator?.detach() } else { coordinator?.attach(self) }
    }
}

final class HoldDragCoordinator: NSObject, UIGestureRecognizerDelegate {
    var began: () -> Void = {}
    var changed: (CGFloat) -> Void = { _ in }
    var ended: () -> Void = {}
    private weak var row: UIView?
    private weak var host: UIView?
    private var y0: CGFloat = 0
    private lazy var press: UILongPressGestureRecognizer = {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(act(_:)))
        g.minimumPressDuration = 0.4
        g.allowableMovement = 10
        g.delegate = self
        return g
    }()

    func attach(_ v: UIView) {
        row = v
        guard v.window != nil else { return }
        var s: UIView? = v.superview
        while let x = s, !(x is UIScrollView) { s = x.superview }
        guard let target = s ?? v.window else { return }
        if host === target { return }
        detach()
        target.addGestureRecognizer(press)
        host = target
    }

    func detach() {
        host?.removeGestureRecognizer(press)
        host = nil
    }

    @objc private func act(_ g: UILongPressGestureRecognizer) {
        let y: CGFloat = g.location(in: nil).y
        switch g.state {
        case .began:
            y0 = y
            began()
        case .changed:
            changed(y - y0)
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }

    /// Только касания в границах своей строки.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let r = row, r.window != nil else { return false }
        return r.bounds.contains(touch.location(in: r))
    }

    /// Вместе с жестами строки (тап, удержание, свайп), но не с прокруткой списка.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return !(other.view is UIScrollView && other is UIPanGestureRecognizer)
    }
}
