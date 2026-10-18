import Foundation

// Динамические полосы в EqUnit (S7b): детекторы цепочки (EqDetectors) и коэффициенты полосы на каждый отсчёт со
// сдвигом усиления — как BiquadFilterNode веба с входом в gain (a-rate: коэффициенты на каждый отсчёт). Пока частота
// и Q не сглаживаются, синус и косинус — один раз на квант, на отсчёт — только усиление (формулы — как в
// EqCoeffs); тот же сдвиг, что в прошлом отсчёте, — те же коэффициенты.

extension EqUnit {
    /// Сдвиг усиления полосы k текущей цепочки в конце блока, dB (для экрана).
    public func dynOffset(_ k: Int) -> Float { return det.last[cur * EqUnit.bands + k] }

    /// Детекторы цепочки c на блок n отсчётов.
    func runDetectors(_ c: Int, _ n: Int) {
        var k = 0
        while k < EqUnit.bands {
            let i = c * EqUnit.bands + k
            let s = det.src[i]
            k += 1
            if s < 0 { continue }
            if s == 0 {
                det.run(i, selfL, selfR, n, sr: sr, decay: decay)
            } else if s <= SoundData.maxTracks, let l = trackL, let r = trackR {
                det.run(i, l + (s - 1) * trackStride, r + (s - 1) * trackStride, n, sr: sr, decay: decay)
            } else {
                det.run(i, nil, nil, n, sr: sr, decay: decay)
            }
        }
    }

    /// В n отсчётах есть ненулевой сдвиг.
    @inline(__always)
    static func nonZero(_ x: UnsafeMutablePointer<Float>, _ n: Int) -> Bool {
        var i = 0
        while i < n {
            if x[i] != 0 { return true }
            i += 1
        }
        return false
    }

    /// Коэффициенты полосы i: траектория сглаживания в отсчёте e (если она идёт) и сдвиг Dynamic off, dB.
    func coeffsAt(_ i: Int, _ mov: Bool, _ e: Double, _ off: Double, _ out: UnsafeMutablePointer<Double>) {
        let x: Double = mov ? exp(e * decay) : 0
        let f: Double = tf[i] + (sf[i] - tf[i]) * x
        let g: Double = tg[i] + (sg[i] - tg[i]) * x + off
        let q: Double = tq[i] + (sq[i] - tq[i]) * x
        EqCoeffs.coeffs(kind[i], f, g, q, sr, out)
    }

    /// Коэффициенты полосы i на m отсчётов (по 5): траектория с отсчёта e0 (mov) и сдвиги off.
    func fillCoeffs(_ i: Int, _ mov: Bool, _ e0: Int, _ off: UnsafeMutablePointer<Float>, _ m: Int,
                    _ out: UnsafeMutablePointer<Double>) {
        let t: Int = kind[i]
        let f: Double = Swift.max(0, Swift.min(1, tf[i] / (sr * 0.5)))
        let q: Double = tq[i]
        if mov || f <= 0 || f >= 1 || q <= 0 || t > EqSpec.highShelf {
            var j = 0
            while j < m {
                coeffsAt(i, mov, Double(e0 + j), Double(off[j]), out + j * 5)
                j += 1
            }
            return
        }
        let g0: Double = tg[i]
        let w0: Double = Double.pi * f
        let k: Double = cos(w0)
        let sn: Double = sin(w0)
        let bell: Bool = t == EqSpec.bell
        let low: Bool = t == EqSpec.lowShelf
        let alphaBell: Double = sn / (2 * q)
        let alphaShelf: Double = 0.5 * sn * 1.4142135623730951
        var prev: Float = 0
        var j = 0
        while j < m {
            let o = out + j * 5
            let v: Float = off[j]
            if j > 0 && v == prev {
                o[0] = o[-5]
                o[1] = o[-4]
                o[2] = o[-3]
                o[3] = o[-2]
                o[4] = o[-1]
                j += 1
                continue
            }
            prev = v
            let A: Double = pow(10, (g0 + Double(v)) / 40)
            var b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double
            if bell {
                b0 = 1 + alphaBell * A
                b1 = -2 * k
                b2 = 1 - alphaBell * A
                a0 = 1 + alphaBell / A
                a1 = -2 * k
                a2 = 1 - alphaBell / A
            } else {
                let k2: Double = 2 * A.squareRoot() * alphaShelf
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
            let inv: Double = 1 / a0
            o[0] = b0 * inv
            o[1] = b1 * inv
            o[2] = b2 * inv
            o[3] = a1 * inv
            o[4] = a2 * inv
            j += 1
        }
    }
}
