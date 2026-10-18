import Foundation

// Детекторы динамических полос EQ (S7b) — как в EqChain веба: источник → фильтр детектора (BiquadFilterNode: у bell —
// полосовой на частоте и Q полосы, у low shelf — ФНЧ, у high shelf — ФВЧ, Q 0,7071 в dB) → eqdyn-worklet.js: пик
// (STEREO — max |L|, |R|; MID — |L+R|/2; SIDE — |L−R|/2) с атакой 5 мс и спадом 100 мс, сдвиг усиления
// RANGE · min(1, (уровень − THRESHOLD) / 12 dB), ниже порога — 0; сдвиг на каждый отсчёт прибавляется к усилению
// полосы. Фильтр детектора — стерео-узел: частота и Q сглаживаются, как у полос EqUnit (L и R — свои отрезки
// траектории), при каждом изменении частоты, усиления или Q полосы.
// На цепочку EqUnit и полосу (индекс c·8 + k) — свой детектор; новая цепочка — с пустым состоянием (новые узлы).
// Источник: 0 SELF — вход канала до EQ (линия 0), n — выход дорожки n (EqUnit.trackL/R; нет — тишина).

public final class EqDetectors {
    static let n = 2 * EqSpec.bands
    static let attackMs: Double = 5
    static let releaseMs: Double = 100
    static let spanDb: Double = 12
    /// Q фильтра детектора у shelf (Math.SQRT1_2; у ФНЧ и ФВЧ Web Audio — в dB).
    static let shelfQ: Double = 0.7071067811865476
    /// Тип фильтра детектора «полосовой» для EqCoeffs.coeffs.
    static let bandpass = 6

    let kAtt: Double
    let kRel: Double
    /// Источник (−1 — полоса не динамическая), режим M/S, порог, сдвиг, тип фильтра.
    let src: UnsafeMutablePointer<Int>
    let ms: UnsafeMutablePointer<Int>
    let thr: UnsafeMutablePointer<Double>
    let range: UnsafeMutablePointer<Double>
    let kind: UnsafeMutablePointer<Int>
    // Сглаживание фильтра детектора — как у полос EqUnit.
    let tf: UnsafeMutablePointer<Double>
    let tq: UnsafeMutablePointer<Double>
    let sf: UnsafeMutablePointer<Double>
    let sq: UnsafeMutablePointer<Double>
    let el: UnsafeMutablePointer<Int>
    let fresh: UnsafeMutablePointer<UInt8>
    let changed: UnsafeMutablePointer<UInt8>
    let moving: UnsafeMutablePointer<UInt8>
    let co: UnsafeMutablePointer<Double>
    let coR: UnsafeMutablePointer<Double>
    /// Состояние фильтра: L (x1, x2, y1, y2), R; огибающая.
    let st: UnsafeMutablePointer<Double>
    let env: UnsafeMutablePointer<Double>
    /// Сдвиг усиления на каждый отсчёт блока: индекс·maxFrames; последний — для экрана.
    let off: UnsafeMutablePointer<Float>
    let last: UnsafeMutablePointer<Float>
    /// В блоке есть ненулевой сдвиг; коэффициенты полосы надо пересчитать без сдвига.
    let live: UnsafeMutablePointer<UInt8>
    let dirty: UnsafeMutablePointer<UInt8>
    let ramp: UnsafeMutablePointer<Double>
    let bufL: UnsafeMutablePointer<Float>
    let bufR: UnsafeMutablePointer<Float>

    init(sampleRate sr: Double) {
        kAtt = exp(-1 / (EqDetectors.attackMs / 1000 * sr))
        kRel = exp(-1 / (EqDetectors.releaseMs / 1000 * sr))
        let n = EqDetectors.n
        src = .allocate(capacity: n)
        src.initialize(repeating: -1, count: n)
        ms = .allocate(capacity: n)
        kind = .allocate(capacity: n)
        el = .allocate(capacity: n)
        for p in [ms, kind, el] { p.initialize(repeating: 0, count: n) }
        thr = .allocate(capacity: n)
        range = .allocate(capacity: n)
        tf = .allocate(capacity: n)
        tq = .allocate(capacity: n)
        sf = .allocate(capacity: n)
        sq = .allocate(capacity: n)
        env = .allocate(capacity: n)
        for p in [thr, range, tf, tq, sf, sq, env] { p.initialize(repeating: 0, count: n) }
        fresh = .allocate(capacity: n)
        changed = .allocate(capacity: n)
        moving = .allocate(capacity: n)
        live = .allocate(capacity: n)
        dirty = .allocate(capacity: n)
        for p in [fresh, changed, moving, live, dirty] { p.initialize(repeating: 0, count: n) }
        co = .allocate(capacity: n * 5)
        co.initialize(repeating: 0, count: n * 5)
        coR = .allocate(capacity: n * 5)
        coR.initialize(repeating: 0, count: n * 5)
        st = .allocate(capacity: n * 8)
        st.initialize(repeating: 0, count: n * 8)
        off = .allocate(capacity: n * EqUnit.maxFrames)
        off.initialize(repeating: 0, count: n * EqUnit.maxFrames)
        last = .allocate(capacity: n)
        last.initialize(repeating: 0, count: n)
        ramp = .allocate(capacity: 10)
        ramp.initialize(repeating: 0, count: 10)
        bufL = .allocate(capacity: EqUnit.maxFrames)
        bufR = .allocate(capacity: EqUnit.maxFrames)
        bufL.initialize(repeating: 0, count: EqUnit.maxFrames)
        bufR.initialize(repeating: 0, count: EqUnit.maxFrames)
    }

    deinit {
        for p in [src, ms, kind, el] { p.deallocate() }
        for p in [thr, range, tf, tq, sf, sq, env, co, coR, st, ramp] { p.deallocate() }
        for p in [fresh, changed, moving, live, dirty] { p.deallocate() }
        off.deallocate()
        last.deallocate()
        bufL.deallocate()
        bufR.deallocate()
    }

    /// Тип фильтра детектора по типу полосы.
    static func detKind(_ band: Int) -> Int {
        if band == EqSpec.lowShelf { return EqSpec.highCut }
        if band == EqSpec.highShelf { return EqSpec.lowCut }
        return EqDetectors.bandpass
    }

    /// Новый детектор полосы i (новая цепочка): значения сразу, пустое состояние. p — значения полосы в снимке.
    func reset(_ i: Int, _ p: UnsafePointer<Double>, _ band: Int, _ sr: Double) {
        let s: Int = band >= 0 ? Int(p[6]) : -1
        src[i] = s
        moving[i] = 0
        changed[i] = 0
        dirty[i] = 0
        live[i] = 0
        env[i] = 0
        last[i] = 0
        (st + i * 8).update(repeating: 0, count: 8)
        (off + i * EqUnit.maxFrames).update(repeating: 0, count: EqUnit.maxFrames)
        if s < 0 { return }
        kind[i] = EqDetectors.detKind(band)
        ms[i] = Int(p[5])
        thr[i] = p[7]
        range[i] = p[8]
        tf[i] = p[2]
        tq[i] = band == EqSpec.bell ? p[4] : EqDetectors.shelfQ
        EqCoeffs.coeffs(kind[i], tf[i], 0, tq[i], sr, co + i * 5)
    }

    /// Изменились частота, усиление или Q полосы: новое сглаживание фильтра детектора (как setDetFilter веба).
    func retarget(_ i: Int, _ p: UnsafePointer<Double>, _ band: Int, decay: Double) {
        if src[i] < 0 { return }
        if moving[i] != 0 {
            let e: Double = exp(Double(el[i]) * decay)
            sf[i] = tf[i] + (sf[i] - tf[i]) * e
            sq[i] = tq[i] + (sq[i] - tq[i]) * e
        } else {
            sf[i] = tf[i]
            sq[i] = tq[i]
        }
        tf[i] = p[2]
        tq[i] = band == EqSpec.bell ? p[4] : EqDetectors.shelfQ
        el[i] = 0
        fresh[i] = changed[i] == 0 ? 1 : 0
        changed[i] = 1
        moving[i] = 1
    }

    /// Порог и сдвиг — без кроссфейда (как сообщение детектору).
    @inline(__always)
    func setLevels(_ i: Int, _ p: UnsafePointer<Double>) {
        if src[i] < 0 { return }
        thr[i] = p[7]
        range[i] = p[8]
    }

    /// Блок n отсчётов детектора i: источник (l, r; nil — тишина) → сдвиг усиления off[i]. live[i] — сдвиг не нулевой.
    func run(_ i: Int, _ l: UnsafeMutablePointer<Float>?, _ r: UnsafeMutablePointer<Float>?, _ n: Int, sr: Double,
             decay: Double) {
        let o = off + i * EqUnit.maxFrames
        let z = st + i * 8
        let fl = bufL, fr = bufR
        var quiet = true
        if let sl = l, let sr0 = r {
            fl.update(from: sl, count: n)
            fr.update(from: sr0, count: n)
            var j = 0
            while j < n {
                if fl[j] != 0 || fr[j] != 0 { quiet = false; break }
                j += 1
            }
        } else {
            fl.update(repeating: 0, count: n)
            fr.update(repeating: 0, count: n)
        }
        // Тишина, затихший фильтр и огибающая ниже −120 dB (порог не ниже −60): сдвиг 0, считать нечего.
        if quiet && env[i] < 1e-6 && EqDetectors.still(z) && moving[i] == 0 {
            z.update(repeating: 0, count: 8)
            env[i] = 0
            if live[i] != 0 || last[i] != 0 { o.update(repeating: 0, count: n) }
            live[i] = 0
            last[i] = 0
            return
        }
        filter(i, fl, fr, n, sr: sr, decay: decay)
        // Огибающая и сдвиг (eqdyn-worklet.js: расчёт в Double, выход — Float).
        let ka: Double = kAtt, kr: Double = kRel
        let t: Double = thr[i], rg: Double = range[i]
        let mode: Int = ms[i]
        // Уровень порога: выше него — log10.
        let lim: Double = pow(10, t / 20) - 1e-12
        let span: Double = EqDetectors.spanDb
        var e: Double = env[i]
        var any = false
        var v: Float = 0
        var j = 0
        while j < n {
            let a0: Double = Double(fl[j])
            let b0: Double = Double(fr[j])
            var a: Double
            if mode == 1 {
                let s: Double = a0 + b0
                a = (s < 0 ? -s : s) * 0.5
            } else if mode == 2 {
                let s: Double = a0 - b0
                a = (s < 0 ? -s : s) * 0.5
            } else {
                let x: Double = a0 < 0 ? -a0 : a0
                let y: Double = b0 < 0 ? -b0 : b0
                a = x > y ? x : y
            }
            e = a + (e - a) * (a > e ? ka : kr) + 1e-25
            v = 0
            if e > lim {
                let over: Double = 20 * log10(e + 1e-12) - t
                if over > 0 {
                    let u: Double = over / span
                    v = Float(rg * (u < 1 ? u : 1))
                }
            }
            if v != 0 { any = true }
            o[j] = v
            j += 1
        }
        env[i] = e
        live[i] = any ? 1 : 0
        last[i] = v
    }

    /// Состояние фильтра затихло (≈ −180 dB).
    @inline(__always)
    static func still(_ z: UnsafeMutablePointer<Double>) -> Bool {
        var k = 0
        while k < 8 {
            let v: Double = z[k] < 0 ? -z[k] : z[k]
            if v >= EqUnit.quiet { return false }
            k += 1
        }
        return true
    }

    /// Фильтр детектора на месте (l, r), квантами по 128 со сглаживанием — как EqUnit.runBand.
    private func filter(_ i: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int,
                        sr: Double, decay: Double) {
        let cp = co + i * 5
        let cr = coR + i * 5
        let z = st + i * 8
        let q = EqUnit.quantum
        var a = 0
        while a < n {
            let m = Swift.min(q, n - a)
            if moving[i] == 0 {
                EqUnit.biquad(l + a, m, cp, z)
                EqUnit.biquad(r + a, m, cp, z + 4)
                a += m
                continue
            }
            let eL = el[i]
            let eR = fresh[i] != 0 ? eL : eL + q
            el[i] += fresh[i] != 0 ? q : 2 * q
            fresh[i] = 0
            let dl = ramp, dr = ramp + 5
            coeffsAt(i, Double(eL), sr, decay, cp)
            coeffsAt(i, Double(eR), sr, decay, cr)
            var j = 0
            while j < m {
                let w = Swift.min(EqUnit.sub, m - j)
                coeffsAt(i, Double(eL + j + w), sr, decay, dl)
                coeffsAt(i, Double(eR + j + w), sr, decay, dr)
                let inv: Double = 1 / Double(w)
                var t = 0
                while t < 5 {
                    dl[t] = (dl[t] - cp[t]) * inv
                    dr[t] = (dr[t] - cr[t]) * inv
                    t += 1
                }
                EqUnit.biquadRamp(l + a + j, w, cp, dl, z)
                EqUnit.biquadRamp(r + a + j, w, cr, dr, z + 4)
                t = 0
                while t < 5 {
                    cp[t] += dl[t] * Double(w)
                    cr[t] += dr[t] * Double(w)
                    t += 1
                }
                j += w
            }
            if Double(el[i]) * decay < -16.2 {
                moving[i] = 0
                EqCoeffs.coeffs(kind[i], tf[i], 0, tq[i], sr, cp)
            }
            a += m
        }
    }

    private func coeffsAt(_ i: Int, _ e: Double, _ sr: Double, _ decay: Double, _ out: UnsafeMutablePointer<Double>) {
        let x: Double = exp(e * decay)
        let f: Double = tf[i] + (sf[i] - tf[i]) * x
        let q: Double = tq[i] + (sq[i] - tq[i]) * x
        EqCoeffs.coeffs(kind[i], f, 0, q, sr, out)
    }
}

/// Сдвиг усиления динамических полос для экрана (анимация точки и кривой): канал·8 + полоса, dB; пишет колбэк
/// после EQ канала, экран читает по таймеру.
public final class EqDynLevels: @unchecked Sendable {
    let v: [AtomicFloat]

    public init() {
        v = (0..<(EqSpec.channels * EqSpec.bands)).map { _ in AtomicFloat(0) }
    }

    /// Сдвиги текущей цепочки EQ канала ch.
    @inline(__always)
    func publish(_ ch: Int, _ u: EqUnit) {
        var k = 0
        while k < EqSpec.bands {
            v[ch * EqSpec.bands + k].store(u.dynOffset(k))
            k += 1
        }
    }

    public func offset(_ ch: Int, _ k: Int) -> Float {
        let i = ch * EqSpec.bands + k
        return i >= 0 && i < v.count ? v[i].load() : 0
    }
}
