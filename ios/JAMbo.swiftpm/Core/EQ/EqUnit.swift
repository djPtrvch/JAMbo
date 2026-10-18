import Foundation

// EQ одного канала в колбэке — как EqChain в src/audio/eq.ts: полосы — биквады BiquadFilterNode (EqCoeffs; как
// Biquad.cpp в Blink/WebKit: коэффициенты и состояние в Double, между ступенями каскада — Float); low cut и high cut
// 24 и 48 dB/окт — каскад из 2 и 4 одинаковых биквадов.
// Частота, усиление и Q меняются плавно (как setTargetAtTime, τ 20 мс) — с особенностью Web Audio: у стерео-узла
// каждый канал заново продвигает автоматизацию на квант 128 отсчётов. Поэтому L в кванте q (от начала изменения)
// идёт по отрезку траектории (2q − 1)·128, R — 2q·128, в первом кванте оба — с начала; так — у первого изменения
// полосы после создания цепочки, у следующих L — 2q·128, R — (2q + 1)·128 (замерено в Chromium). На время
// сглаживания у L и R свои коэффициенты: точные на краях кусков sub отсчётов, между ними — линейно по отсчётам
// (Web Audio считает их на каждый отсчёт). Смена набора полос (включение, тип, крутизна, M/S, BYPASS) — новая цепочка
// с пустым состоянием и линейный кроссфейд 40 мс (как в вебе: усиление цепочки — до её полос); смена во время
// кроссфейда ждёт его конца. После кроссфейда хвост фильтров прежней цепочки звучит до затухания (в вебе её узлы
// живут ещё ~150 мс, хвост — после усиления); новая смена в это время хвост обрывает.
// Линии — стерео-сигналы с одним EQ (дорожка: сухой сигнал и посылы Reverb, Delay, Drive — в вебе у каждого своя
// копия EqChain с теми же событиями): коэффициенты считаются один раз, состояние и кроссфейд — у каждой линии.
// Линия без сигнала, у которой хвост фильтров затих, не считается; молчащий канал — idle.
// Полоса MID или SIDE (S7a) фильтрует один канал M/S — EqUnitMs.swift.
// Цепочки две (0 и 1): у каждой на полосу тип, каскад, режим M/S, цель, начало и ход сглаживания, коэффициенты.
// Параметры — из снимка звука (EqSpec.fill). Всё в колбэке: память выделена при создании.

public final class EqUnit {
    static let bands = EqSpec.bands
    static let maxStages = 4
    static let fadeFrames = 1920
    static let tau: Double = 0.02
    static let sub = 32
    static let quantum = 128
    static let maxFrames = 4096
    /// Состояние полосы одной линии: ступени × (L, R) × (x1, x2, y1, y2).
    static let bandState = maxStages * 8
    /// Порог «тишины» состояния (≈ −180 dB): ниже — состояние обнуляется, линия больше не звучит.
    static let quiet: Double = 1e-9

    let sr: Double
    /// −1/(τ·sr): затухание разницы с целью за отсчёт (показатель экспоненты).
    let decay: Double
    public let lanes: Int
    // На цепочку c и полосу k — индекс c·8 + k.
    let kind: UnsafeMutablePointer<Int>
    let nst: UnsafeMutablePointer<Int>
    /// Режим M/S: 0 STEREO, 1 MID, 2 SIDE.
    let msm: UnsafeMutablePointer<Int>
    let tf: UnsafeMutablePointer<Double>
    let tg: UnsafeMutablePointer<Double>
    let tq: UnsafeMutablePointer<Double>
    /// Значения в начале сглаживания; ход — отсчётов траектории от его начала; первый квант (у первого изменения
    /// полосы после создания цепочки — общий для L и R); было ли уже изменение; идёт ли сглаживание.
    let sf: UnsafeMutablePointer<Double>
    let sg: UnsafeMutablePointer<Double>
    let sq: UnsafeMutablePointer<Double>
    let el: UnsafeMutablePointer<Int>
    let fresh: UnsafeMutablePointer<UInt8>
    let changed: UnsafeMutablePointer<UInt8>
    let moving: UnsafeMutablePointer<UInt8>
    /// Коэффициенты b0, b1, b2, a1, a2 (нормированы на a0); coR — у R во время сглаживания.
    let co: UnsafeMutablePointer<Double>
    let coR: UnsafeMutablePointer<Double>
    /// Приращения коэффициентов L и R за отсчёт (5 + 5).
    let ramp: UnsafeMutablePointer<Double>
    /// Состояние: ((линия·2 + c)·8 + k)·bandState + ступень·8 + канал·4 + (x1, x2, y1, y2).
    let st: UnsafeMutablePointer<Double>
    /// Вход прежней цепочки на время кроссфейда: линия·maxFrames.
    let oldL: UnsafeMutablePointer<Float>
    let oldR: UnsafeMutablePointer<Float>
    /// Середина и бока линии для полос MID/SIDE: линия·maxFrames.
    let midBuf: UnsafeMutablePointer<Float>
    let sideBuf: UnsafeMutablePointer<Float>
    /// Сигналы линий на этот блок (ставит вызывающий; nil — линии нет), считается ли линия, звучит ли хвост.
    public let laneL: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    public let laneR: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    let live: UnsafeMutablePointer<UInt8>
    let ring: UnsafeMutablePointer<UInt8>
    var cur = 0
    /// Отсчётов кроссфейда пройдено (fadeFrames — звучит хвост прежней цепочки); −1 — кроссфейда нет.
    var fadePos = -1

    public init(sampleRate: Double, lanes: Int = 1) {
        sr = sampleRate
        decay = -1 / (EqUnit.tau * sampleRate)
        self.lanes = lanes
        let n = 2 * EqUnit.bands
        kind = .allocate(capacity: n)
        kind.initialize(repeating: -1, count: n)
        nst = .allocate(capacity: n)
        nst.initialize(repeating: 1, count: n)
        msm = .allocate(capacity: n)
        msm.initialize(repeating: 0, count: n)
        tf = .allocate(capacity: n)
        tg = .allocate(capacity: n)
        tq = .allocate(capacity: n)
        sf = .allocate(capacity: n)
        sg = .allocate(capacity: n)
        sq = .allocate(capacity: n)
        for p in [tf, tg, tq, sf, sg, sq] { p.initialize(repeating: 0, count: n) }
        el = .allocate(capacity: n)
        el.initialize(repeating: 0, count: n)
        fresh = .allocate(capacity: n)
        changed = .allocate(capacity: n)
        moving = .allocate(capacity: n)
        for p in [fresh, changed, moving] { p.initialize(repeating: 0, count: n) }
        co = .allocate(capacity: n * 5)
        co.initialize(repeating: 0, count: n * 5)
        coR = .allocate(capacity: n * 5)
        coR.initialize(repeating: 0, count: n * 5)
        ramp = .allocate(capacity: 10)
        ramp.initialize(repeating: 0, count: 10)
        st = .allocate(capacity: lanes * n * EqUnit.bandState)
        st.initialize(repeating: 0, count: lanes * n * EqUnit.bandState)
        oldL = .allocate(capacity: lanes * EqUnit.maxFrames)
        oldR = .allocate(capacity: lanes * EqUnit.maxFrames)
        oldL.initialize(repeating: 0, count: lanes * EqUnit.maxFrames)
        oldR.initialize(repeating: 0, count: lanes * EqUnit.maxFrames)
        midBuf = .allocate(capacity: lanes * EqUnit.maxFrames)
        sideBuf = .allocate(capacity: lanes * EqUnit.maxFrames)
        midBuf.initialize(repeating: 0, count: lanes * EqUnit.maxFrames)
        sideBuf.initialize(repeating: 0, count: lanes * EqUnit.maxFrames)
        laneL = .allocate(capacity: lanes)
        laneR = .allocate(capacity: lanes)
        laneL.initialize(repeating: nil, count: lanes)
        laneR.initialize(repeating: nil, count: lanes)
        live = .allocate(capacity: lanes)
        ring = .allocate(capacity: lanes)
        live.initialize(repeating: 0, count: lanes)
        ring.initialize(repeating: 0, count: lanes)
    }

    deinit {
        kind.deallocate()
        nst.deallocate()
        msm.deallocate()
        midBuf.deallocate()
        sideBuf.deallocate()
        for p in [tf, tg, tq, sf, sg, sq, co, coR, ramp, st] { p.deallocate() }
        for p in [fresh, changed, moving, live, ring] { p.deallocate() }
        el.deallocate()
        oldL.deallocate()
        oldR.deallocate()
        laneL.deallocate()
        laneR.deallocate()
    }

    /// Хвост фильтров линии ещё звучит — её нужно считать и без входа.
    @inline(__always)
    public func ringing(_ lane: Int) -> Bool { return ring[lane] != 0 }

    /// Один стерео-сигнал (линия 0) на месте.
    public func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int,
                        params p: UnsafePointer<Double>) {
        laneL[0] = left
        laneR[0] = right
        process(frames: frames, params: p)
    }

    /// Блок n отсчётов на месте во всех линиях (laneL, laneR); p — параметры канала (EqSpec.stride значений).
    public func process(frames: Int, params p: UnsafePointer<Double>) {
        let n = Swift.min(frames, EqUnit.maxFrames)
        if (fadePos < 0 || fadePos >= EqUnit.fadeFrames) && !same(p, cur) { startFade(p) }
        setTargets(p, cur)
        var any = false
        var k = 0
        while k < lanes {
            live[k] = 0
            if let l = laneL[k], let r = laneR[k], ring[k] != 0 || !silent(l, r, n) {
                live[k] = 1
                any = true
            }
            k += 1
        }
        if !any {
            snap(cur)
            if fadePos >= 0 { endFade(n) }
            return
        }
        if fadePos >= 0 {
            fadeIn(n)
            run(1 - cur, n, old: true)
        }
        run(cur, n, old: false)
        if fadePos >= 0 {
            mixFade(n)
            endFade(n)
        }
        k = 0
        while k < lanes {
            if live[k] != 0 { ring[k] = settle(k) ? 1 : 0 }
            k += 1
        }
    }

    /// Канал молчит (вход — тишина, хвостов нет; Sampler не считает дорожку): набор полос и значения — сразу, без
    /// кроссфейда и сглаживания (в вебе кроссфейд прошёл бы в тишине).
    public func idle(params p: UnsafePointer<Double>) {
        if fadePos >= 0 || !same(p, cur) {
            startFade(p)
            fadePos = -1
            st.update(repeating: 0, count: lanes * 2 * EqUnit.bands * EqUnit.bandState)
        }
        setTargets(p, cur)
        snap(cur)
    }

    /// Набор полос цепочки c совпадает с параметрами (тип, каскад и режим M/S каждой полосы).
    private func same(_ p: UnsafePointer<Double>, _ c: Int) -> Bool {
        var k = 0
        while k < EqUnit.bands {
            let o = 1 + k * EqSpec.bandStride
            let t = Int(p[o])
            if kind[c * EqUnit.bands + k] != t { return false }
            if t >= 0 && nst[c * EqUnit.bands + k] != Int(p[o + 1]) { return false }
            if t >= 0 && msm[c * EqUnit.bands + k] != Int(p[o + 5]) { return false }
            k += 1
        }
        return true
    }

    /// Новая цепочка: полосы из p со значениями сразу (как setNode без сглаживания), пустое состояние, кроссфейд.
    private func startFade(_ p: UnsafePointer<Double>) {
        let c = 1 - cur
        var k = 0
        while k < EqUnit.bands {
            let i = c * EqUnit.bands + k
            let o = 1 + k * EqSpec.bandStride
            kind[i] = Int(p[o])
            nst[i] = Swift.max(1, Swift.min(EqUnit.maxStages, Int(p[o + 1])))
            tf[i] = p[o + 2]
            tg[i] = p[o + 3]
            tq[i] = p[o + 4]
            msm[i] = Int(p[o + 5])
            moving[i] = 0
            changed[i] = 0
            if kind[i] >= 0 { EqCoeffs.coeffs(kind[i], tf[i], tg[i], tq[i], sr, co + i * 5) }
            k += 1
        }
        let m = EqUnit.bands * EqUnit.bandState
        var lane = 0
        while lane < lanes {
            (st + (lane * 2 + c) * m).update(repeating: 0, count: m)
            lane += 1
        }
        cur = c
        fadePos = 0
    }

    private func setTargets(_ p: UnsafePointer<Double>, _ c: Int) {
        var k = 0
        while k < EqUnit.bands {
            let i = c * EqUnit.bands + k
            let o = 1 + k * EqSpec.bandStride
            let f = p[o + 2], g = p[o + 3], q = p[o + 4]
            if kind[i] >= 0 && kind[i] == Int(p[o]) && (f != tf[i] || g != tg[i] || q != tq[i]) {
                // Новое сглаживание (setTargetAtTime): от значения, до которого дошло прежнее.
                if moving[i] != 0 {
                    let e: Double = exp(Double(el[i]) * decay)
                    sf[i] = tf[i] + (sf[i] - tf[i]) * e
                    sg[i] = tg[i] + (sg[i] - tg[i]) * e
                    sq[i] = tq[i] + (sq[i] - tq[i]) * e
                } else {
                    sf[i] = tf[i]
                    sg[i] = tg[i]
                    sq[i] = tq[i]
                }
                tf[i] = f
                tg[i] = g
                tq[i] = q
                el[i] = 0
                fresh[i] = changed[i] == 0 ? 1 : 0
                changed[i] = 1
                moving[i] = 1
            }
            k += 1
        }
    }

    /// Без звука: значения сразу к цели.
    private func snap(_ c: Int) {
        var k = 0
        while k < EqUnit.bands {
            let i = c * EqUnit.bands + k
            if kind[i] >= 0 && moving[i] != 0 {
                moving[i] = 0
                EqCoeffs.coeffs(kind[i], tf[i], tg[i], tq[i], sr, co + i * 5)
            }
            k += 1
        }
    }

    private func silent(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) -> Bool {
        var i = 0
        while i < n {
            if l[i] != 0 || r[i] != 0 { return false }
            i += 1
        }
        return true
    }

    /// Состояние линии затихло — обнулить; true — ещё звучит.
    private func settle(_ lane: Int) -> Bool {
        let m = 2 * EqUnit.bands * EqUnit.bandState
        let s = st + lane * m
        var peak: Double = 0
        var i = 0
        while i < m {
            let v = Swift.abs(s[i])
            if v > peak { peak = v }
            i += 1
        }
        if peak < EqUnit.quiet {
            if peak > 0 { s.update(repeating: 0, count: m) }
            return false
        }
        return true
    }

    /// Кроссфейд (как в вебе, усиление цепочки — до её полос): вход прежней цепочки (oldL, oldR) — · (1 → 0),
    /// новой (линия) — · (0 → 1) за fadeFrames.
    private func fadeIn(_ n: Int) {
        let total = Float(EqUnit.fadeFrames)
        var lane = 0
        while lane < lanes {
            if live[lane] != 0, let l = laneL[lane], let r = laneR[lane] {
                let fl = oldL + lane * EqUnit.maxFrames, fr = oldR + lane * EqUnit.maxFrames
                var pos = fadePos
                var i = 0
                while i < n {
                    let g: Float = pos >= EqUnit.fadeFrames ? 1 : Float(pos) / total
                    fl[i] = l[i] * (1 - g)
                    fr[i] = r[i] * (1 - g)
                    l[i] *= g
                    r[i] *= g
                    pos += 1
                    i += 1
                }
            }
            lane += 1
        }
    }

    /// Выходы цепочек складываются.
    private func mixFade(_ n: Int) {
        var lane = 0
        while lane < lanes {
            if live[lane] != 0, let l = laneL[lane], let r = laneR[lane] {
                let fl = oldL + lane * EqUnit.maxFrames, fr = oldR + lane * EqUnit.maxFrames
                var i = 0
                while i < n {
                    l[i] += fl[i]
                    r[i] += fr[i]
                    i += 1
                }
            }
            lane += 1
        }
    }

    /// Кроссфейд кончился и хвост прежней цепочки затих — её состояние обнуляется.
    private func endFade(_ n: Int) {
        let pos = fadePos + n
        if pos < EqUnit.fadeFrames {
            fadePos = pos
            return
        }
        fadePos = EqUnit.fadeFrames
        let m = EqUnit.bands * EqUnit.bandState
        var peak: Double = 0
        var lane = 0
        while lane < lanes {
            let s = st + (lane * 2 + 1 - cur) * m
            var i = 0
            while i < m {
                let v = Swift.abs(s[i])
                if v > peak { peak = v }
                i += 1
            }
            lane += 1
        }
        if peak >= EqUnit.quiet { return }
        fadePos = -1
        lane = 0
        while lane < lanes {
            (st + (lane * 2 + 1 - cur) * m).update(repeating: 0, count: m)
            lane += 1
        }
    }

    /// Полосы цепочки c по очереди, квантами по 128 отсчётов; old — сигнал прежней цепочки (oldL, oldR).
    private func run(_ c: Int, _ n: Int, old: Bool) {
        var k = 0
        while k < EqUnit.bands {
            let i = c * EqUnit.bands + k
            if kind[i] >= 0 {
                if msm[i] == 0 { runBand(c, i, n, old) } else { runMsBand(c, i, n, old) }
            }
            k += 1
        }
    }

    /// Сигнал линии lane для цепочки (old — вход прежней цепочки).
    @inline(__always)
    func signal(_ lane: Int, _ old: Bool) -> (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>)? {
        if live[lane] == 0 { return nil }
        if old { return (oldL + lane * EqUnit.maxFrames, oldR + lane * EqUnit.maxFrames) }
        guard let l = laneL[lane], let r = laneR[lane] else { return nil }
        return (l, r)
    }

    private func runBand(_ c: Int, _ i: Int, _ n: Int, _ old: Bool) {
        let stages = nst[i]
        let k = i - c * EqUnit.bands
        let cp = co + i * 5
        let cr = coR + i * 5
        let laneStride = 2 * EqUnit.bands * EqUnit.bandState
        let s0 = st + (c * EqUnit.bands + k) * EqUnit.bandState
        var a = 0
        while a < n {
            let m = Swift.min(EqUnit.quantum, n - a)
            if moving[i] == 0 {
                var lane = 0
                while lane < lanes {
                    if let (l, r) = signal(lane, old) {
                        let z = s0 + lane * laneStride
                        var s = 0
                        while s < stages {
                            EqUnit.biquad(l + a, m, cp, z + s * 8)
                            EqUnit.biquad(r + a, m, cp, z + s * 8 + 4)
                            s += 1
                        }
                    }
                    lane += 1
                }
                a += m
                continue
            }
            // Отрезки траектории L и R в этом кванте.
            let eL = el[i]
            let eR = fresh[i] != 0 ? eL : eL + EqUnit.quantum
            el[i] += fresh[i] != 0 ? EqUnit.quantum : 2 * EqUnit.quantum
            fresh[i] = 0
            // Коэффициенты — точно на краях кусков sub, между ними — линейно по отсчётам.
            let dl = ramp, dr = ramp + 5
            coeffsAt(i, Double(eL), cp)
            coeffsAt(i, Double(eR), cr)
            var j = 0
            while j < m {
                let w = Swift.min(EqUnit.sub, m - j)
                coeffsAt(i, Double(eL + j + w), dl)
                coeffsAt(i, Double(eR + j + w), dr)
                let inv: Double = 1 / Double(w)
                var t = 0
                while t < 5 {
                    dl[t] = (dl[t] - cp[t]) * inv
                    dr[t] = (dr[t] - cr[t]) * inv
                    t += 1
                }
                var lane = 0
                while lane < lanes {
                    if let (l, r) = signal(lane, old) {
                        let z = s0 + lane * laneStride
                        var s = 0
                        while s < stages {
                            EqUnit.biquadRamp(l + a + j, w, cp, dl, z + s * 8)
                            EqUnit.biquadRamp(r + a + j, w, cr, dr, z + s * 8 + 4)
                            s += 1
                        }
                    }
                    lane += 1
                }
                t = 0
                while t < 5 {
                    cp[t] += dl[t] * Double(w)
                    cr[t] += dr[t] * Double(w)
                    t += 1
                }
                j += w
            }
            // Разница с целью меньше 1e-7 — сглаживание кончилось.
            if Double(el[i]) * decay < -16.2 {
                moving[i] = 0
                EqCoeffs.coeffs(kind[i], tf[i], tg[i], tq[i], sr, cp)
            }
            a += m
        }
    }

    /// Коэффициенты полосы i по значениям траектории сглаживания в отсчёте e от его начала.
    func coeffsAt(_ i: Int, _ e: Double, _ out: UnsafeMutablePointer<Double>) {
        let x: Double = exp(e * decay)
        let f: Double = tf[i] + (sf[i] - tf[i]) * x
        let g: Double = tg[i] + (sg[i] - tg[i]) * x
        let q: Double = tq[i] + (sq[i] - tq[i]) * x
        EqCoeffs.coeffs(kind[i], f, g, q, sr, out)
    }

    /// Одна ступень (Direct Form I, как Biquad::Process): x — Float, y и состояние — Double, выход — Float.
    @inline(__always)
    static func biquad(_ x: UnsafeMutablePointer<Float>, _ n: Int, _ c: UnsafeMutablePointer<Double>,
                       _ z: UnsafeMutablePointer<Double>) {
        let b0 = c[0], b1 = c[1], b2 = c[2], a1 = c[3], a2 = c[4]
        var x1 = z[0], x2 = z[1], y1 = z[2], y2 = z[3]
        var i = 0
        while i < n {
            let xi = Double(x[i])
            let y: Double = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x[i] = Float(y)
            x2 = x1
            x1 = xi
            y2 = y1
            y1 = y
            i += 1
        }
        z[0] = x1
        z[1] = x2
        z[2] = y1
        z[3] = y2
    }

    /// Ступень с коэффициентами, которые меняются линейно: в отсчёте k — c + dc·k.
    @inline(__always)
    static func biquadRamp(_ x: UnsafeMutablePointer<Float>, _ n: Int, _ c: UnsafeMutablePointer<Double>,
                           _ dc: UnsafeMutablePointer<Double>, _ z: UnsafeMutablePointer<Double>) {
        var b0 = c[0], b1 = c[1], b2 = c[2], a1 = c[3], a2 = c[4]
        let d0 = dc[0], d1 = dc[1], d2 = dc[2], d3 = dc[3], d4 = dc[4]
        var x1 = z[0], x2 = z[1], y1 = z[2], y2 = z[3]
        var i = 0
        while i < n {
            let xi = Double(x[i])
            let y: Double = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x[i] = Float(y)
            x2 = x1
            x1 = xi
            y2 = y1
            y1 = y
            b0 += d0
            b1 += d1
            b2 += d2
            a1 += d3
            a2 += d4
            i += 1
        }
        z[0] = x1
        z[1] = x2
        z[2] = y1
        z[3] = y2
    }
}
