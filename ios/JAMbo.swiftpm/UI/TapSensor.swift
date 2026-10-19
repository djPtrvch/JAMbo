import CoreMotion
import Foundation

/// Толчки iPad для KEY VELOCITY (S12): акселерометр ~100 Гц без гравитации (минус медленное среднее), модуль
/// в g, последние 0,5 с. Работает, только пока KEY VELOCITY включён; разрешений не нужно.
final class TapSensor {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var samples: [(t: Double, g: Double)] = []
    private var avg: (Double, Double, Double)? = nil
    /// Последний толчок и сила (DIAGNOSTICS: подбор порогов).
    private(set) var lastPeak: Double = 0
    private(set) var lastVelocity: Double = 0

    var available: Bool { motion.isAccelerometerAvailable }
    var running: Bool { motion.isAccelerometerActive }

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        queue.maxConcurrentOperationCount = 1
        motion.accelerometerUpdateInterval = 0.005
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let d = data else { return }
            self.add(d.timestamp, d.acceleration.x, d.acceleration.y, d.acceleration.z)
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        lock.lock()
        samples.removeAll()
        avg = nil
        lock.unlock()
    }

    /// Отсчёт датчика (очередь датчика): толчок — отклонение от медленного среднего (гравитация, наклон).
    private func add(_ t: Double, _ x: Double, _ y: Double, _ z: Double) {
        let a: (Double, Double, Double) = avg ?? (x, y, z)
        let k: Double = 0.05
        avg = (a.0 + (x - a.0) * k, a.1 + (y - a.1) * k, a.2 + (z - a.2) * k)
        let dx: Double = x - a.0, dy: Double = y - a.1, dz: Double = z - a.2
        let g: Double = (dx * dx + dy * dy + dz * dz).squareRoot()
        lock.lock()
        samples.append((t, g))
        let cut: Double = t - 0.5
        if let i = samples.firstIndex(where: { $0.t >= cut }), i > 0 { samples.removeFirst(i) }
        lock.unlock()
    }

    /// Сила касания в момент at (секунды с запуска системы); nil — данных датчика нет.
    func velocity(at: Double) -> Double? {
        lock.lock()
        let s = samples
        lock.unlock()
        guard let p = TapVelocity.peak(s, at: at) else { return nil }
        let v: Double = TapVelocity.velocity(peak: p)
        lastPeak = p
        lastVelocity = v
        return v
    }
}
