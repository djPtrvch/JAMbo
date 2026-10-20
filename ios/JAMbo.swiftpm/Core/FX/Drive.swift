import Foundation

// Drive — перенос public/drive-worklet.js 1:1: искажение на шине посыла (только обработанный сигнал), стерео,
// каналы независимо. Цепь: вход → LOW CUT (HP 2-го порядка; ≤ 25 Гц — обход, плавно) → · g (10^(36·DRIVE/100 / 20))
// → 4× оверсэмплинг (oversampler.js) → нелинейность TYPE (SOFT, HARD, TUBE, FUZZ — антипроизводная первого порядка
// по таблицам; FOLD — среднее sin соседних отсчётов) → коррекция среднего → децимация → фильтр DC (5 Гц)
// ÷ компенсация громкости → TONE (LP, 500 Гц · 24^(TONE/100)) → выход. CRUSH — без оверсэмплинга: квантование
// до 12 − 9·D бит и повтор отсчёта 1 + round(15·D²) раз, вход задержан на задержку оверсэмплинга (33).
// Параметры — k-rate: drive (0–100), type (0–5), tone (0–100), lowcut (Гц); DRIVE — по отсчётам за 20 мс,
// TONE и LOW CUT — по блокам; смена TYPE — кроссфейд 20 мс. Тишина дольше 200 мс — выход нули, расчёт пропускается.
// Расчёт — Double, как JS. Состояния каналов — в одном буфере (указатели: без проверок доступа в отладке).

public final class FxDrive {
    static let soft = 0, hard = 1, tube = 2, fuzz = 3, fold = 4, crush = 5
    static let smoothMs: Double = 20
    static let typeFadeMs: Double = 20
    static let dcHz: Double = 5
    static let lowCutMin: Double = 20
    static let lowCutMax: Double = 1000
    static let lowCutOff: Double = 25
    static let toneHz: Double = 500
    static let toneRange: Double = 24
    static let crushBitsMax: Double = 12
    static let crushBitsMin: Double = 3
    static let crushHoldMax: Double = 16
    static let tiny: Double = 1e-18
    static let idleMs: Double = 200
    static let idleLevel: Double = 1e-7
    static let adaaEps: Double = 1e-6
    /// Задержка цепи оверсэмплинга, исходных отсчётов: (64 + 0,5 + 3,5 + 64) / 4.
    static let osDelay = 33
    static let corrLen = 8
    // Раскладка состояния канала (Double): история 66, u 4, y 4, коррекция 16, децимация 258, prevF 4, задержка CRUSH 33,
    // затем prevU, prevS, hold, dcX, dcY, LOW CUT [s1, s2], TONE [s1, s2].
    static let oHist = 0, oU = 66, oY = 70, oCorr = 74, oOs = 90, oPrevF = 348, oCd = 352
    static let oPrevU = 385, oPrevS = 386, oHold = 387, oDcX = 388, oDcY = 389, oLc = 390, oTone = 392
    static let chSize = 394
    // Целые состояния канала: hpos, cpos, opos, cdp, holdN.
    static let iSize = 5

    let sr: Double
    let t: DriveTables
    var started = false
    var drive: Double = 26
    var tone: Double = 50
    var lowcut: Double = 20
    let kSmooth: Double
    var cur = 0
    var prev = 0
    var fade: Double = 1
    let fadeStep: Double
    let kDc: Double
    let st: UnsafeMutablePointer<Double>
    let ist: UnsafeMutablePointer<Int>
    let cLc = UnsafeMutablePointer<Double>.allocate(capacity: 5)
    let cTone = UnsafeMutablePointer<Double>.allocate(capacity: 5)
    var lcSig: Double = .nan
    var toneSig: Double = .nan
    var lcW: Double = 0
    var silent: Double = 0

    public init(sampleRate: Double, tables: DriveTables = .shared) {
        sr = sampleRate
        t = tables
        kSmooth = exp(-1 / ((FxDrive.smoothMs / 1000) * sampleRate))
        fadeStep = 1 / ((FxDrive.typeFadeMs / 1000) * sampleRate)
        kDc = exp((-2 * Double.pi * FxDrive.dcHz) / sampleRate)
        st = UnsafeMutablePointer<Double>.allocate(capacity: 2 * FxDrive.chSize)
        ist = UnsafeMutablePointer<Int>.allocate(capacity: 2 * FxDrive.iSize)
        cLc.initialize(repeating: 0, count: 5)
        cTone.initialize(repeating: 0, count: 5)
        st.initialize(repeating: 0, count: 2 * FxDrive.chSize)
        ist.initialize(repeating: 0, count: 2 * FxDrive.iSize)
    }

    deinit {
        st.deallocate()
        ist.deallocate()
        cLc.deallocate()
        cTone.deallocate()
    }

    /// Состояния каналов — с нуля (как new Channel() веба).
    public func reset() {
        st.update(repeating: 0, count: 2 * FxDrive.chSize)
        ist.update(repeating: 0, count: 2 * FxDrive.iSize)
    }

    /// RBJ (Q = 1/√2) LP или HP → [b0, b1, b2, a1, a2].
    static func rbj(_ out: UnsafeMutablePointer<Double>, hp: Bool, _ f: Double, _ sr: Double) {
        let w: Double = 2 * Double.pi * Swift.min(f, sr * 0.45) / sr
        let cw: Double = cos(w)
        let al: Double = sin(w) / 1.4142135623730951
        let a0: Double = 1 + al
        let b0: Double = (hp ? (1 + cw) / 2 : (1 - cw) / 2) / a0
        out[0] = b0
        out[1] = (hp ? -(1 + cw) : 1 - cw) / a0
        out[2] = b0
        out[3] = (-2 * cw) / a0
        out[4] = (1 - al) / a0
    }

    /// Math.round: половина — вверх.
    @inline(__always) static func jsRound(_ x: Double) -> Double { return (x + 0.5).rounded(.down) }

    /// F(|u|) по таблице (кубический Эрмит; копия DriveTables.tableF — горячий путь в своём файле).
    @inline(__always)
    func tableF(_ F: UnsafeMutablePointer<Double>, _ D: UnsafeMutablePointer<Double>, _ fmax: Double, _ u: Double) -> Double {
        let a: Double = u < 0 ? -u : u
        if a >= 12 { return fmax + (a - 12) }
        let x: Double = a * 32
        let i = Int(x)
        let tt: Double = x - Double(i), t2: Double = tt * tt, t3: Double = t2 * tt
        let h: Double = 0.03125
        return (2 * t3 - 3 * t2 + 1) * F[i] + (t3 - 2 * t2 + tt) * h * D[i] + (-2 * t3 + 3 * t2) * F[i + 1]
            + (t3 - t2) * h * D[i + 1]
    }

    /// Антипроизводные 0–3.
    @inline(__always)
    func anti(_ type: Int, _ u: Double) -> Double {
        switch type {
        case 0: return tableF(t.tanhF, t.tanhD, t.tanhMax, u)
        case 1:
            let a: Double = u < 0 ? -u : u
            return a <= 1 ? 0.5 * u * u : a - 0.5
        case 2: return (tableF(t.tanhF, t.tanhD, t.tanhMax, u + 0.35) - t.lcB - u * t.tb) / t.td
        default: return tableF(t.fuzzF, t.fuzzD, t.fuzzMax, u)
        }
    }

    /// Кривые 0–4.
    @inline(__always)
    func shapeY(_ type: Int, _ u: Double) -> Double {
        switch type {
        case 0: return tanh(u)
        case 1: return u > 1 ? 1 : (u < -1 ? -1 : u)
        case 2: return (tanh(u + 0.35) - t.tb) / t.td
        case 3: return u < 0 ? -(1 - exp(u)) : 1 - exp(-u)
        default: return sin(u)
        }
    }

    /// Нелинейность type по 4 отсчётам u: y[p] += k · кривая (c — состояние канала).
    func shape(_ c: UnsafeMutablePointer<Double>, _ type: Int, _ k: Double) {
        let u = c + FxDrive.oU, y = c + FxDrive.oY
        var u0: Double = c[FxDrive.oPrevU]
        if type == FxDrive.fold {
            var s0: Double = c[FxDrive.oPrevS]
            var p = 0
            while p < 4 {
                let s: Double = sin(u[p])
                y[p] += k * 0.5 * (s + s0)
                s0 = s
                p += 1
            }
            c[FxDrive.oPrevS] = s0
            return
        }
        var F0: Double = c[FxDrive.oPrevF + type]
        var p = 0
        while p < 4 {
            let v: Double = u[p]
            let F: Double = anti(type, v)
            let du: Double = v - u0
            y[p] += k * (abs(du) < FxDrive.adaaEps ? shapeY(type, 0.5 * (v + u0)) : (F - F0) / du)
            u0 = v
            F0 = F
            p += 1
        }
        c[FxDrive.oPrevF + type] = F0
    }

    /// Отсчёт (уже · g) → 4 отсчёта нелинейности (смесь типов a и b, только 0–4) → децимация.
    func wet(_ c: UnsafeMutablePointer<Double>, _ ic: UnsafeMutablePointer<Int>, _ x: Double, _ ta: Int, _ tb: Int,
             _ wa: Double, _ wb: Double, _ ka: Double, _ kb: Double) -> Double {
        let pl = DriveTables.phaseLen
        let hist = c + FxDrive.oHist
        let hp = ic[0]
        hist[hp] = x
        hist[hp + pl] = x
        ic[0] = hp + 1 == pl ? 0 : hp + 1
        let base = hp + pl
        let u = c + FxDrive.oU
        u[0] = t.ph0Gain * hist[base - DriveTables.ph0Delay]
        let phases = t.phases
        var p = 1
        while p < 4 {
            let f = phases + p * pl
            var s: Double = 0
            var j = 0
            while j < pl {
                s += f[j] * hist[base - j]
                j += 1
            }
            u[p] = s
            p += 1
        }
        let y = c + FxDrive.oY
        y[0] = 0; y[1] = 0; y[2] = 0; y[3] = 0
        if wa > 0 && ta != FxDrive.crush { shape(c, ta, wa / ka) }
        if wb > 0 && tb != FxDrive.crush { shape(c, tb, wb / kb) }
        // Состояния кривых, которые сейчас не считались, — на текущий отсчёт (вход в них без скачка).
        let last: Double = u[3]
        var tt = 0
        while tt < 4 {
            if tt != ta && tt != tb { c[FxDrive.oPrevF + tt] = anti(tt, last) }
            tt += 1
        }
        if ta != FxDrive.fold && tb != FxDrive.fold { c[FxDrive.oPrevS] = sin(last) }
        c[FxDrive.oPrevU] = last
        // Коррекция среднего (1 − sin⁸) и децимация.
        let cb = c + FxDrive.oCorr, os = c + FxDrive.oOs
        let cl = FxDrive.corrLen, fl = DriveTables.firLen
        let k0: Double = -1.0 / 128, k1: Double = 9.0 / 128, k2: Double = -37.0 / 128, k3: Double = 93.0 / 128
        // Позиции колец — в локальных переменных (Swift 6.0.3 на Linux с -O падал на ic[1] в цикле).
        var cp: Int = ic[1]
        var op: Int = ic[2]
        p = 0
        while p < 4 {
            cb[cp] = y[p]
            cb[cp + cl] = y[p]
            let e = cp + cl
            cp = cp + 1 == cl ? 0 : cp + 1
            let yc: Double = k0 * (cb[e] + cb[e - 7]) + k1 * (cb[e - 1] + cb[e - 6]) + k2 * (cb[e - 2] + cb[e - 5])
                + k3 * (cb[e - 3] + cb[e - 4])
            os[op] = yc
            os[op + fl] = yc
            op = op + 1 == fl ? 0 : op + 1
            p += 1
        }
        ic[1] = cp
        ic[2] = op
        let ob = op + fl - 1
        let dc = DriveTables.decC
        var out: Double = t.decMid * os[ob - dc]
        let lst = ob - (fl - 1)
        let dh = t.decHalf
        var j = 0
        while j < dc {
            out += dh[j] * (os[ob - j] + os[lst + j])
            j += 1
        }
        return out
    }

    /// Блок n отсчётов: вход (nil — тишина) → outL/outR (перезаписывает). Параметры — как AudioParam (Float).
    public func process(inL: UnsafePointer<Float>?, inR: UnsafePointer<Float>?, outL: UnsafeMutablePointer<Float>,
                        outR: UnsafeMutablePointer<Float>, frames n: Int, drive dIn: Float, type tIn: Float,
                        tone toIn: Float, lowcut lIn: Float) {
        let sr: Double = self.sr
        let driveT: Double = Swift.max(0, Swift.min(100, Double(dIn)))
        let toneT: Double = Swift.max(0, Swift.min(100, Double(toIn)))
        let lcT: Double = Swift.max(FxDrive.lowCutMin, Swift.min(FxDrive.lowCutMax, Double(lIn)))
        let type = Int(Swift.max(0, Swift.min(5, FxDrive.jsRound(Double(tIn)))))
        if !started {
            started = true
            drive = driveT; tone = toneT; lowcut = lcT; cur = type; prev = type
            lcW = lcT > FxDrive.lowCutOff ? 1 : 0
        }
        if type != cur {
            // Смена TYPE: кроссфейд 20 мс; новая кривая начинает антипроизводную с текущего отсчёта.
            prev = fade >= 0.5 ? cur : prev
            cur = type
            fade = 0
            for k in 0..<2 {
                let c = st + k * FxDrive.chSize
                if type < 4 { c[FxDrive.oPrevF + type] = anti(type, c[FxDrive.oPrevU]) }
                if type == FxDrive.fold { c[FxDrive.oPrevS] = sin(c[FxDrive.oPrevU]) }
            }
        }
        // TONE и LOW CUT — по блокам (сглаживание за 20 мс), коэффициенты — при изменении.
        let kb: Double = pow(kSmooth, Double(n))
        tone = toneT + (tone - toneT) * kb
        if abs(tone - toneT) < 1e-3 { tone = toneT }
        lowcut = exp(log(lcT) + (log(lowcut) - log(lcT)) * kb)
        if abs(lowcut - lcT) < 1e-3 { lowcut = lcT }
        if tone != toneSig {
            toneSig = tone
            FxDrive.rbj(cTone, hp: false, FxDrive.toneHz * pow(FxDrive.toneRange, tone / 100), sr)
        }
        if lowcut != lcSig {
            lcSig = lowcut
            FxDrive.rbj(cLc, hp: true, Swift.max(FxDrive.lowCutMin, lowcut), sr)
        }
        // LOW CUT ≤ 25 Гц — обход: доля фильтра плавно 0 ↔ 1.
        let lcW0: Double = lcW
        let lcW1: Double = lowcut > FxDrive.lowCutOff ? 1 : 0
        lcW = lcW0 + (lcW1 - lcW0) * (1 - kb)
        if abs(lcW - lcW1) < 1e-4 { lcW = lcW1 }

        // Покой: на входе тишина дольше 200 мс — выход нули.
        var peak: Double = 0
        var ch = 0
        while ch < 2 {
            if let a = ch == 0 ? inL : inR {
                var i = 0
                while i < n {
                    let v = Double(abs(a[i]))
                    if v > peak { peak = v }
                    i += 1
                }
            }
            ch += 1
        }
        silent = peak < FxDrive.idleLevel ? silent + Double(n) : 0
        if silent > (FxDrive.idleMs / 1000) * sr {
            outL.update(repeating: 0, count: n)
            outR.update(repeating: 0, count: n)
            drive = driveT
            if fade < 1 { fade = 1 }
            return
        }
        let ks: Double = kSmooth, kDc: Double = self.kDc, cLc = self.cLc, cTone = self.cTone
        let tiny: Double = FxDrive.tiny
        let comp = t.comp
        let cn = DriveTables.compN + 2
        let pl = DriveTables.phaseLen
        let lcWEnd: Double = lcW
        var bad = false
        var i = 0
        while i < n {
            drive = driveT + (drive - driveT) * ks
            if fade < 1 { fade = Swift.min(1, fade + fadeStep) }
            let D: Double = drive / 100
            let dB: Double = 36 * D
            let g: Double = exp(dB * 0.11512925464970229)
            let ci: Double = dB / 0.1
            let i0f: Double = ci.rounded(.down)
            let i0 = Int(i0f)
            let fr: Double = ci - i0f
            let ta = prev, tb = cur
            let wb: Double = fade
            let wa: Double = ta == tb ? 0 : 1 - wb
            let ka: Double = ta == FxDrive.crush ? 1 : comp[ta * cn + i0] + (comp[ta * cn + i0 + 1] - comp[ta * cn + i0]) * fr
            let kB: Double = tb == FxDrive.crush ? 1 : comp[tb * cn + i0] + (comp[tb * cn + i0 + 1] - comp[tb * cn + i0]) * fr
            let osNeeded: Bool = (wa > 0 && ta != FxDrive.crush) || (wb > 0 && tb != FxDrive.crush)
            let crW: Double = (ta == FxDrive.crush ? wa : 0) + (tb == FxDrive.crush ? wb : 0)
            // CRUSH: шаг квантования 2^(1 − B), B = 12 − 9·D; повтор N = 1 + round(15·D²).
            let step: Double = pow(2, 1 - (FxDrive.crushBitsMax - (FxDrive.crushBitsMax - FxDrive.crushBitsMin) * D))
            let holdN = 1 + Int(FxDrive.jsRound((FxDrive.crushHoldMax - 1) * D * D))
            let lcw: Double = lcW0 + (lcWEnd - lcW0) * (Double(i + 1) / Double(n))
            var k = 0
            while k < 2 {
                let c = st + k * FxDrive.chSize
                let ic = ist + k * FxDrive.iSize
                var x: Double = 0
                if k == 0 { if let p = inL { x = Double(p[i]) } } else if let p = inR { x = Double(p[i]) }
                // LOW CUT (до искажения), TDF-II.
                let lc = c + FxDrive.oLc
                let xl: Double = cLc[0] * x + lc[0]
                lc[0] = cLc[1] * x - cLc[3] * xl + lc[1]
                lc[1] = cLc[2] * x - cLc[4] * xl
                x += (xl - x) * lcw
                var y: Double = 0
                if osNeeded {
                    y = wet(c, ic, x * g, ta, tb, wa, wb, ka, kB)
                } else {
                    // История оверсэмплера идёт дальше — вход в него потом без скачка.
                    let hp = ic[0]
                    c[FxDrive.oHist + hp] = x * g
                    c[FxDrive.oHist + hp + pl] = x * g
                    ic[0] = hp + 1 == pl ? 0 : hp + 1
                }
                // CRUSH — на входе, задержанном на задержку оверсэмплинга.
                let dp = ic[3]
                let xd: Double = c[FxDrive.oCd + dp]
                c[FxDrive.oCd + dp] = x
                ic[3] = dp + 1 == FxDrive.osDelay ? 0 : dp + 1
                if crW > 0 {
                    if ic[4] <= 0 {
                        var q: Double = step * FxDrive.jsRound(xd / step)
                        if q > 1 - step { q = 1 - step } else if q < -1 { q = -1 }
                        c[FxDrive.oHold] = q
                        ic[4] = holdN
                    }
                    ic[4] -= 1
                    y += crW * c[FxDrive.oHold]
                } else {
                    ic[4] = 0
                }
                // Фильтр DC (HP 1-го порядка 5 Гц), TONE (TDF-II).
                let hpY: Double = kDc * (c[FxDrive.oDcY] + y - c[FxDrive.oDcX]) + tiny
                c[FxDrive.oDcX] = y
                c[FxDrive.oDcY] = hpY
                let tn = c + FxDrive.oTone
                y = cTone[0] * hpY + tn[0]
                tn[0] = cTone[1] * hpY - cTone[3] * y + tn[1]
                tn[1] = cTone[2] * hpY - cTone[4] * y
                if k == 0 { outL[i] = Float(y) } else { outR[i] = Float(y) }
                if !(y == y) || abs(y) > 1e6 { bad = true }
                k += 1
            }
            i += 1
        }
        if bad {
            // NaN или разнос — тишина и сброс состояний.
            reset()
            outL.update(repeating: 0, count: n)
            outR.update(repeating: 0, count: n)
        }
    }
}
