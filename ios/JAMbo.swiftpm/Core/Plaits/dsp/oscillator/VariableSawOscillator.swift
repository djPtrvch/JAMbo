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

        // Интерполяторы — значение и приращение локально, polyBLEP — формулами, константа — локально: в отладочной
        // сборке (Playgrounds) вызовы и глобальные константы из других файлов на каждом отсчёте не встраиваются.
        var fV = fm.value, pwV = pwm.value, shapeV = waveshapeModulation.value
        let fI = fm.increment, pwI = pwm.increment, shapeI = waveshapeModulation.increment
        let notchDepth = kVariableSawNotchDepth
        @_transparent func thisBlep(_ t: Float) -> Float { 0.5 * t * t }
        @_transparent func nextBlep(_ t0: Float) -> Float {
            let t = 1 - t0
            return -0.5 * t * t
        }
        @_transparent func nextIntBlep(_ t: Float) -> Float {
            let t1 = 0.5 * t
            let t2 = t1 * t1
            let t4 = t2 * t2
            return 0.1875 - t1 + 1.5 * t2 - t4
        }
        @_transparent func thisIntBlep(_ t: Float) -> Float { nextIntBlep(1 - t) }
        var next = nextSample
        var i = 0
        while i < size {
            defer { i += 1 }
            var thisSample = next
            next = 0

            fV += fI
            pwV += pwI
            shapeV += shapeI
            let f = fV
            let pwNow = pwV
            let shape = shapeV
            let triangleAmount = shape
            let notchAmount = 1 - shape
            let slopeUp = 1 / pwNow
            let slopeDown = 1 / (1 - pwNow)

            phase += f

            if !high && phase >= pwNow {
                let triangleStep = (slopeUp + slopeDown) * f * triangleAmount
                let notch = (notchDepth + 1 - pwNow) * notchAmount
                let t = (phase - pwNow) / (previousPw - pwNow + f)
                thisSample += notch * thisBlep(t)
                next += notch * nextBlep(t)
                thisSample -= triangleStep * thisIntBlep(t)
                next -= triangleStep * nextIntBlep(t)
                high = true
            } else if phase >= 1 {
                phase -= 1
                let triangleStep = (slopeUp + slopeDown) * f * triangleAmount
                let notch = (notchDepth + 1) * notchAmount
                let t = phase / f
                thisSample -= notch * thisBlep(t)
                next -= notch * nextBlep(t)
                thisSample += triangleStep * thisIntBlep(t)
                next += triangleStep * nextIntBlep(t)
                high = false
            }

            next += naiveSample(phase, pwNow, slopeUp, slopeDown, triangleAmount, notchAmount)
            previousPw = pwNow

            out[i] = (2 * thisSample - 1) / (1 + notchDepth)
        }
        nextSample = next

        frequency = fV
        pw = pwV
        waveshape = shapeV
    }

    @_transparent
    private func naiveSample(_ phase: Float, _ pw: Float, _ slopeUp: Float, _ slopeDown: Float,
                             _ triangleAmount: Float, _ notchAmount: Float) -> Float {
        let notchSaw = phase < pw ? phase : 1 + kVariableSawNotchDepth
        let triangle = phase < pw ? phase * slopeUp : 1 - (phase - pw) * slopeDown
        return notchSaw * notchAmount + triangle * triangleAmount
    }
}
