// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/sine_oscillator.h: SineOscillator, FastSineOscillator (Sine, SinePM — в PlaitsResources).

/// Синус по таблице; фаза 0…1.
struct SineOscillator {
    private var phase: Float = 0
    private var frequency: Float = 0
    private var amplitude: Float = 0

    mutating func initialize() {
        phase = 0
        frequency = 0
        amplitude = 0
    }

    @inline(__always) mutating func next(_ r: PlaitsResources, _ frequencyIn: Float) -> Float {
        let f = frequencyIn >= 0.5 ? 0.5 : frequencyIn
        phase += f
        if phase >= 1 { phase -= 1 }
        return r.sineNoWrap(phase)
    }

    /// Next(frequency, amplitude, &sin, &cos).
    @inline(__always) mutating func next(_ r: PlaitsResources, _ frequencyIn: Float, _ amplitude: Float) -> (Float, Float) {
        let f = frequencyIn >= 0.5 ? 0.5 : frequencyIn
        phase += f
        if phase >= 1 { phase -= 1 }
        return (amplitude * r.sineNoWrap(phase), amplitude * r.sineNoWrap(phase + 0.25))
    }
}

/// Синус рекурсией (без таблицы); Render с амплитудой — прибавляет к out.
struct FastSineOscillator {
    private var x: Float = 1
    private var y: Float = 0
    private var epsilon: Float = 0
    private var amplitude: Float = 0

    mutating func initialize() {
        x = 1
        y = 0
        epsilon = 0
        amplitude = 0
    }

    @inline(__always) static func fast2Sin(_ f: Float) -> Float {
        let fPi = f * Float.pi
        return fPi * (2 - (2 * 0.96 / 6) * fPi * fPi)
    }

    /// Render(frequency, amplitude, out, size) — режим ADDITIVE.
    @inline(__always) mutating func render(_ frequencyIn: Float, _ amplitudeIn: Float,
                                           _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequency = frequencyIn
        var amplitudeTarget = amplitudeIn
        if frequency >= 0.25 {
            frequency = 0.25
            amplitudeTarget = 0
        } else {
            amplitudeTarget *= 1 - frequency * 4
        }
        var e = ParameterInterpolator(epsilon, FastSineOscillator.fast2Sin(frequency), size)
        var am = ParameterInterpolator(amplitude, amplitudeTarget, size)
        var x = self.x
        var y = self.y
        let norm = x * x + y * y
        if norm <= 0.5 || norm >= 2 {
            let scale = fastRsqrtCarmack(norm)
            x *= scale
            y *= scale
        }
        for i in 0..<size {
            let eps = e.next()
            x += eps * y
            y -= eps * x
            out[i] += am.next() * x
        }
        self.x = x
        self.y = y
        epsilon = e.value
        amplitude = am.value
    }
}
