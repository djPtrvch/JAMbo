import SwiftUI
import Observation
import QuartzCore

/// Общие часы анимаций (17.11, нагрузка): один CADisplayLink на 60 Гц вместо своего таймера у каждого вида. Все
/// анимации (измеритель, линии воспроизведения, окна мастера, скоп…) обновляются в одном кадре: свои таймеры на
/// экране 120 Гц могли попадать в разные кадры, а служебная работа SwiftUI на кадр дорогая. Счётчики 60, 30 и 10 Гц
/// наблюдаются отдельно — вид на 30 Гц не пересчитывается каждый кадр. Часы сами встают, когда их никто не читает
/// (все анимации на паузе), и запускаются, как только вид снова их читает.
final class FrameClock: NSObject, Observable {
    static let shared = FrameClock()
    private let registrar = ObservationRegistrar()
    private var link: CADisplayLink? = nil
    private var frame: Int = 0
    /// Кадров подряд без чтения часов — после 10 часы встают.
    private var idle: Int = 0
    private var read: Bool = false
    private var _t60: Int = 0
    private var _t30: Int = 0
    private var _t10: Int = 0

    /// Счётчик тиков частоты fps (60, 30 или 10); чтение — подписка вида и запуск часов.
    func tick(_ fps: Int) -> Int {
        read = true
        start()
        if fps >= 60 {
            registrar.access(self, keyPath: \.t60)
            return _t60
        }
        if fps >= 30 {
            registrar.access(self, keyPath: \.t30)
            return _t30
        }
        registrar.access(self, keyPath: \.t10)
        return _t10
    }

    // Пути для регистратора.
    private var t60: Int { return _t60 }
    private var t30: Int { return _t30 }
    private var t10: Int { return _t10 }

    private func start() {
        if let l = link {
            if l.isPaused { l.isPaused = false }
            return
        }
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func step() {
        if read {
            read = false
            idle = 0
        } else {
            idle += 1
            if idle >= 10 {
                link?.isPaused = true
                return
            }
        }
        frame &+= 1
        registrar.withMutation(of: self, keyPath: \.t60) { _t60 &+= 1 }
        if frame % 2 == 0 { registrar.withMutation(of: self, keyPath: \.t30) { _t30 &+= 1 } }
        if frame % 6 == 0 { registrar.withMutation(of: self, keyPath: \.t10) { _t10 &+= 1 } }
    }
}

/// Время кадра для содержимого (как TimelineView.Context: только date).
struct FrameContext {
    let date: Date
}

/// Замена TimelineView(.animation) на общих часах: fps — 60, 30 или 10; paused — вид не подписан на часы (проба A —
/// все стоят, проба H — вдвое реже).
struct FrameTimeline<Content: View>: View {
    let fps: Int
    let paused: Bool
    let content: (FrameContext) -> Content

    init(fps: Int, paused: Bool = false, @ViewBuilder content: @escaping (FrameContext) -> Content) {
        self.fps = fps
        self.paused = paused
        self.content = content
    }

    var body: some View {
        if !paused && !LoadAnim.stop {
            let half: Bool = LoadProbe.shared.mode == LoadProbe.half
            _ = FrameClock.shared.tick(half ? fps / 2 : fps)
        }
        return content(FrameContext(date: Date()))
    }
}
