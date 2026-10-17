// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/z_oscillator.h.

/// Синтез в духе Casio CZ: форманта со сбросом на каждом полупериоде несущей, контур — shape, сдвиг фазы — mode.
struct ZOscillator {
    private var carrierPhase: Float = 0
    private var discontinuityPhase: Float = 0
    private var formantPhase: Float = 0
    private var nextSample: Float = 0

    private var carrierFrequency: Float = 0
    private var formantFrequency: Float = 0
    private var carrierShape: Float = 0
    private var mode: Float = 0

    init() {}

    @inline(__always)
    mutating func render(_ r: PlaitsResources, _ carrierFrequencyIn: Float, _ formantFrequencyIn: Float,
                         _ carrierShapeIn: Float, _ modeIn: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var carrierTarget = carrierFrequencyIn
        var formantTarget = formantFrequencyIn
        if carrierTarget >= kMaxFrequency * 0.5 { carrierTarget = kMaxFrequency * 0.5 }
        if formantTarget >= kMaxFrequency { formantTarget = kMaxFrequency }

        var carrierFrequencyModulation = ParameterInterpolator(carrierFrequency, carrierTarget, size)
        var formantFrequencyModulation = ParameterInterpolator(formantFrequency, formantTarget, size)
        var carrierShapeModulation = ParameterInterpolator(carrierShape, carrierShapeIn, size)
        var modeModulation = ParameterInterpolator(mode, modeIn, size)

        var next = nextSample
        for i in 0..<size {
            var thisSample = next
            next = 0

            let f0 = carrierFrequencyModulation.next()
            let f1 = formantFrequencyModulation.next()

            discontinuityPhase += 2 * f0
            carrierPhase += f0
            let reset = discontinuityPhase >= 1

            if reset {
                discontinuityPhase -= 1
                let resetTime = discontinuityPhase / (2 * f0)

                let carrierPhaseBefore: Float = carrierPhase >= 1 ? 1 : 0.5
                let carrierPhaseAfter: Float = carrierPhase >= 1 ? 0 : 0.5
                let before = z(r, carrierPhaseBefore, 1, formantPhase + (1 - resetTime) * f1,
                               carrierShapeModulation.subsample(1 - resetTime),
                               modeModulation.subsample(1 - resetTime))
                let after = z(r, carrierPhaseAfter, 0, 0, carrierShapeModulation.subsample(1),
                              modeModulation.subsample(1))

                let discontinuity = after - before
                thisSample += discontinuity * thisBlepSample(resetTime)
                next += discontinuity * nextBlepSample(resetTime)
                formantPhase = resetTime * f1

                if carrierPhase > 1 {
                    carrierPhase = discontinuityPhase * 0.5
                }
            } else {
                formantPhase += f1
                if formantPhase >= 1 { formantPhase -= 1 }
            }

            if carrierPhase >= 1 { carrierPhase -= 1 }

            next += z(r, carrierPhase, discontinuityPhase, formantPhase, carrierShapeModulation.next(),
                      modeModulation.next())
            out[i] = thisSample
        }
        nextSample = next

        carrierFrequency = carrierFrequencyModulation.value
        formantFrequency = formantFrequencyModulation.value
        carrierShape = carrierShapeModulation.value
        mode = modeModulation.value
    }

    @inline(__always)
    private func z(_ r: PlaitsResources, _ c: Float, _ d: Float, _ f: Float, _ shapeIn: Float,
                   _ mode: Float) -> Float {
        var rampDown = 0.5 * (1 + r.sine(0.5 * d + 0.25))

        let offset: Float
        let phaseShift: Float
        if mode < 0.333 {
            offset = 1
            phaseShift = 0.25 + mode * 1.50
        } else if mode < 0.666 {
            phaseShift = 0.7495 - (mode - 0.33) * 0.75
            offset = -r.sine(phaseShift)
        } else {
            phaseShift = 0.7495 - (mode - 0.33) * 0.75
            offset = 0.001
        }

        let discontinuity = r.sine(f + phaseShift)
        let contour: Float
        if shapeIn < 0.5 {
            let shape = shapeIn * 2
            if c >= 0.5 { rampDown *= shape }
            contour = 1 + (r.sine(c + 0.25) - 1) * shape
        } else {
            contour = r.sine(c + shapeIn * 0.5)
        }
        return (rampDown * (offset + discontinuity) - offset) * contour
    }
}
