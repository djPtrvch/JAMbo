import Foundation

// Лимитер мастера — перенос public/limiter-worklet.js (решение пользователя S5a: без LINK, UNITY, AUDIT — LINK 100 %,
// как по умолчанию в вебе: один gain computer по максимуму L и R, звук тот же). Стерео.
// Вход · GAIN → true peak (4× полифазный FIR, окно Блэкмана) → цель g = min(1, Ceiling/Peak) → скользящий минимум
// за окно lookahead + HOLD → релиз (вниз мгновенно, вверх — экспонента RELEASE или AUTO 30 мс / 400 мс) → скользящее
// среднее окна (рампа к цели) → задержанный сигнал · g → страховочный клип на CEILING. BYPASS — кроссфейд 10 мс
// с тем же задержанным входом; смена LOOKAHEAD — кроссфейд задержек 20 мс. Буферы задержки и FIR — Float32, как в вебе.
// Индикация (S5c): за кадр 256 отсчётов — true peak после GAIN, GR (dB), true peak выхода.

/// Gain computer: история цели и рампы, монотонная очередь скользящего минимума.
final class LimiterGain {
    static let hold = 8
    let maxL: Int
    let tHist: UnsafeMutablePointer<Double>
    let eHist: UnsafeMutablePointer<Double>
    let qIdx: UnsafeMutablePointer<Int>
    let qVal: UnsafeMutablePointer<Double>
    var hpos = 0
    var qHead = 0
    var qLen = 0
    var n = 0
    var sumAge = 0
    var envF: Double = 1
    var envS: Double = 1
    var L: Int
    var sum: Double

    init(maxL: Int, L: Int) {
        self.maxL = maxL
        self.L = L
        sum = Double(L)
        tHist = UnsafeMutablePointer<Double>.allocate(capacity: maxL)
        tHist.initialize(repeating: 1, count: maxL)
        eHist = UnsafeMutablePointer<Double>.allocate(capacity: maxL)
        eHist.initialize(repeating: 1, count: maxL)
        qIdx = UnsafeMutablePointer<Int>.allocate(capacity: maxL + 1)
        qIdx.initialize(repeating: 0, count: maxL + 1)
        qVal = UnsafeMutablePointer<Double>.allocate(capacity: maxL + 1)
        qVal.initialize(repeating: 0, count: maxL + 1)
    }

    deinit {
        tHist.deallocate()
        eHist.deallocate()
        qIdx.deallocate()
        qVal.deallocate()
    }

    /// Новое окно L: очередь минимума и сумма пересобираются из истории.
    func setWindow(_ L: Int) {
        self.L = L
        let M = maxL
        qHead = 0
        qLen = 0
        sum = 0
        var k = L + LimiterGain.hold - 1
        while k >= 0 {
            let pos = (hpos - 1 - k + 2 * M) % M
            _ = pushMin(n - 1 - k, tHist[pos])
            if k < L { sum += eHist[pos] }
            k -= 1
        }
        sumAge = 0
    }

    @inline(__always)
    func pushMin(_ idx: Int, _ v: Double) -> Double {
        let cap = maxL + 1
        while qLen > 0 {
            let tail = (qHead + qLen - 1) % cap
            if qVal[tail] >= v { qLen -= 1 } else { break }
        }
        let at = (qHead + qLen) % cap
        qIdx[at] = idx
        qVal[at] = v
        qLen += 1
        while qIdx[qHead] <= idx - L - LimiterGain.hold {
            qHead = (qHead + 1) % cap
            qLen -= 1
        }
        return qVal[qHead]
    }

    /// Отсчёт: пик pk, потолок ceil → усиление g.
    @inline(__always)
    func step(_ pk: Double, _ ceil: Double, _ auto: Bool, _ kRel: Double, _ kFast: Double, _ kSlow: Double) -> Double {
        let M = maxL
        let t: Double = pk > ceil ? ceil / pk : 1
        let hp = hpos
        tHist[hp] = t
        let h: Double = pushMin(n, t)
        var e: Double
        if auto {
            envF = h < envF ? h : h + (envF - h) * kFast
            envS = h + (envS - h) * kSlow
            e = Swift.min(envF, envS)
        } else {
            envF = h < envF ? h : h + (envF - h) * kRel
            envS = envF
            e = envF
        }
        let old: Double = eHist[(hp - L + 2 * M) % M]
        eHist[hp] = e
        sum += e - old
        sumAge += 1
        if sumAge >= 4096 {
            // Пересчёт суммы — без накопления ошибки.
            var s: Double = 0
            var k = 0
            while k < L {
                s += eHist[(hp - k + 2 * M) % M]
                k += 1
            }
            sum = s
            sumAge = 0
        }
        hpos = (hp + 1) % M
        n += 1
        return Swift.min(1, sum / Double(L))
    }
}

public final class MasterLimiter {
    static let taps = MasterTables.limTaps
    static let maxLookaheadMs: Double = 6
    static let autoFastMs: Double = 30
    static let autoSlowMs: Double = 400
    static let smoothMs: Double = 20
    static let bypassMs: Double = 10
    static let xfadeMs: Double = 20
    static let meterFrames = 256

    let sr: Double
    let phases: UnsafeMutablePointer<Double>
    let kSmooth: Double
    let wetStep: Double
    let xfStep: Double
    let kFast: Double
    let kSlow: Double
    var kRel: Double
    var relSig: Double = 150
    let maxL: Int
    let size: Int
    /// Задержанный сигнал после GAIN (dl, dr) и без него (xl, xr — для bypass).
    let dl: UnsafeMutablePointer<Float>
    let dr: UnsafeMutablePointer<Float>
    let xl: UnsafeMutablePointer<Float>
    let xr: UnsafeMutablePointer<Float>
    /// История true peak входа и выхода (L, R по 24 — двойной буфер).
    let hIn: UnsafeMutablePointer<Float>
    let hOut: UnsafeMutablePointer<Float>
    var posIn = 0
    var posOut = 0
    var w = 0
    var pkPrev: Double = 0
    var gainLin: Double = 1
    var ceil: Double = 0.8912509381337456
    var wet: Double = 1
    var L: Int
    var oldDelay = -1
    var xf: Double = 1
    let gc: LimiterGain
    var meterN = 0
    var mIn: Double = 0, mGr: Double = 1, mOut: Double = 0
    public private(set) var frameIn: Double = 0
    public private(set) var frameGr: Double = 0
    public private(set) var frameOut: Double = 0
    public private(set) var frames = 0

    public init(sampleRate: Double, tables: MasterTables = .shared) {
        sr = sampleRate
        phases = tables.limPhases
        kSmooth = exp(-1 / ((MasterLimiter.smoothMs / 1000) * sampleRate))
        wetStep = 1 / ((MasterLimiter.bypassMs / 1000) * sampleRate)
        xfStep = 1 / ((MasterLimiter.xfadeMs / 1000) * sampleRate)
        kFast = exp(-1 / ((MasterLimiter.autoFastMs / 1000) * sampleRate))
        kSlow = exp(-1 / ((MasterLimiter.autoSlowMs / 1000) * sampleRate))
        kRel = exp(-1 / ((150.0 / 1000) * sampleRate))
        ceil = pow(10, -1.0 / 20)
        maxL = Int(((MasterLimiter.maxLookaheadMs / 1000) * sampleRate).rounded(.up)) + LimiterGain.hold + 2
        size = maxL + MasterTables.limFirDelay + 8
        dl = UnsafeMutablePointer<Float>.allocate(capacity: size)
        dr = UnsafeMutablePointer<Float>.allocate(capacity: size)
        xl = UnsafeMutablePointer<Float>.allocate(capacity: size)
        xr = UnsafeMutablePointer<Float>.allocate(capacity: size)
        for p in [dl, dr, xl, xr] { p.initialize(repeating: 0, count: size) }
        hIn = UnsafeMutablePointer<Float>.allocate(capacity: 4 * MasterLimiter.taps)
        hIn.initialize(repeating: 0, count: 4 * MasterLimiter.taps)
        hOut = UnsafeMutablePointer<Float>.allocate(capacity: 4 * MasterLimiter.taps)
        hOut.initialize(repeating: 0, count: 4 * MasterLimiter.taps)
        L = MasterLimiter.look(3, sampleRate, maxL)
        gc = LimiterGain(maxL: maxL, L: L)
    }

    deinit {
        for p in [dl, dr, xl, xr, hIn, hOut] { p.deallocate() }
    }

    /// Окно lookahead в отсчётах (Math.round, как в вебе).
    static func look(_ ms: Double, _ sr: Double, _ maxL: Int) -> Int {
        let v = Int(((ms / 1000) * sr + 0.5).rounded(.down))
        return Swift.max(1, Swift.min(maxL - LimiterGain.hold - 1, v))
    }

    /// Задержка звука относительно детектора для окна L (рампа кончается ровно на пике).
    @inline(__always) func delayFor(_ L: Int) -> Int { return L + MasterTables.limFirDelay + LimiterGain.hold / 2 }

    /// True peak стереоотсчёта: история h (L — 0…23, R — 24…47), наибольший модуль из 4 фаз.
    @inline(__always)
    func truePeak(_ h: UnsafeMutablePointer<Float>, _ pos: inout Int, _ l: Double, _ r: Double) -> Double {
        let T = MasterLimiter.taps
        let p = pos
        let fl = Float(l), fr = Float(r)
        h[p] = fl
        h[p + T] = fl
        h[2 * T + p] = fr
        h[2 * T + p + T] = fr
        pos = p + 1 == T ? 0 : p + 1
        let base = p + T
        let ph = phases
        var m: Double = 0
        var q = 0
        while q < 4 {
            let f = ph + q * T
            var sl: Double = 0, sr: Double = 0
            var j = 0
            while j < T {
                let k = base - j
                sl += f[j] * Double(h[k])
                sr += f[j] * Double(h[2 * T + k])
                j += 1
            }
            let a: Double = Swift.max(abs(sl), abs(sr))
            if a > m { m = a }
            q += 1
        }
        return m
    }

    /// Блок n отсчётов (вход и выход могут совпадать). gain 0…24 dB, ceiling −24…0 dB, lookahead 0,5…6 мс,
    /// rel 10…1000 мс (auto — AUTO).
    public func process(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>, outL: UnsafeMutablePointer<Float>,
                        outR: UnsafeMutablePointer<Float>, frames n: Int, gain: Double, ceiling: Double,
                        lookahead: Double, rel: Double, auto: Bool, bypass: Bool) {
        if rel != relSig {
            relSig = rel
            kRel = rel <= 0 ? 0 : exp(-1 / ((rel / 1000) * sr))
        }
        let ks: Double = kSmooth
        let gainT: Double = pow(10, gain / 20)
        let ceilT: Double = pow(10, ceiling / 20)
        let wetT: Double = bypass ? 0 : 1
        let S = size
        let kRel = self.kRel, kFast = self.kFast, kSlow = self.kSlow
        // Новое окно lookahead — только после окончания прошлого кроссфейда.
        let Lt = MasterLimiter.look(lookahead, sr, maxL)
        if Lt != L && xf >= 1 {
            oldDelay = delayFor(L)
            xf = 0
            L = Lt
            gc.setWindow(Lt)
        }
        let dl = self.dl, dr = self.dr, xl = self.xl, xr = self.xr
        var i = 0
        while i < n {
            gainLin = gainT + (gainLin - gainT) * ks
            ceil = ceilT + (ceil - ceilT) * ks
            if wet < wetT { wet = Swift.min(wetT, wet + wetStep) } else if wet > wetT { wet = Swift.max(wetT, wet - wetStep) }
            let rawL = Double(inL[i]), rawR = Double(inR[i])
            let gl: Double = rawL * gainLin
            let gr: Double = rawR * gainLin
            let wi = w
            dl[wi] = Float(gl)
            dr[wi] = Float(gr)
            xl[wi] = Float(rawL)
            xr[wi] = Float(rawR)
            w = (wi + 1) % S
            // Детектор: true peak; межсэмпловый пик — на оба соседних отсчёта.
            let pk0: Double = truePeak(hIn, &posIn, gl, gr)
            let pk: Double = Swift.max(pk0, pkPrev)
            pkPrev = pk0
            if pk0 > mIn { mIn = pk0 }
            let c: Double = ceil
            let g: Double = gc.step(pk, c, auto, kRel, kFast, kSlow)
            if g < mGr { mGr = g }
            let r = (wi - delayFor(L) + S) % S
            var yl = Double(dl[r]), yr = Double(dr[r])
            var bl = Double(xl[r]), br = Double(xr[r])
            if xf < 1 {
                let ro = (wi - oldDelay + S) % S
                let a: Double = xf
                yl = yl * a + Double(dl[ro]) * (1 - a)
                yr = yr * a + Double(dr[ro]) * (1 - a)
                bl = bl * a + Double(xl[ro]) * (1 - a)
                br = br * a + Double(xr[ro]) * (1 - a)
                xf = Swift.min(1, xf + xfStep)
            }
            yl *= g
            yr *= g
            // Страховка: жёсткий клип на CEILING.
            if yl > c { yl = c } else if yl < -c { yl = -c }
            if yr > c { yr = c } else if yr < -c { yr = -c }
            let wt: Double = wet
            let ol: Double = yl * wt + bl * (1 - wt)
            let orr: Double = yr * wt + br * (1 - wt)
            let po: Double = truePeak(hOut, &posOut, ol, orr)
            if po > mOut { mOut = po }
            outL[i] = Float(ol)
            outR[i] = Float(orr)
            i += 1
        }
        meterN += n
        if meterN >= MasterLimiter.meterFrames {
            frameIn = mIn
            frameGr = wet > 0.5 ? -20 * log10(Swift.max(mGr, 1e-6)) : 0
            frameOut = mOut
            frames += 1
            meterN = 0
            mIn = 0
            mGr = 1
            mOut = 0
        }
    }
}
