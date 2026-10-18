import Foundation

// Коэффициенты биквада полосы EQ — как Biquad::Set*Params в Blink/WebKit (формулы Web Audio: peaking, lowshelf и
// highshelf с S = 1, highpass и lowpass с Q в dB, notch, bandpass — фильтр детектора Dynamic, тип
// EqDetectors.bandpass; частота — доля Найквиста, края 0 и 1 — как там же),
// и АЧХ полосы для кривой EQ (как getFrequencyResponse; каскад — сумма ступеней).

public enum EqCoeffs {
    /// Коэффициенты полосы (тип EqSpec.types; частота, Гц; усиление, dB; Q фильтра) — как Biquad::Set*Params.
    static func coeffs(_ type: Int, _ hz: Double, _ db: Double, _ q: Double, _ sr: Double,
                       _ out: UnsafeMutablePointer<Double>) {
        let f: Double = Swift.max(0, Swift.min(1, hz / (sr * 0.5)))
        var b0: Double = 1, b1: Double = 0, b2: Double = 0, a0: Double = 1, a1: Double = 0, a2: Double = 0
        let w0: Double = Double.pi * f
        let k: Double = cos(w0)
        switch type {
        case EqSpec.bell:
            let A: Double = pow(10, db / 40)
            if f > 0 && f < 1 {
                if q > 0 {
                    let alpha: Double = sin(w0) / (2 * q)
                    b0 = 1 + alpha * A
                    b1 = -2 * k
                    b2 = 1 - alpha * A
                    a0 = 1 + alpha / A
                    a1 = -2 * k
                    a2 = 1 - alpha / A
                } else {
                    b0 = A * A
                }
            }
        case EqSpec.lowShelf, EqSpec.highShelf:
            let A: Double = pow(10, db / 40)
            let low = type == EqSpec.lowShelf
            if f >= 1 {
                b0 = low ? A * A : 1
            } else if f <= 0 {
                b0 = low ? 1 : A * A
            } else {
                let alpha: Double = 0.5 * sin(w0) * 1.4142135623730951
                let k2: Double = 2 * A.squareRoot() * alpha
                let ap: Double = A + 1
                let am: Double = A - 1
                if low {
                    b0 = A * (ap - am * k + k2)
                    b1 = 2 * A * (am - ap * k)
                    b2 = A * (ap - am * k - k2)
                    a0 = ap + am * k + k2
                    a1 = -2 * (am + ap * k)
                    a2 = ap + am * k - k2
                } else {
                    b0 = A * (ap + am * k + k2)
                    b1 = -2 * A * (am + ap * k)
                    b2 = A * (ap + am * k - k2)
                    a0 = ap - am * k + k2
                    a1 = 2 * (am - ap * k)
                    a2 = ap - am * k - k2
                }
            }
        case EqSpec.lowCut, EqSpec.highCut:
            let high = type == EqSpec.lowCut
            if f >= 1 {
                b0 = high ? 0 : 1
            } else if f <= 0 {
                b0 = high ? 1 : 0
            } else {
                let g: Double = pow(10, 0.05 * q)
                let alpha: Double = sin(w0) / (2 * g)
                let beta: Double = high ? (1 + k) / 2 : (1 - k) / 2
                b0 = beta
                b1 = high ? -2 * beta : 2 * beta
                b2 = beta
                a0 = 1 + alpha
                a1 = -2 * k
                a2 = 1 - alpha
            }
        case EqSpec.notch:
            if f > 0 && f < 1 && q > 0 {
                let alpha: Double = sin(w0) / (2 * q)
                b0 = 1
                b1 = -2 * k
                b2 = 1
                a0 = 1 + alpha
                a1 = -2 * k
                a2 = 1 - alpha
            } else if f > 0 && f < 1 {
                b0 = 0
            }
        case EqDetectors.bandpass:
            if f > 0 && f < 1 {
                if q > 0 {
                    let alpha: Double = sin(w0) / (2 * q)
                    b0 = alpha
                    b1 = 0
                    b2 = -alpha
                    a0 = 1 + alpha
                    a1 = -2 * k
                    a2 = 1 - alpha
                }
            } else {
                b0 = 0
            }
        default:
            break
        }
        let inv: Double = 1 / a0
        out[0] = b0 * inv
        out[1] = b1 * inv
        out[2] = b2 * inv
        out[3] = a1 * inv
        out[4] = a2 * inv
    }

    /// АЧХ полосы на частоте hz, dB (для кривой EQ; каскад — сумма ступеней), как getFrequencyResponse.
    public static func response(_ b: EqBand, hz: Double, sampleRate: Double = 48000) -> Double {
        return response(b, hz: [hz], sampleRate: sampleRate)[0]
    }

    /// АЧХ полосы на частотах hz, dB (коэффициенты — один раз на полосу).
    public static func response(_ b: EqBand, hz: [Double], sampleRate: Double = 48000) -> [Double] {
        let c = UnsafeMutablePointer<Double>.allocate(capacity: 5)
        defer { c.deallocate() }
        coeffs(b.type, b.freq, EqSpec.hasGain(b.type) ? b.gain : 0, EqSpec.filterQ(b), sampleRate, c)
        let n: Double = Double(EqSpec.stages(b))
        return hz.map { f in
            let w: Double = 2 * Double.pi * f / sampleRate
            let c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
            let nr = c[0] + c[1] * c1 + c[2] * c2, ni = -(c[1] * s1 + c[2] * s2)
            let dr = 1 + c[3] * c1 + c[4] * c2, di = -(c[3] * s1 + c[4] * s2)
            let mag = ((nr * nr + ni * ni) / Swift.max(1e-30, dr * dr + di * di)).squareRoot()
            return n * 20 * log10(Swift.max(1e-6, mag))
        }
    }
}
