import Foundation

// Компрессор мастера «glue» — перенос public/glue-worklet.js (решение пользователя S5a: без RANGE, HOLD, LINK и AUDIT —
// RANGE OFF, HOLD 0, LINK 100 %, как по умолчанию в вебе: один детектор по максимуму L и R, звук тот же).
// Стерео, нулевая задержка. Детектор: 60 % пика + 40 % RMS (10 мс, приведён к пику синуса) по сигналу после SC HPF
// (Баттерворт 2-го порядка; 20 Гц — обход). Gain computer в dB: колено KNEE, наклон 1 − 1/RATIO (1…20).
// GR сглаживается в dB: атака ATTACK, релиз RELEASE или AUTO (быстрый 60 мс и медленный 1,2 с).
// Выход = вход·(1 − MIX) + вход·GR·Makeup·MIX; BYPASS — кроссфейд 10 мс. Параметры сглаживаются за 20 мс.
// Индикация (S5c): за кадр 256 отсчётов — пик входа, уровень детектора (dB), GR (dB), пик выхода.

public final class MasterGlue {
    static let peakWeight: Double = 0.6
    static let rmsWeight: Double = 0.4
    static let rmsMs: Double = 10
    static let rmsCal: Double = 1.4142135623730951
    static let peakReleaseMs: Double = 10
    static let autoFastMs: Double = 60
    static let autoSlowMs: Double = 1200
    static let smoothMs: Double = 20
    static let bypassMs: Double = 10
    static let scHpfOff: Double = 20
    static let meterFrames = 256
    static let tiny: Double = 1e-25

    let sr: Double
    let kSmooth: Double
    let wetStep: Double
    let kPeak: Double
    let kRms: Double
    let kAutoFast: Double
    let kAutoSlow: Double
    var kAtt: Double = 0
    var kRel: Double = 0
    var attSig: Double = .nan
    var relSig: Double = .nan
    var thr: Double = -10
    var makeupDb: Double = 0
    var slope: Double = 0.5
    var knee: Double = 6
    var mix: Double = 1
    var schpf: Double = 90
    var wet: Double = 1
    var hpfSig: Double = .nan
    var hb0: Double = 0, hb1: Double = 0, hb2: Double = 0, ha1: Double = 0, ha2: Double = 0
    /// x1, x2, y1, y2 для L и R.
    var zl1: Double = 0, zl2: Double = 0, zl3: Double = 0, zl4: Double = 0
    var zr1: Double = 0, zr2: Double = 0, zr3: Double = 0, zr4: Double = 0
    // Детектор.
    var pk: Double = 0
    var ms: Double = 0
    var env: Double = 0
    var envSlow: Double = 0
    var ldb: Double = -240
    // Индикация: накопление кадра и последний кадр.
    var meterN = 0
    var mIn: Double = 0, mGr: Double = 0, mOut: Double = 0, mDet: Double = -240
    public private(set) var frameIn: Double = 0
    public private(set) var frameDet: Double = -240
    public private(set) var frameGr: Double = 0
    public private(set) var frameOut: Double = 0
    public private(set) var frames = 0

    public init(sampleRate: Double) {
        sr = sampleRate
        kSmooth = MasterGlue.coef(MasterGlue.smoothMs, sampleRate)
        wetStep = 1 / ((MasterGlue.bypassMs / 1000) * sampleRate)
        kPeak = MasterGlue.coef(MasterGlue.peakReleaseMs, sampleRate)
        kRms = MasterGlue.coef(MasterGlue.rmsMs, sampleRate)
        kAutoFast = MasterGlue.coef(MasterGlue.autoFastMs, sampleRate)
        kAutoSlow = MasterGlue.coef(MasterGlue.autoSlowMs, sampleRate)
        updateHpf(90)
    }

    static func coef(_ ms: Double, _ sr: Double) -> Double { return ms <= 0 ? 0 : exp(-1 / ((ms / 1000) * sr)) }

    /// SC HPF: биквад Баттерворта на частоте f.
    func updateHpf(_ f: Double) {
        if f == hpfSig { return }
        hpfSig = f
        let w: Double = (2 * Double.pi * f) / sr
        let cw: Double = cos(w)
        let al: Double = sin(w) / (2 * 0.7071067811865476)
        let a0: Double = 1 + al
        hb0 = (1 + cw) / 2 / a0
        hb1 = -(1 + cw) / a0
        hb2 = (1 + cw) / 2 / a0
        ha1 = (-2 * cw) / a0
        ha2 = (1 - al) / a0
    }

    /// Статическая кривая (окно компрессора, TRANSFER): GR в dB ≥ 0 на уровне детектора level — та же формула, что
    /// в process (staticGr веба без RANGE).
    public static func staticGr(_ level: Double, thr: Double, ratio: Double, knee: Double) -> Double {
        let slope: Double = 1 - 1 / Swift.max(1, Swift.min(20, ratio))
        let k: Double = Swift.max(0, Swift.min(24, knee))
        let over: Double = level - thr
        let half: Double = k / 2
        if over >= half { return over * slope }
        if over > -half { return (slope * (over + half) * (over + half)) / (2 * k) }
        return 0
    }

    /// Следующий пресет RATIO по тапу поля: 2 → 4 → 10 → 2 (выше 10 — 2; 3.3 — 4).
    public static func nextRatio(_ r: Double) -> Double {
        for x in [2.0, 4.0, 10.0] where x > r + 1e-3 { return x }
        return 2
    }

    /// Блок n отсчётов (вход и выход могут совпадать). thr −40…0 dB, att 0,1…100 мс, rel 20…2000 мс (auto — AUTO),
    /// makeup 0…18 dB, ratio 1…20, knee 0…24 dB, mix 0…100 %, schpf 20…500 Гц (20 — OFF).
    public func process(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>, outL: UnsafeMutablePointer<Float>,
                        outR: UnsafeMutablePointer<Float>, frames n: Int, thr thrT: Double, att: Double, rel: Double,
                        auto: Bool, makeup mkT: Double, ratio: Double, knee kIn: Double, mix mIn0: Double,
                        schpf hpIn: Double, bypass: Double) {
        if att != attSig { attSig = att; kAtt = MasterGlue.coef(att, sr) }
        if rel != relSig { relSig = rel; kRel = MasterGlue.coef(rel, sr) }
        let ks: Double = kSmooth
        let slopeT: Double = 1 - 1 / Swift.max(1, Swift.min(20, ratio))
        let kneeT: Double = Swift.max(0, Swift.min(24, kIn))
        let mixT: Double = Swift.max(0, Swift.min(1, mIn0 / 100))
        // bypass — доля глушения 0…1 (переход MIX ведёт её плавно; кнопка — 0 или 1).
        let wetT: Double = 1 - Swift.max(0, Swift.min(1, bypass))
        // SC HPF — по блокам (по логарифму частоты); на 20 Гц и ниже — обход.
        let hpT: Double = Swift.max(MasterGlue.scHpfOff, Swift.min(500, hpIn))
        let kb: Double = pow(ks, Double(n))
        schpf = exp(log(hpT) + (log(schpf) - log(hpT)) * kb)
        if abs(schpf - hpT) < 1e-3 { schpf = hpT }
        let hpOn: Bool = schpf > MasterGlue.scHpfOff + 1e-6
        if hpOn { updateHpf(schpf) }
        let b0 = hb0, b1 = hb1, b2 = hb2, a1 = ha1, a2 = ha2
        let tiny: Double = MasterGlue.tiny
        let kAtt = self.kAtt, kRel = self.kRel, kAF = kAutoFast, kAS = kAutoSlow, kPk = kPeak, kRm = kRms
        var pk = self.pk, ms = self.ms, env = self.env, envSlow = self.envSlow, ldb = self.ldb
        var thr = self.thr, makeupDb = self.makeupDb, slope = self.slope, knee = self.knee, mix = self.mix, wet = self.wet
        var zl1 = self.zl1, zl2 = self.zl2, zl3 = self.zl3, zl4 = self.zl4
        var zr1 = self.zr1, zr2 = self.zr2, zr3 = self.zr3, zr4 = self.zr4
        var mIn = self.mIn, mGr = self.mGr, mOut = self.mOut, mDet = self.mDet
        var i = 0
        while i < n {
            let xl = Double(inL[i])
            let xr = Double(inR[i])
            thr = thrT + (thr - thrT) * ks
            makeupDb = mkT + (makeupDb - mkT) * ks
            slope = slopeT + (slope - slopeT) * ks
            knee = kneeT + (knee - kneeT) * ks
            mix = mixT + (mix - mixT) * ks
            if wet < wetT { wet = Swift.min(wetT, wet + wetStep) } else if wet > wetT { wet = Swift.max(wetT, wet - wetStep) }
            var hl: Double = xl, hr: Double = xr
            if hpOn {
                hl = b0 * xl + b1 * zl1 + b2 * zl2 - a1 * zl3 - a2 * zl4 + tiny
                zl2 = zl1; zl1 = xl; zl4 = zl3; zl3 = hl
                hr = b0 * xr + b1 * zr1 + b2 * zr2 - a1 * zr3 - a2 * zr4 + tiny
                zr2 = zr1; zr1 = xr; zr4 = zr3; zr3 = hr
            }
            let al: Double = abs(hl), ar: Double = abs(hr)
            let a: Double = al > ar ? al : ar
            // Детектор: пик + RMS → уровень (dB) → цель GR → сглаживание.
            pk = a > pk ? a : pk * kPk + tiny
            ms = a * a + (ms - a * a) * kRm + tiny
            let level: Double = MasterGlue.peakWeight * pk + MasterGlue.rmsWeight * sqrt(ms) * MasterGlue.rmsCal
            ldb = 20 * log10(level + 1e-12)
            let over: Double = ldb - thr
            let half: Double = knee / 2
            var target: Double = 0
            if over >= half { target = over * slope } else if over > -half {
                target = (slope * (over + half) * (over + half)) / (2 * knee)
            }
            if target > env { env = target + (env - target) * kAtt } else if auto {
                env = target + (env - target) * kAF
            } else {
                env = target + (env - target) * kRel
            }
            envSlow = auto ? target + (envSlow - target) * kAS : 0
            let gr: Double = Swift.max(env, envSlow)
            let g: Double = pow(10, (makeupDb - gr) / 20)
            let k: Double = 1 - mix + g * mix
            let f: Double = wet * k + (1 - wet)
            let yl: Double = xl * f, yr: Double = xr * f
            outL[i] = Float(yl)
            outR[i] = Float(yr)
            let ao: Double = Swift.max(abs(yl), abs(yr))
            if ao > mOut { mOut = ao }
            let ai: Double = Swift.max(abs(xl), abs(xr))
            if ai > mIn { mIn = ai }
            if gr * wet > mGr { mGr = gr * wet }
            if ldb > mDet { mDet = ldb }
            i += 1
        }
        self.pk = pk; self.ms = ms; self.env = env; self.envSlow = envSlow; self.ldb = ldb
        self.thr = thr; self.makeupDb = makeupDb; self.slope = slope; self.knee = knee; self.mix = mix; self.wet = wet
        self.zl1 = zl1; self.zl2 = zl2; self.zl3 = zl3; self.zl4 = zl4
        self.zr1 = zr1; self.zr2 = zr2; self.zr3 = zr3; self.zr4 = zr4
        meterN += n
        if meterN >= MasterGlue.meterFrames {
            frameIn = mIn; frameDet = mDet; frameGr = mGr; frameOut = mOut
            frames += 1
            meterN = 0
            mIn = 0; mGr = 0; mOut = 0; mDet = -240
        }
        self.mIn = mIn; self.mGr = mGr; self.mOut = mOut; self.mDet = mDet
    }
}
