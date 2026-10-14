import Foundation

/// Щелчок метронома (как clickAt веба): синус 1000 Гц (акцент — 1600), подъём за 2 мс, спад до −80 dB к 50 мс.
public struct Click {
    private var active = false
    private var start: Int64 = 0
    private var phaseInc: Double = 0
    private var peak: Double = 0
    private let sampleRate: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Щелчок с отсчёта at (кадры ядра).
    public mutating func trigger(at: Int64, accent: Bool) {
        active = true
        start = at
        phaseInc = (accent ? 1600 : 1000) / sampleRate
        peak = accent ? 0.5 : 0.3
    }

    /// Прибавить щелчок к блоку, начинающемуся с кадра blockStart.
    public mutating func render(blockStart: Int64, frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if !active { return }
        let attack: Double = 0.002 * sampleRate
        let decay: Double = 0.048 * sampleRate
        let stop: Double = 0.06 * sampleRate
        for i in 0..<frames {
            let n = Double(blockStart + Int64(i) - start)
            if n < 0 { continue }
            if n >= stop {
                active = false
                return
            }
            let g: Double
            if n < attack {
                g = 0.0001 * pow(peak / 0.0001, n / attack)
            } else {
                g = peak * pow(0.0001 / peak, min(1, (n - attack) / decay))
            }
            let s = Float(sin(2 * Double.pi * phaseInc * n) * g)
            left[i] += s
            right[i] += s
        }
    }
}
