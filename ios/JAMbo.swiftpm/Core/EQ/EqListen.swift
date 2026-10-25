import Foundation

// Прослушивание полосы EQ (как соло полосы в FabFilter Pro-Q): пока держат LISTEN в строке EQ, канал EQ звучит
// только в области выбранной полосы — после своего EQ фильтр: bell и notch — полосовой на частоте
// и Q полосы (0 dB на вершине), low cut и low shelf — ФНЧ на частоте полосы, high cut и high shelf — ФВЧ
// (Баттерворт, 12 dB/окт); усиление полосы и Dynamic не учитываются. У полосы MID — середина (L+R)/2 на оба канала,
// у SIDE — бока (L−R)/2 (L = S, R = −S). Включение и выключение — плавно (10 мс), частота при перетаскивании —
// сглаживание по блокам (τ 20 мс) с линейным ходом коэффициентов внутри блока. Слушается один канал сразу; другой
// канал начинает, когда прежний затих. Цель ставит UI (атомарные значения), всё остальное — в колбэке.

public final class EqListen: @unchecked Sendable {
    public static let bandpass = 0, lowpass = 1, highpass = 2
    static let fadeFrames: Float = 480
    static let tau: Double = 0.02
    /// Q ФНЧ и ФВЧ в dB (как Q у lowpass/highpass Web Audio): 1/√2.
    static let butterQ: Double = -3.0102999566398116
    static let maxLanes = TrackEqs.lanes

    /// Канал EQ (дорожка, EqSpec.masterChannel; −1 — не слушать), фильтр, частота, Q, режим M/S — пишет UI.
    public let channel = AtomicCounter()
    public let kind = AtomicCounter()
    public let ms = AtomicCounter()
    public let freq = AtomicFloat(1000)
    public let q = AtomicFloat(1)

    let sr: Double
    /// Канал, который сейчас звучит через фильтр (−1 — нет), доля фильтра (0…1).
    var active = -1
    var mix: Float = 0
    var curKind = -1
    var curFreq: Double = 1000
    var curQ: Double = 1
    var curMs = 0
    /// Коэффициенты начала блока, приращения за отсчёт, конца блока.
    let co: UnsafeMutablePointer<Double>
    let dc: UnsafeMutablePointer<Double>
    let next: UnsafeMutablePointer<Double>
    /// Состояние: линия × (L, R) × (x1, x2, y1, y2).
    let st: UnsafeMutablePointer<Double>
    let tmpL: UnsafeMutablePointer<Float>
    let tmpR: UnsafeMutablePointer<Float>

    public init(sampleRate: Double) {
        sr = sampleRate
        channel.store(-1)
        co = .allocate(capacity: 5)
        dc = .allocate(capacity: 5)
        next = .allocate(capacity: 5)
        for p in [co, dc, next] { p.initialize(repeating: 0, count: 5) }
        st = .allocate(capacity: EqListen.maxLanes * 8)
        st.initialize(repeating: 0, count: EqListen.maxLanes * 8)
        tmpL = .allocate(capacity: EqUnit.maxFrames)
        tmpR = .allocate(capacity: EqUnit.maxFrames)
        tmpL.initialize(repeating: 0, count: EqUnit.maxFrames)
        tmpR.initialize(repeating: 0, count: EqUnit.maxFrames)
    }

    deinit {
        for p in [co, dc, next, st] { p.deallocate() }
        tmpL.deallocate()
        tmpR.deallocate()
    }

    /// Фильтр прослушивания полосы: тип EqListen и Q фильтра.
    public static func filter(_ b: EqBand) -> (kind: Int, q: Double) {
        switch b.type {
        case EqSpec.lowCut, EqSpec.lowShelf: return (lowpass, butterQ)
        case EqSpec.highCut, EqSpec.highShelf: return (highpass, butterQ)
        default: return (bandpass, Swift.max(0.1, b.q))
        }
    }

    /// Коэффициенты фильтра (тип EqListen) — формулами EqCoeffs.
    static func coeffs(_ kind: Int, _ hz: Double, _ q: Double, _ sr: Double, _ out: UnsafeMutablePointer<Double>) {
        let t: Int = kind == lowpass ? EqSpec.highCut : (kind == highpass ? EqSpec.lowCut : EqDetectors.bandpass)
        EqCoeffs.coeffs(t, hz, 0, q, sr, out)
    }

    /// Область прослушивания полосы, Гц (подсветка на поле EQ): у полосового — ширина по Q, края по −3 dB
    /// (f·(√(1 + 1/(4Q²)) ∓ 1/(2Q)), ширина f/Q); у ФНЧ — от 0 до частоты, у ФВЧ — от частоты до бесконечности.
    public static func span(_ b: EqBand) -> (lo: Double, hi: Double) {
        let f = filter(b)
        if f.kind == lowpass { return (0, b.freq) }
        if f.kind == highpass { return (b.freq, Double.infinity) }
        let h: Double = 1 / (2 * f.q)
        let r: Double = (1 + h * h).squareRoot()
        return (b.freq * (r - h), b.freq * (r + h))
    }

    /// Канал ch молчит в этом блоке (EQ без звука): если он звучал через фильтр — отпустить сразу.
    public func idle(_ ch: Int) {
        if active == ch {
            active = -1
            mix = 0
        }
    }

    /// Блок n отсчётов канала ch после его EQ, на месте во всех линиях u (laneL, laneR).
    public func process(_ ch: Int, _ u: EqUnit, _ frames: Int) {
        let target: Int = channel.load()
        if active != ch {
            if active >= 0 || target != ch { return }
            active = ch
            mix = 0
            curKind = -1
            st.update(repeating: 0, count: EqListen.maxLanes * 8)
        }
        let n = Swift.min(frames, EqUnit.maxFrames)
        if n <= 0 { return }
        let on: Bool = target == ch
        if on { prepare(n) } else { hold() }
        let lanes = Swift.min(u.lanes, EqListen.maxLanes)
        let m0 = mix
        var lane = 0
        while lane < lanes {
            if let l = u.laneL[lane], let r = u.laneR[lane] { run(lane, l, r, n, m0, on) }
            lane += 1
        }
        let step: Float = Float(n) / EqListen.fadeFrames
        mix = on ? Swift.min(1, m0 + step) : Swift.max(0, m0 - step)
        var t = 0
        while t < 5 {
            co[t] = next[t]
            t += 1
        }
        if !on && mix <= 0 { active = -1 }
    }

    /// Цель фильтра на этот блок: тип и M/S — сразу (новый тип — с пустым состоянием), частота и Q — сглаживание.
    private func prepare(_ n: Int) {
        let k: Int = kind.load()
        let f: Double = Swift.max(10, Swift.min(sr * 0.49, Double(freq.load())))
        let qq: Double = Double(q.load())
        let msNew: Int = ms.load()
        if k != curKind || msNew != curMs {
            curKind = k
            curMs = msNew
            curFreq = f
            curQ = qq
            st.update(repeating: 0, count: EqListen.maxLanes * 8)
            EqListen.coeffs(k, f, qq, sr, co)
        } else {
            let a: Double = 1 - exp(-Double(n) / (EqListen.tau * sr))
            curFreq = exp(log(curFreq) + (log(f) - log(curFreq)) * a)
            curQ = curQ + (qq - curQ) * a
        }
        EqListen.coeffs(curKind, curFreq, curQ, sr, next)
        let inv: Double = 1 / Double(n)
        var t = 0
        while t < 5 {
            dc[t] = (next[t] - co[t]) * inv
            t += 1
        }
    }

    /// Затухание: коэффициенты не меняются.
    private func hold() {
        var t = 0
        while t < 5 {
            dc[t] = 0
            next[t] = co[t]
            t += 1
        }
    }

    /// Одна линия: фильтр по копии сигнала, затем смесь сигнала и фильтра по доле mix.
    private func run(_ lane: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int,
                     _ m0: Float, _ on: Bool) {
        let z = st + lane * 8
        let msMode = curMs
        var i = 0
        if msMode == 0 {
            tmpL.update(from: l, count: n)
            tmpR.update(from: r, count: n)
            EqUnit.biquadRamp(tmpL, n, co, dc, z)
            EqUnit.biquadRamp(tmpR, n, co, dc, z + 4)
        } else {
            let side: Bool = msMode == 2
            while i < n {
                let hl: Float = l[i] * 0.5
                let hr: Float = r[i] * 0.5
                tmpL[i] = side ? hl - hr : hl + hr
                i += 1
            }
            EqUnit.biquadRamp(tmpL, n, co, dc, z)
            i = 0
            while i < n {
                tmpR[i] = side ? -tmpL[i] : tmpL[i]
                i += 1
            }
        }
        let step: Float = (on ? 1 : -1) / EqListen.fadeFrames
        var m: Float = m0
        i = 0
        while i < n {
            m = Swift.max(0, Swift.min(1, m + step))
            l[i] += (tmpL[i] - l[i]) * m
            r[i] += (tmpR[i] - r[i]) * m
            i += 1
        }
    }
}
