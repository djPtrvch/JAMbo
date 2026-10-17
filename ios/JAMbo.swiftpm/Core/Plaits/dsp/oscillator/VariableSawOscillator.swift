// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/variable_saw_oscillator.h.

let kVariableSawNotchDepth: Float = 0.2

/// Пила с вырезом (notch) ↔ треугольник с переменной симметрией, polyBLEP.
struct VariableSawOscillator {
    private var phase: Float = 0
    private var nextSample: Float = 0
    private var previousPw: Float = 0.5
    private var high = false

    private var frequency: Float = 0.01
    private var pw: Float = 0.5
    private var waveshape: Float = 0

    init() {}

    @inline(__always)
    mutating func render(_ frequencyIn: Float, _ pwIn: Float, _ waveshapeIn: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequencyTarget = frequencyIn
        var pwTarget = pwIn
        if frequencyTarget >= kMaxFrequency { frequencyTarget = kMaxFrequency }
        if frequencyTarget >= 0.25 {
            pwTarget = 0.5
        } else {
            constrain(&pwTarget, frequencyTarget * 2, 1 - 2 * frequencyTarget)
        }

        var fm = ParameterInterpolator(frequency, frequencyTarget, size)
        var pwm = ParameterInterpolator(pw, pwTarget, size)
        var waveshapeModulation = ParameterInterpolator(waveshape, waveshapeIn, size)

        var next = nextSample
        for i in 0..<size {
            var thisSample = next
            next = 0

            let f = fm.next()
            let pwNow = pwm.next()
            let shape = waveshapeModulation.next()
            let triangleAmount = shape
            let notchAmount = 1 - shape
            let slopeUp = 1 / pwNow
            let slopeDown = 1 / (1 - pwNow)

            phase += f

            if !high && phase >= pwNow {
                let triangleStep = (slopeUp + slopeDown) * f * triangleAmount
                let notch = (kVariableSawNotchDepth + 1 - pwNow) * notchAmount
                let t = (phase - pwNow) / (previousPw - pwNow + f)
                thisSample += notch * thisBlepSample(t)
                next += notch * nextBlepSample(t)
                thisSample -= triangleStep * thisIntegratedBlepSample(t)
                next -= triangleStep * nextIntegratedBlepSample(t)
                high = true
            } else if phase >= 1 {
                phase -= 1
                let triangleStep = (slopeUp + slopeDown) * f * triangleAmount
                let notch = (kVariableSawNotchDepth + 1) * notchAmount
                let t = phase / f
                thisSample -= notch * thisBlepSample(t)
                next -= notch * nextBlepSample(t)
                thisSample += triangleStep * thisIntegratedBlepSample(t)
                next += triangleStep * nextIntegratedBlepSample(t)
                high = false
            }

            next += naiveSample(phase, pwNow, slopeUp, slopeDown, triangleAmount, notchAmount)
            previousPw = pwNow

            out[i] = (2 * thisSample - 1) / (1 + kVariableSawNotchDepth)
        }
        nextSample = next

        frequency = fm.value
        pw = pwm.value
        waveshape = waveshapeModulation.value
    }

    @inline(__always)
    private func naiveSample(_ phase: Float, _ pw: Float, _ slopeUp: Float, _ slopeDown: Float,
                             _ triangleAmount: Float, _ notchAmount: Float) -> Float {
        let notchSaw = phase < pw ? phase : 1 + kVariableSawNotchDepth
        let triangle = phase < pw ? phase * slopeUp : 1 - (phase - pw) * slopeDown
        return notchSaw * notchAmount + triangle * triangleAmount
    }
}
