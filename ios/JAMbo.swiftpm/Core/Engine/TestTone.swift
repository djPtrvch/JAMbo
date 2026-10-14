import Foundation

/// Тест-тон S0: синус, уровень −12 dBFS, включение и выключение без щелчка (огибающая 5 мс).
public final class TestTone {
    public static let level: Float = 0.25118864 // −12 dBFS
    private let sampleRate: Double
    private var phase: Double = 0
    private var increment: Double
    private var gain: Float = 0
    private var target: Float = 0
    /// Коэффициент однополюсного сглаживания огибающей (постоянная 5 мс).
    private let smooth: Float

    public init(sampleRate: Double, frequency: Double = 440) {
        self.sampleRate = sampleRate
        increment = frequency / sampleRate
        smooth = Float(1 - exp(-1 / (0.005 * sampleRate)))
    }

    public var isOn: Bool { return target > 0 }

    public func set(on: Bool) {
        target = on ? TestTone.level : 0
    }

    public func set(frequency: Double) {
        increment = frequency / sampleRate
    }

    /// Прибавить `frames` кадров к left и right.
    @inline(__always)
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if gain == 0 && target == 0 { return }
        var p = phase
        var g = gain
        let inc = increment
        let t = target
        let k = smooth
        for i in 0..<frames {
            g += (t - g) * k
            let s = Float(sin(2 * Double.pi * p)) * g
            left[i] += s
            right[i] += s
            p += inc
            if p >= 1 { p -= 1 }
        }
        if t == 0 && g < 1e-6 { g = 0 }
        phase = p
        gain = g
    }
}
