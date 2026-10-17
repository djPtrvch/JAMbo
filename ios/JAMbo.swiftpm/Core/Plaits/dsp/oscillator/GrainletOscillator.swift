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

        // Интерполяторы — значение и приращение локально, синус и polyBLEP — в этом файле (в отладочной сборке,
        // Playgrounds, функции из других файлов на каждом отсчёте не встраиваются).
        var f0V = carrierFrequencyModulation.value, f1V = formantFrequencyModulation.value
        var shapeV = carrierShapeModulation.value, bleedV = carrierBleedModulation.value
        let f0I = carrierFrequencyModulation.increment, f1I = formantFrequencyModulation.increment
        let shapeI = carrierShapeModulation.increment, bleedI = carrierBleedModulation.increment
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

            carrierPhase += f0
            let reset = carrierPhase >= 1

            if reset {
                carrierPhase -= 1
                let resetTime = carrierPhase / f0
                let before = grainlet(lut, 1, formantPhase + (1 - resetTime) * f1,
                                      shapeV + shapeI * (1 - resetTime),
                                      bleedV + bleedI * (1 - resetTime))
                let after = grainlet(lut, 0, 0, shapeV + shapeI * 1,
                                     bleedV + bleedI * 1)
                let discontinuity = after - before
                thisSample += discontinuity * (0.5 * resetTime * resetTime)
                let tn = 1 - resetTime
                next += discontinuity * (-0.5 * tn * tn)
                formantPhase = resetTime * f1
            } else {
                formantPhase += f1
                if formantPhase >= 1 { formantPhase -= 1 }
            }

            shapeV += shapeI
            bleedV += bleedI
            next += grainlet(lut, carrierPhase, formantPhase, shapeV, bleedV)
            out[i] = thisSample
        }
        nextSample = next

        carrierFrequency = f0V
        formantFrequency = f1V
        carrierShape = shapeV
        carrierBleed = bleedV
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
    private func carrier(_ lut: UnsafePointer<Float>, _ phaseIn: Float, _ shapeIn: Float) -> Float {
        var phase = phaseIn
        let shape = shapeIn * 3
        let shapeIntegral = (shape > -2147483648 && shape < 2147483648) ? Int(shape) : 0
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
        return (sine(lut, phase) + 1) * 0.25
    }

    @_transparent
    private func grainlet(_ lut: UnsafePointer<Float>, _ carrierPhase: Float, _ formantPhase: Float,
                          _ shape: Float, _ bleed: Float) -> Float {
        let c = carrier(lut, carrierPhase, shape)
        let formant = sine(lut, formantPhase)
        return c * (formant + bleed) / (1 + bleed)
    }
}
