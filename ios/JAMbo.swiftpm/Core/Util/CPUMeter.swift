/// Нагрузка аудиоколбэка: время расчёта блока / длительность блока, среднее за ~0,5 с звука.
/// measure вызывается в колбэке (только арифметика); load читает UI.
public final class CPUMeter: @unchecked Sendable {
    /// Окно усреднения в кадрах звука.
    private let window: Int
    private let sampleRate: Double
    private var busyNs: Double = 0
    private var frames: Int = 0
    private let value = AtomicFloat(0)
    private let peakValue = AtomicFloat(0)
    private var peakNow: Double = 0

    public init(sampleRate: Double, windowSeconds: Double = 0.5) {
        self.sampleRate = sampleRate
        window = Int(sampleRate * windowSeconds)
    }

    /// Блок из `frames` кадров считался `ns` наносекунд.
    @inline(__always)
    public func measure(ns: Double, frames blockFrames: Int) {
        busyNs += ns
        frames += blockFrames
        let blockNs = Double(blockFrames) / sampleRate * 1e9
        if blockNs > 0 { peakNow = max(peakNow, ns / blockNs) }
        if frames >= window {
            let wallNs = Double(frames) / sampleRate * 1e9
            value.store(Float(busyNs / wallNs))
            peakValue.store(Float(peakNow))
            busyNs = 0
            frames = 0
            peakNow = 0
        }
    }

    /// Средняя нагрузка 0…1 (доля одного ядра).
    public var load: Float { return value.load() }
    /// Наибольшая нагрузка одного блока за окно 0…1.
    public var peak: Float { return peakValue.load() }
}
