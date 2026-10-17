// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/string_synth_oscillator.h.

/// Органное деление частоты: пилы 8′, 4′, 2′, 1′ из одной фазы (сегменты 0…7), регистры — 7 весов.
struct StringSynthOscillator {
    private var phase: Float = 0
    private var nextSample: Float = 0
    private var segment = 0

    private var frequency: Float = 0.001
    private var saw8Gain: Float = 0
    private var saw4Gain: Float = 0
    private var saw2Gain: Float = 0
    private var saw1Gain: Float = 0

    init() {}

    /// unshiftedRegistration — не меньше 7 значений; out — прибавляется.
    @inline(__always)
    mutating func render(_ frequencyIn: Float, _ unshiftedRegistration: UnsafePointer<Float>, _ gain: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequencyTarget = frequencyIn * 8

        // Очень высокие частоты — на 1–2 октавы ниже: вместо 1-й гармоники 8 кГц — 2-я гармоника 4 кГц.
        var shift = 0
        while frequencyTarget > 0.5 {
            shift += 2
            frequencyTarget *= 0.5
        }
        // Частота слишком высока.
        if shift >= 8 { return }

        @inline(__always) func registration(_ k: Int) -> Float {
            k < shift ? 0 : unshiftedRegistration[k - shift]
        }

        var fm = ParameterInterpolator(frequency, frequencyTarget, size)
        var saw8GainModulation = ParameterInterpolator(
            saw8Gain, (registration(0) + 2 * registration(1)) * gain, size)
        var saw4GainModulation = ParameterInterpolator(
            saw4Gain, (registration(2) - registration(1) + 2 * registration(3)) * gain, size)
        var saw2GainModulation = ParameterInterpolator(
            saw2Gain, (registration(4) - registration(3) + 2 * registration(5)) * gain, size)
        var saw1GainModulation = ParameterInterpolator(
            saw1Gain, (registration(6) - registration(5)) * gain, size)

        var ph = phase
        var next = nextSample
        var seg = segment
        for i in 0..<size {
            var thisSample = next
            next = 0

            let f = fm.next()
            let s8 = saw8GainModulation.next()
            let s4 = saw4GainModulation.next()
            let s2 = saw2GainModulation.next()
            let s1 = saw1GainModulation.next()

            ph += f
            var nextSegment = stmInt(ph)
            if nextSegment != seg {
                var discontinuity: Float = 0
                if nextSegment == 8 {
                    ph -= 8
                    nextSegment -= 8
                    discontinuity -= s8
                }
                if nextSegment & 3 == 0 { discontinuity -= s4 }
                if nextSegment & 1 == 0 { discontinuity -= s2 }
                discontinuity -= s1
                if discontinuity != 0 {
                    let fraction = ph - Float(nextSegment)
                    let t = fraction / f
                    thisSample += thisBlepSample(t) * discontinuity
                    next += nextBlepSample(t) * discontinuity
                }
            }
            seg = nextSegment

            next += (ph - 4) * s8 * 0.125
            next += (ph - Float(seg & 4) - 2) * s4 * 0.25
            next += (ph - Float(seg & 6) - 1) * s2 * 0.5
            next += (ph - Float(seg & 7) - 0.5) * s1
            out[i] += 2 * thisSample
        }
        nextSample = next
        phase = ph
        segment = seg

        frequency = fm.value
        saw8Gain = saw8GainModulation.value
        saw4Gain = saw4GainModulation.value
        saw2Gain = saw2GainModulation.value
        saw1Gain = saw1GainModulation.value
    }
}
