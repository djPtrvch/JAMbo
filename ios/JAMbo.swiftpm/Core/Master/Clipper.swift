import Foundation

// Клиппер мастера — перенос public/clipper-worklet.js (решение пользователя S5a: без MIX, UNITY, AUDIT и снимков WAVE —
// MIX 100 %, как по умолчанию в вебе, звук тот же). Стерео, каналы независимо.
// Вход · DRIVE → кроссовер LR4 на BASS (0 — OFF, без деления; переход за 20 мс) → ВЧ: 4× оверсэмплинг (oversampler.js)
// → мягкое колено (SOFTNESS) по CEILING с антипроизводной и коррекцией [−1/8, 5/4, −1/8] → децимация;
// НЧ — без обработки, с задержкой 32 → сумма. BYPASS — кроссфейд 10 мс с входом той же задержки.
// Индикация (S5c): за кадр 256 отсчётов — пик после DRIVE, срез (dB, окна 10 мс), пик выхода.

public final class MasterClipper {
    static let smoothMs: Double = 20
    static let bypassMs: Double = 10
    static let grWindowMs: Double = 10
    static let meterFrames = 256
    static let tiny: Double = 1e-25
    /// Задержка НЧ и сухой ветки: round((64 + 1 + 0,5 + 64) / 4); кольцо — на 1 больше.
    static let lfDelay = 32
    static let ring = 33
    // Раскладка состояния канала (Double): ФНЧ [2][2], ФВЧ [2][2], история 66, децимация 258, задержки НЧ, сухая,
    // ВЧ без среза (по 33), затем prevU, prevF, c0, c1.
    static let oLp = 0, oHp = 4, oHist = 8, oOs = 74, oLf = 332, oDry = 365, oHf = 398
    static let oPrevU = 431, oPrevF = 432, oC0 = 433, oC1 = 434
    static let chSize = 435
    // Целые состояния канала: hpos, opos, dpos.
    static let iSize = 3

    let sr: Double
    let d: DriveTables
    let st: UnsafeMutablePointer<Double>
    let ist: UnsafeMutablePointer<Int>
    /// Коэффициенты кроссовера: прошлого блока, этого блока и текущие (интерполяция внутри блока) — LP и HP по 5.
    let cf: UnsafeMutablePointer<Double>
    let kSmooth: Double
    let kBlock: Double
    let wetStep: Double
    let splitStep: Double
    let grWin: Int
    var driveLin: Double = 1
    var ceil: Double = 0.8912509381337456
    var knee: Double = 0.82
    var freq: Double = 100
    var split: Double = 1
    var wet: Double = 1
    var engaged = false
    var grN = 0
    var winIn: Double = 0
    var winOut: Double = 0
    var lastGr: Double = 0
    var frameGrAcc: Double = -1
    var meterN = 0
    var mIn: Double = 0, mOut: Double = 0
    public private(set) var frameIn: Double = 0
    public private(set) var frameGr: Double = 0
    public private(set) var frameOut: Double = 0
    public private(set) var frames = 0

    public init(sampleRate: Double, tables: DriveTables = .shared) {
        sr = sampleRate
        d = tables
        kSmooth = exp(-1 / ((MasterClipper.smoothMs / 1000) * sampleRate))
        kBlock = pow(kSmooth, 128)
        wetStep = 1 / ((MasterClipper.bypassMs / 1000) * sampleRate)
        splitStep = 1 / ((MasterClipper.smoothMs / 1000) * sampleRate)
        grWin = Int((MasterClipper.grWindowMs / 1000) * sampleRate + 0.5)
        knee = 1 - 0.6 * 0.3
        ceil = pow(10, -1.0 / 20)
        st = UnsafeMutablePointer<Double>.allocate(capacity: 2 * MasterClipper.chSize)
        st.initialize(repeating: 0, count: 2 * MasterClipper.chSize)
        ist = UnsafeMutablePointer<Int>.allocate(capacity: 2 * MasterClipper.iSize)
        ist.initialize(repeating: 0, count: 2 * MasterClipper.iSize)
        cf = UnsafeMutablePointer<Double>.allocate(capacity: 30)
        cf.initialize(repeating: 0, count: 30)
        MasterClipper.butter(cf, 100, sampleRate, high: false)
        MasterClipper.butter(cf + 5, 100, sampleRate, high: true)
    }

    deinit {
        st.deallocate()
        ist.deallocate()
        cf.deallocate()
    }

    /// Биквад Баттерворта (Q = 1/√2) → [b0, b1, b2, a1, a2]: ФНЧ или ФВЧ на частоте f.
    static func butter(_ o: UnsafeMutablePointer<Double>, _ f: Double, _ sr: Double, high: Bool) {
        let w: Double = (2 * Double.pi * f) / sr
        let cw: Double = cos(w)
        let al: Double = sin(w) * 0.7071067811865476
        let a0: Double = 1 + al
        let b0: Double = (high ? (1 + cw) / 2 : (1 - cw) / 2) / a0
        o[0] = b0
        o[1] = (high ? -(1 + cw) : 1 - cw) / a0
        o[2] = b0
        o[3] = (-2 * cw) / a0
        o[4] = (1 - al) / a0
    }

    @inline(__always)
    func shape(_ u: Double, _ k: Double) -> Double {
        let a: Double = abs(u)
        if a <= k { return u }
        let s: Double = 1 - k
        let y: Double = s > 1e-9 ? k + s * tanh((a - k) / s) : 1
        return u < 0 ? -y : y
    }

    @inline(__always)
    func antideriv(_ u: Double, _ k: Double) -> Double {
        let a: Double = abs(u)
        if a <= k { return 0.5 * u * u }
        let s: Double = 1 - k
        let base: Double = 0.5 * k * k + k * (a - k)
        if s <= 1e-9 { return base + (a - k) * (1 - k) }
        let x: Double = (a - k) / s
        // ln cosh: при x > 9 поправка меньше 1e-8.
        let lc: Double = x > 9 ? x - 0.6931471805599453 : x + log1p(exp(-2 * x)) - 0.6931471805599453
        return base + s * s * lc
    }

    /// Отсчёт ВЧ-полосы → 4 отсчёта нелинейности → децимация.
    func hf(_ c: UnsafeMutablePointer<Double>, _ ic: UnsafeMutablePointer<Int>, _ x: Double, _ ceil: Double,
            _ k: Double) -> Double {
        let pl = DriveTables.phaseLen, fl = DriveTables.firLen
        let hist = c + MasterClipper.oHist
        let hp = ic[0]
        hist[hp] = x
        hist[hp + pl] = x
        ic[0] = hp + 1 == pl ? 0 : hp + 1
        let base = hp + pl
        let inv: Double = 1 / ceil
        let os = c + MasterClipper.oOs
        let phases = d.phases
        var p = 0
        while p < 4 {
            var s: Double = 0
            if p == 0 {
                s = d.ph0Gain * hist[base - DriveTables.ph0Delay]
            } else {
                let f = phases + p * pl
                var j = 0
                while j < pl {
                    s += f[j] * hist[base - j]
                    j += 1
                }
            }
            // Антипроизводная первого порядка; ниже колена — среднее двух отсчётов.
            let u: Double = s * inv
            let u0: Double = c[MasterClipper.oPrevU]
            var y: Double
            if abs(u) <= k && abs(u0) <= k {
                y = 0.5 * (u + u0)
                c[MasterClipper.oPrevF] = 0.5 * u * u
            } else {
                engaged = true
                let F: Double = antideriv(u, k)
                let du: Double = u - u0
                y = abs(du) > 1e-6 ? (F - c[MasterClipper.oPrevF]) / du : shape(0.5 * (u + u0), k)
                c[MasterClipper.oPrevF] = F
            }
            c[MasterClipper.oPrevU] = u
            let yc: Double = 1.25 * c[MasterClipper.oC0] - 0.125 * (y + c[MasterClipper.oC1])
            c[MasterClipper.oC1] = c[MasterClipper.oC0]
            c[MasterClipper.oC0] = y
            let op = ic[1]
            os[op] = yc * ceil
            os[op + fl] = yc * ceil
            ic[1] = op + 1 == fl ? 0 : op + 1
            p += 1
        }
        let ob = ic[1] + fl - 1
        let dc = DriveTables.decC
        var out: Double = d.decMid * os[ob - dc]
        let lst = ob - (fl - 1)
        let dh = d.decHalf
        var j = 0
        while j < dc {
            out += dh[j] * (os[ob - j] + os[lst + j])
            j += 1
        }
        return out + MasterClipper.tiny
    }

    @inline(__always)
    func biquad(_ s: UnsafeMutablePointer<Double>, _ c: UnsafeMutablePointer<Double>, _ x: Double) -> Double {
        let y: Double = c[0] * x + s[0]
        s[0] = c[1] * x - c[3] * y + s[1]
        s[1] = c[2] * x - c[4] * y
        return y
    }

    /// Статическая кривая (окно клиппера, TRANSFER; clipCurve веба): выход в dB при уровне источника x dB (до INPUT),
    /// по формуле клиппера — u = x·INPUT/CEILING, колено k = 1 − 0,6·SOFTNESS, выше колена tanh.
    public static func staticOut(_ x: Double, input: Double, ceiling: Double, softness: Double) -> Double {
        let k: Double = 1 - 0.6 * (softness / 100)
        let u: Double = pow(10, (x + input - ceiling) / 20)
        var y: Double = u
        if u > k {
            let s: Double = 1 - k
            y = s > 1e-9 ? k + s * tanh((u - k) / s) : 1
        }
        return ceiling + 20 * log10(y)
    }

    /// Блок n отсчётов (вход и выход могут совпадать). drive 0…12 dB, ceiling −12…0 dB, softness 0…100 %,
    /// bass 20…300 Гц (0 — OFF).
    public func process(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>, outL: UnsafeMutablePointer<Float>,
                        outR: UnsafeMutablePointer<Float>, frames n: Int, drive: Double, ceiling: Double,
                        softness: Double, bass: Double, bypass: Bool) {
        let ks: Double = kSmooth
        let driveT: Double = pow(10, drive / 20)
        let ceilT: Double = pow(10, ceiling / 20)
        let kneeT: Double = 1 - 0.6 * (softness / 100)
        let wetT: Double = bypass ? 0 : 1
        let splitT: Double = bass > 0 ? 1 : 0
        // Частота кроссовера — по блокам; коэффициенты линейно внутри блока.
        let fT: Double = bass > 0 ? bass : freq
        let f1: Double = fT + (freq - fT) * kBlock
        let lp0 = cf, hp0 = cf + 5, lp1 = cf + 10, hp1 = cf + 15, lpc = cf + 20, hpc = cf + 25
        MasterClipper.butter(lp1, f1, sr, high: false)
        MasterClipper.butter(hp1, f1, sr, high: true)
        freq = f1
        let moving: Bool = abs(f1 - fT) > 0.01 || lp0[0] != lp1[0]
        if !moving {
            lpc.update(from: lp1, count: 5)
            hpc.update(from: hp1, count: 5)
        }
        let R = MasterClipper.ring
        var i = 0
        while i < n {
            if moving {
                let a: Double = Double(i + 1) / Double(n)
                var q = 0
                while q < 5 {
                    lpc[q] = lp0[q] + (lp1[q] - lp0[q]) * a
                    hpc[q] = hp0[q] + (hp1[q] - hp0[q]) * a
                    q += 1
                }
            }
            driveLin = driveT + (driveLin - driveT) * ks
            ceil = ceilT + (ceil - ceilT) * ks
            knee = kneeT + (knee - kneeT) * ks
            if wet < wetT { wet = Swift.min(wetT, wet + wetStep) } else if wet > wetT { wet = Swift.max(wetT, wet - wetStep) }
            if split < splitT { split = Swift.min(splitT, split + splitStep) } else if split > splitT {
                split = Swift.max(splitT, split - splitStep)
            }
            var inPk: Double = 0, dryPk: Double = 0, outPk: Double = 0
            var k = 0
            while k < 2 {
                let c = st + k * MasterClipper.chSize
                let ic = ist + k * MasterClipper.iSize
                let raw = Double(k == 0 ? inL[i] : inR[i])
                let x: Double = raw * driveLin
                if abs(x) > inPk { inPk = abs(x) }
                // Кроссовер LR4 (OFF — всё в ВЧ, с плавным переходом).
                let lo: Double = biquad(c + MasterClipper.oLp + 2, lpc, biquad(c + MasterClipper.oLp, lpc, x))
                let hi: Double = biquad(c + MasterClipper.oHp + 2, hpc, biquad(c + MasterClipper.oHp, hpc, x))
                let sp: Double = split
                let hfIn: Double = sp * hi + (1 - sp) * x
                let lfIn: Double = sp * lo
                let yh: Double = hf(c, ic, hfIn, ceil, knee)
                // НЧ и сухой сигнал — с той же задержкой.
                let dp = ic[2]
                let r = dp + 1 == R ? 0 : dp + 1
                let lfOut: Double = c[MasterClipper.oLf + r]
                let dryOut: Double = c[MasterClipper.oDry + r]
                let lin: Double = lfOut + c[MasterClipper.oHf + r]
                c[MasterClipper.oLf + dp] = lfIn
                c[MasterClipper.oDry + dp] = raw
                c[MasterClipper.oHf + dp] = hfIn
                ic[2] = r
                let w: Double = lfOut + yh
                // В bypass клиппер отключён целиком (и DRIVE): сухой — исходный сигнал с той же задержкой.
                let y: Double = wet * w + (1 - wet) * dryOut
                if k == 0 { outL[i] = Float(y) } else { outR[i] = Float(y) }
                if abs(lin) > dryPk { dryPk = abs(lin) }
                if abs(w) > outPk { outPk = abs(w) }
                if abs(y) > mOut { mOut = abs(y) }
                k += 1
            }
            if inPk > mIn { mIn = inPk }
            // Срез пика: наибольший пик выхода к наибольшему пику того же сигнала без среза за 10 мс.
            if dryPk > winIn { winIn = dryPk }
            if outPk > winOut { winOut = outPk }
            grN += 1
            if grN >= grWin { closeWindow() }
            i += 1
        }
        lp0.update(from: lp1, count: 5)
        hp0.update(from: hp1, count: 5)
        meterN += n
        if meterN >= MasterClipper.meterFrames {
            // GR кадра — наибольшее из окон, закончившихся в кадре; если ни одно не закончилось — последнее.
            frameIn = mIn
            frameGr = frameGrAcc >= 0 ? frameGrAcc : lastGr
            frameOut = mOut
            frames += 1
            meterN = 0
            mIn = 0
            mOut = 0
            frameGrAcc = -1
        }
    }

    func closeWindow() {
        var gr: Double = 0
        if winIn > 1e-6 && wet > 0.5 { gr = Swift.max(0, -20 * log10(Swift.max(winOut, 1e-9) / winIn)) }
        // Без срабатывания нелинейности или меньше 0,1 dB — погрешность фильтров оверсэмплинга, не срез.
        if gr < 0.1 || !engaged { gr = 0 }
        engaged = false
        lastGr = gr
        frameGrAcc = Swift.max(frameGrAcc, gr)
        grN = 0
        winIn = 0
        winOut = 0
    }
}
