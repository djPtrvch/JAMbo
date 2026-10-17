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

        // Интерполяторы — значение и приращение локально, синус и polyBLEP — в этом файле (в отладочной сборке,
        // Playgrounds, функции из других файлов на каждом отсчёте не встраиваются).
        var f0V = carrierFrequencyModulation.value, f1V = formantFrequencyModulation.value
        var shapeV = carrierShapeModulation.value, modeV = modeModulation.value
        let f0I = carrierFrequencyModulation.increment, f1I = formantFrequencyModulation.increment
        let shapeI = carrierShapeModulation.increment, modeI = modeModulation.increment
        let lut = r.lutSine
        var next = nextSample
        var i = 0
        while i < size {
            defer { i += 1 }
            var thisSample = next
            next = 0

            f0V += f0I
            f1V += f1I
            let f0 = f0V
            let f1 = f1V

            discontinuityPhase += 2 * f0
            carrierPhase += f0
            let reset = discontinuityPhase >= 1

            if reset {
                discontinuityPhase -= 1
                let resetTime = discontinuityPhase / (2 * f0)

                let carrierPhaseBefore: Float = carrierPhase >= 1 ? 1 : 0.5
                let carrierPhaseAfter: Float = carrierPhase >= 1 ? 0 : 0.5
                let before = z(lut, carrierPhaseBefore, 1, formantPhase + (1 - resetTime) * f1,
                               shapeV + shapeI * (1 - resetTime),
                               modeV + modeI * (1 - resetTime))
                let after = z(lut, carrierPhaseAfter, 0, 0, shapeV + shapeI * 1,
                              modeV + modeI * 1)

                let discontinuity = after - before
                thisSample += discontinuity * (0.5 * resetTime * resetTime)
                let tn = 1 - resetTime
                next += discontinuity * (-0.5 * tn * tn)
                formantPhase = resetTime * f1

                if carrierPhase > 1 {
                    carrierPhase = discontinuityPhase * 0.5
                }
            } else {
                formantPhase += f1
                if formantPhase >= 1 { formantPhase -= 1 }
            }

            if carrierPhase >= 1 { carrierPhase -= 1 }

            shapeV += shapeI
            modeV += modeI
            next += z(lut, carrierPhase, discontinuityPhase, formantPhase, shapeV, modeV)
            out[i] = thisSample
        }
        nextSample = next

        carrierFrequency = f0V
        formantFrequency = f1V
        carrierShape = shapeV
        mode = modeV
    }

    /// Sine(phase) — InterpolateWrap(lut_sine, phase, 512), как PlaitsResources.sine (здесь — чтобы встраивалось).
    @_transparent
    private func sine(_ lut: UnsafePointer<Float>, _ index: Float) -> Float {
        var x = index - Float((index > -2147483648 && index < 2147483648) ? Int(index) : 0)
        x *= 512
        let i = (x > -2147483648 && x < 2147483648) ? Int(x) : 0
        let f = x - Float(i)
        let a = lut[i], b = lut[i + 1]
        return a + (b - a) * f
    }

    @_transparent
    private func z(_ lut: UnsafePointer<Float>, _ c: Float, _ d: Float, _ f: Float, _ shapeIn: Float,
                   _ mode: Float) -> Float {
        var rampDown = 0.5 * (1 + sine(lut, 0.5 * d + 0.25))

        let offset: Float
        let phaseShift: Float
        if mode < 0.333 {
            offset = 1
            phaseShift = 0.25 + mode * 1.50
        } else if mode < 0.666 {
            phaseShift = 0.7495 - (mode - 0.33) * 0.75
            offset = -sine(lut, phaseShift)
        } else {
            phaseShift = 0.7495 - (mode - 0.33) * 0.75
            offset = 0.001
        }

        let discontinuity = sine(lut, f + phaseShift)
        let contour: Float
        if shapeIn < 0.5 {
            let shape = shapeIn * 2
            if c >= 0.5 { rampDown *= shape }
            contour = 1 + (sine(lut, c + 0.25) - 1) * shape
        } else {
            contour = sine(lut, c + shapeIn * 0.5)
        }
        return (rampDown * (offset + discontinuity) - offset) * contour
    }
}
