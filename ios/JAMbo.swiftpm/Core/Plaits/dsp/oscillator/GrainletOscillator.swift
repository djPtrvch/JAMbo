// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/grainlet_oscillator.h.

/// Гранулы: несущая (форма — shape) × синус форманты, сброс форманты на каждом периоде несущей (polyBLEP).
struct GrainletOscillator {
    private var carrierPhase: Float = 0
    private var formantPhase: Float = 0
    private var nextSample: Float = 0

    private var carrierFrequency: Float = 0
    private var formantFrequency: Float = 0
    private var carrierShape: Float = 0
    private var carrierBleed: Float = 0

    init() {}

    @inline(__always)
    mutating func render(_ r: PlaitsResources, _ carrierFrequencyIn: Float, _ formantFrequencyIn: Float,
                         _ carrierShapeIn: Float, _ carrierBleedIn: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var carrierTarget = carrierFrequencyIn
        var formantTarget = formantFrequencyIn
        if carrierTarget >= kMaxFrequency * 0.5 { carrierTarget = kMaxFrequency * 0.5 }
        if formantTarget >= kMaxFrequency { formantTarget = kMaxFrequency }

        var carrierFrequencyModulation = ParameterInterpolator(carrierFrequency, carrierTarget, size)
        var formantFrequencyModulation = ParameterInterpolator(formantFrequency, formantTarget, size)
        var carrierShapeModulation = ParameterInterpolator(carrierShape, carrierShapeIn, size)
        var carrierBleedModulation = ParameterInterpolator(carrierBleed, carrierBleedIn, size)

        var next = nextSample
        for i in 0..<size {
            var thisSample = next
            next = 0

            let f0 = carrierFrequencyModulation.next()
            let f1 = formantFrequencyModulation.next()

            carrierPhase += f0
            let reset = carrierPhase >= 1

            if reset {
                carrierPhase -= 1
                let resetTime = carrierPhase / f0
                let before = grainlet(r, 1, formantPhase + (1 - resetTime) * f1,
                                      carrierShapeModulation.subsample(1 - resetTime),
                                      carrierBleedModulation.subsample(1 - resetTime))
                let after = grainlet(r, 0, 0, carrierShapeModulation.subsample(1),
                                     carrierBleedModulation.subsample(1))
                let discontinuity = after - before
                thisSample += discontinuity * thisBlepSample(resetTime)
                next += discontinuity * nextBlepSample(resetTime)
                formantPhase = resetTime * f1
            } else {
                formantPhase += f1
                if formantPhase >= 1 { formantPhase -= 1 }
            }

            next += grainlet(r, carrierPhase, formantPhase, carrierShapeModulation.next(),
                             carrierBleedModulation.next())
            out[i] = thisSample
        }
        nextSample = next

        carrierFrequency = carrierFrequencyModulation.value
        formantFrequency = formantFrequencyModulation.value
        carrierShape = carrierShapeModulation.value
        carrierBleed = carrierBleedModulation.value
    }

    @inline(__always)
    private func carrier(_ r: PlaitsResources, _ phaseIn: Float, _ shapeIn: Float) -> Float {
        var phase = phaseIn
        let shape = shapeIn * 3
        let shapeIntegral = stmInt(shape)
        let shapeFractional = shape - Float(shapeIntegral)
        var t = 1 - shapeFractional

        if shapeIntegral == 0 {
            phase = phase * (1 + t * t * t * 15)
            if phase >= 1 { phase = 1 }
            phase += 0.75
        } else if shapeIntegral == 1 {
            let breakpoint = 0.001 + 0.499 * t * t * t
            if phase < breakpoint {
                phase *= 0.5 / breakpoint
            } else {
                phase = 0.5 + (phase - breakpoint) * 0.5 / (1 - breakpoint)
            }
            phase += 0.75
        } else {
            t = 1 - t
            phase = 0.25 + phase * (0.5 + t * t * t * 14.5)
            if phase >= 0.75 { phase = 0.75 }
        }
        return (r.sine(phase) + 1) * 0.25
    }

    @inline(__always)
    private func grainlet(_ r: PlaitsResources, _ carrierPhase: Float, _ formantPhase: Float,
                          _ shape: Float, _ bleed: Float) -> Float {
        let c = carrier(r, carrierPhase, shape)
        let formant = r.sine(formantPhase)
        return c * (formant + bleed) / (1 + bleed)
    }
}
