import Foundation

// Сатуратор мастера — перенос public/saturator-worklet.js (решение пользователя S5a: без BIAS, OUTPUT, AUTO —
// они стоят на значениях по умолчанию 0, 0 dB, ON, звук тот же). Стерео, каналы независимо.
// Вход · DRIVE → 4× оверсэмплинг (oversampler.js) → TAPE / TUBE / EDGE с антипроизводной ÷ компенсация громкости →
// коррекция среднего → децимация → фильтр DC (TUBE) → TONE (shelf 1 кГц) → смесь с сухим (MIX · smoothstep(DRIVE, 0…1 dB)).
// FOCUS: x = LP + HP (однополюсный, 20 Гц — OFF), кривая — на HP, LP — чистый с той же задержкой (33).
// DRIVE 0 или MIX 0 — выход = сухой с задержкой, обработка не считается; из покоя — 40 отсчётов и вход за 5 мс.
// BYPASS — MIX 0 (за 20 мс в сухой, задержка та же). Расчёт — Double, как JS.

// Горячий путь shape (4 отсчёта на входной): те же формулы, что tableF, anti и shapeY, — функциями файла с
// @_transparent (в отладочной сборке встраивается только он; S14b).

/// F(|u|) по таблице (кубический Эрмит); за 12: tanh — линейно, EDGE — с поправкой a − 1/(12a³).
@_transparent private func satTableF(_ F: UnsafeMutablePointer<Double>, _ D: UnsafeMutablePointer<Double>, _ fmax: Double,
                                     _ edge: Bool, _ u: Double) -> Double {
    let a: Double = u < 0 ? -u : u
    if a >= 12 {
        let tail: Double = edge ? (1.0 / 1728 - 1 / (a * a * a)) / 12 : 0
        return fmax + (a - 12) - tail
    }
    let x: Double = a * 32
    let i = Int(x)
    let tt: Double = x - Double(i), t2: Double = tt * tt, t3: Double = t2 * tt
    let h: Double = 0.03125
    return (2 * t3 - 3 * t2 + 1) * F[i] + (t3 - 2 * t2 + tt) * h * D[i] + (-2 * t3 + 3 * t2) * F[i + 1]
        + (t3 - t2) * h * D[i + 1]
}

/// Антипроизводная type 0–2 (F, D, fmax — таблица кривой: tanh у 0 и 1, EDGE у 2).
@_transparent private func satAnti(_ type: Int, _ u: Double, _ F: UnsafeMutablePointer<Double>,
                                   _ D: UnsafeMutablePointer<Double>, _ fmax: Double, _ lcB: Double, _ tb: Double,
                                   _ td: Double) -> Double {
    if type == 0 { return satTableF(F, D, fmax, false, u) }
    if type == 1 { return (satTableF(F, D, fmax, false, u + 0.35) - lcB - u * tb) / td }
    return satTableF(F, D, fmax, true, u)
}

/// Кривая type 0–2.
@_transparent private func satShapeY(_ type: Int, _ u: Double, _ tb: Double, _ td: Double) -> Double {
    if type == 0 { return tanh(u) }
    if type == 1 { return (tanh(u + 0.35) - tb) / td }
    return u / sqrt(sqrt(1 + u * u * u * u))
}

/// Свёртка n отводов: acc + Σ k[j]·x[−j] (x — последний отсчёт окна). По 4 отвода со сдвигом указателей: в отладочной
/// сборке счётчик и индексы цикла дороже самих умножений (S14b); порядок сложения тот же.
@_transparent private func satDot(_ acc: Double, _ k: UnsafePointer<Double>, _ x: UnsafePointer<Double>, _ n: Int) -> Double {
    var s: Double = acc
    var kp: UnsafePointer<Double> = k
    var xp: UnsafePointer<Double> = x
    var j: Int = n
    while j >= 4 {
        s += kp[0] * xp[0]
        s += kp[1] * xp[-1]
        s += kp[2] * xp[-2]
        s += kp[3] * xp[-3]
        kp += 4
        xp -= 4
        j -= 4
    }
    while j > 0 {
        s += kp[0] * xp[0]
        kp += 1
        xp -= 1
        j -= 1
    }
    return s
}

/// Симметричная свёртка: acc + Σ k[j]·(a[−j] + b[j]).
@_transparent private func satDotSym(_ acc: Double, _ k: UnsafePointer<Double>, _ a: UnsafePointer<Double>,
                                       _ b: UnsafePointer<Double>, _ n: Int) -> Double {
    var s: Double = acc
    var kp: UnsafePointer<Double> = k
    var ap: UnsafePointer<Double> = a
    var bp: UnsafePointer<Double> = b
    var j: Int = n
    while j >= 4 {
        s += kp[0] * (ap[0] + bp[0])
        s += kp[1] * (ap[-1] + bp[1])
        s += kp[2] * (ap[-2] + bp[2])
        s += kp[3] * (ap[-3] + bp[3])
        kp += 4
        ap -= 4
        bp += 4
        j -= 4
    }
    while j > 0 {
        s += kp[0] * (ap[0] + bp[0])
        kp += 1
        ap -= 1
        bp += 1
        j -= 1
    }
    return s
}

public final class MasterSaturator {
    static let fadeInDb: Double = 1
    static let toneHz: Double = 1000
    static let toneQ: Double = 0.5
    static let toneMaxDb: Double = 6
    static let dcHz: Double = 5
    static let smoothMs: Double = 20
    static let typeFadeMs: Double = 20
    static let tiny: Double = 1e-25
    static let adaaEps: Double = 1e-6
    static let warmSamples = 40
    static let warmRampMs: Double = 5
    static let focusOff: Double = 20
    /// Задержка цепи (сухая ветка), исходных отсчётов: (64 + 0,5 + 3,5 + 64) / 4.
    static let dryDelay = 33
    static let corrLen = 8
    // Раскладка состояния канала (Double): история 66, u 4, y 4, коррекция 16, децимация 258, prevF 3, сухая 33,
    // НЧ FOCUS 33, затем prevU, dcX, dcY, low shelf [2], high shelf [2], lp.
    static let oHist = 0, oU = 66, oY = 70, oCorr = 74, oOs = 90, oPrevF = 348, oDry = 351, oLpD = 384
    static let oPrevU = 417, oDcX = 418, oDcY = 419, oLo = 420, oHi = 422, oLp = 424
    static let chSize = 425
    // Целые состояния канала: hpos, cpos, opos, dpos.
    static let iSize = 4

    let sr: Double
    let t: MasterTables
    let st: UnsafeMutablePointer<Double>
    let ist: UnsafeMutablePointer<Int>
    let cLo = UnsafeMutablePointer<Double>.allocate(capacity: 5)
    let cHi = UnsafeMutablePointer<Double>.allocate(capacity: 5)
    let kSmooth: Double
    let kBlock: Double
    let fadeStep: Double
    let splitStep: Double
    let rampStep: Double
    let kDc: Double
    var driveDb: Double = 0
    var mix: Double = 1
    var toneDb: Double = 0
    var focus: Double = 20
    var split: Double = 0
    var kLp: Double = 0
    var cur = 0
    var prev = 0
    var fade: Double = 1
    var idle = true
    var warmN = 0
    var ramp: Double = 1

    public init(sampleRate: Double, tables: MasterTables = .shared) {
        sr = sampleRate
        t = tables
        kSmooth = exp(-1 / ((MasterSaturator.smoothMs / 1000) * sampleRate))
        kBlock = pow(kSmooth, 128)
        fadeStep = 1 / ((MasterSaturator.typeFadeMs / 1000) * sampleRate)
        splitStep = 1 / ((MasterSaturator.smoothMs / 1000) * sampleRate)
        rampStep = 1 / ((MasterSaturator.warmRampMs / 1000) * sampleRate)
        kDc = exp((-2 * Double.pi * MasterSaturator.dcHz) / sampleRate)
        st = UnsafeMutablePointer<Double>.allocate(capacity: 2 * MasterSaturator.chSize)
        st.initialize(repeating: 0, count: 2 * MasterSaturator.chSize)
        ist = UnsafeMutablePointer<Int>.allocate(capacity: 2 * MasterSaturator.iSize)
        ist.initialize(repeating: 0, count: 2 * MasterSaturator.iSize)
        MasterSaturator.shelf(cLo, 0, sampleRate, high: false)
        MasterSaturator.shelf(cHi, 0, sampleRate, high: true)
    }

    deinit {
        st.deallocate()
        ist.deallocate()
        cLo.deallocate()
        cHi.deallocate()
    }

    /// RBJ shelf → [b0, b1, b2, a1, a2]: high — high shelf, иначе low shelf; усиление gDb на 1 кГц (Q 0,5).
    static func shelf(_ o: UnsafeMutablePointer<Double>, _ gDb: Double, _ sr: Double, high: Bool) {
        let A: Double = pow(10, gDb / 40)
        let w: Double = (2 * Double.pi * toneHz) / sr
        let cw: Double = cos(w)
        let al: Double = sin(w) / (2 * toneQ)
        let sa: Double = 2 * sqrt(A) * al
        let s: Double = high ? 1 : -1
        let a0: Double = A + 1 - s * (A - 1) * cw + sa
        o[0] = (A * (A + 1 + s * (A - 1) * cw + sa)) / a0
        o[1] = (-2 * s * A * (A - 1 + s * (A + 1) * cw)) / a0
        o[2] = (A * (A + 1 + s * (A - 1) * cw - sa)) / a0
        o[3] = (2 * s * (A - 1 - s * (A + 1) * cw)) / a0
        o[4] = (A + 1 - s * (A - 1) * cw - sa) / a0
    }

    /// F(|u|) по таблице (кубический Эрмит); за 12: tanh — линейно, EDGE — с поправкой a − 1/(12a³).
    @inline(__always)
    func tableF(_ F: UnsafeMutablePointer<Double>, _ D: UnsafeMutablePointer<Double>, _ fmax: Double, _ edge: Bool,
                _ u: Double) -> Double {
        let a: Double = u < 0 ? -u : u
        if a >= 12 {
            let tail: Double = edge ? (1.0 / 1728 - 1 / (a * a * a)) / 12 : 0
            return fmax + (a - 12) - tail
        }
        let x: Double = a * 32
        let i = Int(x)
        let tt: Double = x - Double(i), t2: Double = tt * tt, t3: Double = t2 * tt
        let h: Double = 0.03125
        return (2 * t3 - 3 * t2 + 1) * F[i] + (t3 - 2 * t2 + tt) * h * D[i] + (-2 * t3 + 3 * t2) * F[i + 1]
            + (t3 - t2) * h * D[i + 1]
    }

    @inline(__always)
    func anti(_ type: Int, _ u: Double) -> Double {
        let d = t.d
        switch type {
        case 0: return tableF(d.tanhF, d.tanhD, d.tanhMax, false, u)
        case 1: return (tableF(d.tanhF, d.tanhD, d.tanhMax, false, u + 0.35) - d.lcB - u * d.tb) / d.td
        default: return tableF(t.edgeF, t.edgeD, t.edgeMax, true, u)
        }
    }

    @inline(__always)
    func shapeY(_ type: Int, _ u: Double) -> Double {
        switch type {
        case 0: return tanh(u)
        case 1: return (tanh(u + 0.35) - t.d.tb) / t.d.td
        default: return u / sqrt(sqrt(1 + u * u * u * u))
        }
    }

    /// Нелинейность type по 4 отсчётам u с антипроизводной: y[p] (+)= k · (F(u) − F(u0)) / (u − u0).
    func shape(_ c: UnsafeMutablePointer<Double>, _ type: Int, _ k: Double, add: Bool) {
        let u = c + MasterSaturator.oU, y = c + MasterSaturator.oY
        var u0: Double = c[MasterSaturator.oPrevU]
        var F0: Double = c[MasterSaturator.oPrevF + type]
        // Таблица кривой и константы — один раз на 4 отсчёта.
        let d: DriveTables = t.d
        let edge: Bool = type >= 2
        let tF: UnsafeMutablePointer<Double> = edge ? t.edgeF : d.tanhF
        let tD: UnsafeMutablePointer<Double> = edge ? t.edgeD : d.tanhD
        let tMax: Double = edge ? t.edgeMax : d.tanhMax
        let lcB: Double = d.lcB, tb: Double = d.tb, td: Double = d.td
        let eps: Double = MasterSaturator.adaaEps
        var p = 0
        while p < 4 {
            let v: Double = u[p]
            let F: Double = satAnti(type, v, tF, tD, tMax, lcB, tb, td)
            let du: Double = v - u0
            let near: Bool = du < eps && du > -eps
            let r: Double = near ? satShapeY(type, 0.5 * (v + u0), tb, td) : (F - F0) / du
            y[p] = add ? y[p] + k * r : k * r
            u0 = v
            F0 = F
            p += 1
        }
        c[MasterSaturator.oPrevF + type] = F0
    }

    /// Отсчёт (уже · g) → 4 отсчёта нелинейности (смесь кривых a — старая, b — новая) → децимация.
    func wet(_ c: UnsafeMutablePointer<Double>, _ ic: UnsafeMutablePointer<Int>, _ x: Double, _ ta: Int, _ tb: Int,
             _ wa: Double, _ wb: Double, _ ca: Double, _ cb: Double) -> Double {
        let d = t.d
        let pl = DriveTables.phaseLen
        let hist = c + MasterSaturator.oHist
        let hp = ic[0]
        hist[hp] = x
        hist[hp + pl] = x
        ic[0] = hp + 1 == pl ? 0 : hp + 1
        let base = hp + pl
        let u = c + MasterSaturator.oU
        u[0] = d.ph0Gain * hist[base - DriveTables.ph0Delay]
        let phases = d.phases
        var p = 1
        while p < 4 {
            let f = phases + p * pl
            let s: Double = satDot(0, f, hist + base, pl)
            u[p] = s
            p += 1
        }
        if wa > 0 {
            shape(c, ta, wa / ca, add: false)
            shape(c, tb, wb / cb, add: true)
        } else {
            shape(c, tb, 1 / cb, add: false)
        }
        c[MasterSaturator.oPrevU] = u[3]
        let y = c + MasterSaturator.oY
        let cbuf = c + MasterSaturator.oCorr, os = c + MasterSaturator.oOs
        let cl = MasterSaturator.corrLen, fl = DriveTables.firLen
        let k0: Double = -1.0 / 128, k1: Double = 9.0 / 128, k2: Double = -37.0 / 128, k3: Double = 93.0 / 128
        // Позиции колец — в локальных переменных (Swift 6.0.3 на Linux с -O падал на ic[1] в цикле).
        var cp: Int = ic[1]
        var op: Int = ic[2]
        p = 0
        while p < 4 {
            cbuf[cp] = y[p]
            cbuf[cp + cl] = y[p]
            let e = cp + cl
            cp = cp + 1 == cl ? 0 : cp + 1
            let yc: Double = k0 * (cbuf[e] + cbuf[e - 7]) + k1 * (cbuf[e - 1] + cbuf[e - 6])
                + k2 * (cbuf[e - 2] + cbuf[e - 5]) + k3 * (cbuf[e - 3] + cbuf[e - 4])
            os[op] = yc
            os[op + fl] = yc
            op = op + 1 == fl ? 0 : op + 1
            p += 1
        }
        ic[1] = cp
        ic[2] = op
        let ob = op + fl - 1
        let dc = DriveTables.decC
        var out: Double = d.decMid * os[ob - dc]
        let lst = ob - (fl - 1)
        let dh = d.decHalf
        out = satDotSym(out, dh, os + ob, os + lst, dc)
        return out + MasterSaturator.tiny
    }

    /// Блок n отсчётов (вход и выход могут совпадать). drive 0…24 dB, type 0–2, tone −100…100, mix 0…100 (BYPASS — 0),
    /// focus 20…2000 Гц (20 — OFF).
    public func process(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>, outL: UnsafeMutablePointer<Float>,
                        outR: UnsafeMutablePointer<Float>, frames n: Int, drive dIn: Double, type tIn: Double,
                        tone toIn: Double, mix mIn: Double, focus fIn: Double) {
        let sr: Double = self.sr
        let ks: Double = kSmooth
        let driveT: Double = Swift.max(0, Swift.min(MasterTables.maxDriveDb, dIn))
        let mixT: Double = Swift.max(0, Swift.min(1, mIn / 100))
        let type = Int(Swift.max(0, Swift.min(2, (tIn + 0.5).rounded(.down))))
        if type != cur {
            // Смена TYPE: кроссфейд 20 мс; новая кривая начинает антипроизводную с текущего отсчёта.
            prev = fade >= 0.5 ? cur : prev
            cur = type
            fade = 0
            for k in 0..<2 {
                let c = st + k * MasterSaturator.chSize
                c[MasterSaturator.oPrevF + type] = anti(type, c[MasterSaturator.oPrevU])
            }
        }
        // TONE: наклон сглаживается по блокам, коэффициенты shelf — на блок.
        let toneT: Double = (Swift.max(-100, Swift.min(100, toIn)) / 100) * MasterSaturator.toneMaxDb
        if toneDb != toneT {
            toneDb = abs(toneT - toneDb) < 1e-4 ? toneT : toneT + (toneDb - toneT) * kBlock
            MasterSaturator.shelf(cLo, -toneDb, sr, high: false)
            MasterSaturator.shelf(cHi, toneDb, sr, high: true)
        }
        // FOCUS: частота — по логарифму по блокам; коэффициент ФНЧ — линейно внутри блока.
        let fT: Double = Swift.max(MasterSaturator.focusOff, Swift.min(2000, fIn))
        let splitT: Double = fT > MasterSaturator.focusOff + 1e-3 ? 1 : 0
        if splitT > 0 { focus = exp(log(fT) + (log(focus) - log(fT)) * kBlock) }
        if abs(focus - fT) < 1e-3 { focus = fT }
        let kLp0: Double = kLp
        kLp = 1 - exp((-2 * Double.pi * focus) / sr)
        let kLpStep: Double = (kLp - kLp0) / Double(n)
        let D = MasterSaturator.dryDelay
        if (driveT == 0 && driveDb < 1e-4) || (mixT == 0 && mix < 1e-5) {
            processIdle(inL, inR, outL, outR, n, driveT, mixT, splitT, kLp0, kLpStep)
            return
        }
        if idle {
            // Из покоя: буферы обработки заполняются заново, обработанная ветка входит после них плавно.
            idle = false
            for k in 0..<2 {
                let c = st + k * MasterSaturator.chSize
                (c + MasterSaturator.oCorr).update(repeating: 0, count: 2 * MasterSaturator.corrLen + 2 * DriveTables.firLen)
                (c + MasterSaturator.oPrevF).update(repeating: 0, count: 3)
                c[MasterSaturator.oPrevU] = 0
                c[MasterSaturator.oDcX] = 0
                c[MasterSaturator.oDcY] = 0
            }
            warmN = MasterSaturator.warmSamples
            ramp = 0
        }
        let comp = t.comp
        let cn = MasterTables.compN + 2
        let kDc: Double = self.kDc, tiny: Double = MasterSaturator.tiny
        let cLo = self.cLo, cHi = self.cHi
        // Состояние — в локальных на блок (в отладочной сборке каждое обращение к свойству — проверка доступа; S14b).
        var dBv: Double = driveDb, mixv: Double = mix, spl: Double = split, fd: Double = fade
        var warm: Int = warmN, rmp: Double = ramp
        let sStep: Double = splitStep, fStep: Double = fadeStep, rStep: Double = rampStep
        let ta = prev, tb = cur
        // Усиление, мягкий вход и компенсация — пересчёт только при изменении DRIVE (exp и таблица на каждом отсчёте
        // при устоявшейся ручке давали те же значения).
        var lastDb: Double = -1, g: Double = 1, tt: Double = 0, ca: Double = 1, cb: Double = 1
        var i = 0
        while i < n {
            dBv = driveT + (dBv - driveT) * ks
            mixv = mixT + (mixv - mixT) * ks
            if spl < splitT { spl = Swift.min(splitT, spl + sStep) } else if spl > splitT {
                spl = Swift.max(splitT, spl - sStep)
            }
            if fd < 1 { fd = Swift.min(1, fd + fStep) }
            let dB: Double = dBv
            if dB != lastDb {
                lastDb = dB
                g = exp(dB * 0.11512925464970229)
                tt = Swift.min(1, dB / MasterSaturator.fadeInDb)
                // dB ≥ 0: пол — через Int.
                let ci: Double = dB / MasterTables.compStepDb
                let i0 = Int(ci)
                let fr: Double = ci - Double(i0)
                ca = comp[ta * cn + i0] + (comp[ta * cn + i0 + 1] - comp[ta * cn + i0]) * fr
                cb = comp[tb * cn + i0] + (comp[tb * cn + i0 + 1] - comp[tb * cn + i0]) * fr
            }
            if warm > 0 { warm -= 1 } else if rmp < 1 { rmp = Swift.min(1, rmp + rStep) }
            let w: Double = mixv * tt * tt * (3 - 2 * tt) * rmp
            let wb: Double = fd
            let wa: Double = ta == tb ? 0 : 1 - wb
            // Фильтр DC — на доле TUBE.
            let tube: Double = (tb == 1 ? wb : 0) + (ta == 1 ? wa : 0)
            let sp: Double = spl
            let kl: Double = kLp0 + kLpStep * Double(i + 1)
            var k = 0
            while k < 2 {
                let c = st + k * MasterSaturator.chSize
                let ic = ist + k * MasterSaturator.iSize
                let x = Double(k == 0 ? inL[i] : inR[i])
                let dp = ic[3]
                let dry: Double = c[MasterSaturator.oDry + dp]
                c[MasterSaturator.oDry + dp] = x
                // FOCUS: в задержку — уже взвешенная НЧ (сумма с ветвью x − sp·LP точно равна x).
                c[MasterSaturator.oLp] += kl * (x - c[MasterSaturator.oLp])
                let lpOut: Double = c[MasterSaturator.oLpD + dp]
                let lpS: Double = sp * c[MasterSaturator.oLp]
                c[MasterSaturator.oLpD + dp] = lpS
                ic[3] = dp + 1 == D ? 0 : dp + 1
                var y: Double = wet(c, ic, (x - lpS) * g, ta, tb, wa, wb, ca, cb)
                let hpY: Double = kDc * (c[MasterSaturator.oDcY] + y - c[MasterSaturator.oDcX]) + tiny
                c[MasterSaturator.oDcX] = y
                c[MasterSaturator.oDcY] = hpY
                y += tube * (hpY - y)
                // TONE: low shelf, затем high shelf (TDF-II).
                let lo = c + MasterSaturator.oLo, hi = c + MasterSaturator.oHi
                let y1: Double = cLo[0] * y + lo[0]
                lo[0] = cLo[1] * y - cLo[3] * y1 + lo[1]
                lo[1] = cLo[2] * y - cLo[4] * y1
                let y2: Double = cHi[0] * y1 + hi[0]
                hi[0] = cHi[1] * y1 - cHi[3] * y2 + hi[1]
                hi[1] = cHi[2] * y1 - cHi[4] * y2
                let yo: Double = dry + w * (y2 + lpOut - dry)
                if k == 0 { outL[i] = Float(yo) } else { outR[i] = Float(yo) }
                k += 1
            }
            i += 1
        }
        driveDb = dBv
        mix = mixv
        split = spl
        fade = fd
        warmN = warm
        ramp = rmp
    }

    /// Покой (DRIVE 0 или MIX 0): выход — сухой с задержкой; история оверсэмплера и НЧ FOCUS идут дальше.
    func processIdle(_ inL: UnsafePointer<Float>, _ inR: UnsafePointer<Float>, _ outL: UnsafeMutablePointer<Float>,
                     _ outR: UnsafeMutablePointer<Float>, _ n: Int, _ driveT: Double, _ mixT: Double, _ splitT: Double,
                     _ kLp0: Double, _ kLpStep: Double) {
        split = splitT
        driveDb = driveT
        mix = mixT
        fade = 1
        idle = true
        let g: Double = exp(driveT * 0.11512925464970229)
        let D = MasterSaturator.dryDelay, pl = DriveTables.phaseLen
        let sp: Double = split
        for k in 0..<2 {
            let c = st + k * MasterSaturator.chSize
            let ic = ist + k * MasterSaturator.iSize
            let src = k == 0 ? inL : inR
            let o = k == 0 ? outL : outR
            var i = 0
            while i < n {
                let x = Double(src[i])
                let hp = ic[0]
                c[MasterSaturator.oHist + hp] = x * g
                c[MasterSaturator.oHist + hp + pl] = x * g
                ic[0] = hp + 1 == pl ? 0 : hp + 1
                let dp = ic[3]
                o[i] = Float(c[MasterSaturator.oDry + dp])
                c[MasterSaturator.oDry + dp] = x
                c[MasterSaturator.oLp] += (kLp0 + kLpStep * Double(i + 1)) * (x - c[MasterSaturator.oLp])
                c[MasterSaturator.oLpD + dp] = sp * c[MasterSaturator.oLp]
                ic[3] = dp + 1 == D ? 0 : dp + 1
                i += 1
            }
        }
    }
}
