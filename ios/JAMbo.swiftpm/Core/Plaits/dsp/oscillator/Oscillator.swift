// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/oscillator.h.

/// OscillatorShape (порядок важен: в Render сравнивается «≤ SAW», «≤ SLOPE»).
enum OscillatorShape: Int {
    case impulseTrain, saw, triangle, slope, square, squareBright, squareDark, squareTriangle
}

/// Генератор polyBLEP с выбором формы; внешняя FM и FM через ноль.
struct Oscillator {
    private var phase: Float = 0.5
    private var nextSample: Float = 0
    private var lpState: Float = 1
    private var hpState: Float = 0
    private var high = true

    private var frequency: Float = 0.001
    private var pw: Float = 0.5

    init() {}

    /// Render<shape>(frequency, pw, out, size).
    @inline(__always)
    mutating func render(_ shape: OscillatorShape, _ frequency: Float, _ pw: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        render(shape, externalFm: false, throughZeroFm: false, frequency, pw, nil, out, size)
    }

    /// Render<shape>(frequency, pw, fm, out, size): с fm — FM через ноль.
    @inline(__always)
    mutating func render(_ shape: OscillatorShape, _ frequency: Float, _ pw: Float, fm: UnsafePointer<Float>?,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        if let fm {
            render(shape, externalFm: true, throughZeroFm: true, frequency, pw, fm, out, size)
        } else {
            render(shape, externalFm: false, throughZeroFm: false, frequency, pw, nil, out, size)
        }
    }

    /// Render<shape, has_external_fm, through_zero_fm>: параметры шаблона — аргументы встроенной функции.
    @inline(__always)
    mutating func render(_ shape: OscillatorShape, externalFm hasExternalFm: Bool, throughZeroFm: Bool,
                         _ frequencyIn: Float, _ pwIn: Float, _ externalFmIn: UnsafePointer<Float>?,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequencyTarget = frequencyIn
        var pwTarget = pwIn
        if !hasExternalFm {
            if !throughZeroFm {
                constrain(&frequencyTarget, kMinFrequency, kMaxFrequency)
            } else {
                constrain(&frequencyTarget, -kMaxFrequency, kMaxFrequency)
            }
            constrain(&pwTarget, abs(frequencyTarget) * 2, 1 - 2 * abs(frequencyTarget))
        }

        var fm = ParameterInterpolator(frequency, frequencyTarget, size)
        var pwm = ParameterInterpolator(pw, pwTarget, size)
        let shapeIndex = shape.rawValue
        var externalFm = externalFmIn

        var next = nextSample
        for i in 0..<size {
            var thisSample = next
            next = 0

            var f = fm.next()
            if hasExternalFm, let e = externalFm {
                f *= 1 + e.pointee
                externalFm = e + 1
                if !throughZeroFm {
                    constrain(&f, kMinFrequency, kMaxFrequency)
                } else {
                    constrain(&f, -kMaxFrequency, kMaxFrequency)
                }
            }
            var pwNow: Float = (shape == .squareTriangle || shape == .triangle) ? 0.5 : pwm.next()
            if hasExternalFm {
                constrain(&pwNow, abs(f) * 2, 1 - 2 * abs(f))
            }
            phase += f

            if shapeIndex <= OscillatorShape.saw.rawValue {
                if phase >= 1 {
                    phase -= 1
                    let t = phase / f
                    thisSample -= thisBlepSample(t)
                    next -= nextBlepSample(t)
                } else if throughZeroFm && phase < 0 {
                    let t = phase / f
                    phase += 1
                    thisSample += thisBlepSample(t)
                    next += nextBlepSample(t)
                }
                next += phase

                if shape == .saw {
                    out[i] = 2 * thisSample - 1
                } else {
                    lpState += 0.25 * ((hpState - thisSample) - lpState)
                    out[i] = 4 * lpState
                    hpState = thisSample
                }
            } else if shapeIndex <= OscillatorShape.slope.rawValue {
                var slopeUp: Float = 2
                var slopeDown: Float = 2
                if shape == .slope {
                    slopeUp = 1 / pwNow
                    slopeDown = 1 / (1 - pwNow)
                }
                if high != (phase < pwNow) {
                    let t = (phase - pwNow) / f
                    var discontinuity = (slopeUp + slopeDown) * f
                    if throughZeroFm && f < 0 { discontinuity = -discontinuity }
                    thisSample -= thisIntegratedBlepSample(t) * discontinuity
                    next -= nextIntegratedBlepSample(t) * discontinuity
                    high = phase < pwNow
                }
                if phase >= 1 {
                    phase -= 1
                    let t = phase / f
                    let discontinuity = (slopeUp + slopeDown) * f
                    thisSample += thisIntegratedBlepSample(t) * discontinuity
                    next += nextIntegratedBlepSample(t) * discontinuity
                    high = true
                } else if throughZeroFm && phase < 0 {
                    let t = phase / f
                    phase += 1
                    let discontinuity = (slopeUp + slopeDown) * f
                    thisSample -= thisIntegratedBlepSample(t) * discontinuity
                    next -= nextIntegratedBlepSample(t) * discontinuity
                    high = false
                }
                next += high ? phase * slopeUp : 1 - (phase - pwNow) * slopeDown
                out[i] = 2 * thisSample - 1
            } else {
                if high != (phase >= pwNow) {
                    let t = (phase - pwNow) / f
                    var discontinuity: Float = 1
                    if throughZeroFm && f < 0 { discontinuity = -discontinuity }
                    thisSample += thisBlepSample(t) * discontinuity
                    next += nextBlepSample(t) * discontinuity
                    high = phase >= pwNow
                }
                if phase >= 1 {
                    phase -= 1
                    let t = phase / f
                    thisSample -= thisBlepSample(t)
                    next -= nextBlepSample(t)
                    high = false
                } else if throughZeroFm && phase < 0 {
                    let t = phase / f
                    phase += 1
                    thisSample += thisBlepSample(t)
                    next += nextBlepSample(t)
                    high = true
                }
                next += phase < pwNow ? 0 : 1

                if shape == .squareTriangle {
                    let integratorCoefficient = f * 0.0625
                    thisSample = 128 * (thisSample - 0.5)
                    lpState += integratorCoefficient * (thisSample - lpState)
                    out[i] = lpState
                } else if shape == .squareDark {
                    let integratorCoefficient = f * 2
                    thisSample = 4 * (thisSample - 0.5)
                    lpState += integratorCoefficient * (thisSample - lpState)
                    out[i] = lpState
                } else if shape == .squareBright {
                    let integratorCoefficient = f * 2
                    thisSample = 2 * thisSample - 1
                    lpState += integratorCoefficient * (thisSample - lpState)
                    out[i] = (thisSample - lpState) * 0.5
                } else {
                    thisSample = 2 * thisSample - 1
                    out[i] = thisSample
                }
            }
        }
        nextSample = next

        frequency = fm.value
        pw = pwm.value
    }
}
