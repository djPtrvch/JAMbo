import Foundation

// TEXTURE (25): шум из случайных событий (ТЗ «Texture и Granular», вариант A; эталон — веб-прототип). Пуассоновский
// поток коротких вспышек белого шума (у каждой свой генератор и случайная панорама) + непрерывный шум на плотном краю;
// шина событий стерео идёт двумя путями: COLOR (ФНЧ → ФВЧ, Q −3 dB, компенсация уровня) и TONE (четыре полосовых
// на f0·1…4 с постоянным усилением 0 dB на пике), смешение — по TONE; MOTION — случайный дрейф цвета, плотности и строя
// (шаг 25 мс). Своей громкостной огибающей нет — огибающая, фильтр и Pan голоса стоят после движка.
// Ручки 0…1: 1.1 COLOR, 1.2 DENSITY, 1.3 TONE, 1.4 MOTION. Монофоничен (слот 0).
// Горячие циклы — без вызовов из других файлов, состояние — в локальных переменных (отладочная сборка Playgrounds).

@_transparent private func xClamp(_ x: Double, _ a: Double, _ b: Double) -> Double {
    return x < a ? a : (x > b ? b : x)
}

@_transparent private func xSmooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t: Double = xClamp((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)
}

@_transparent private func xLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// xorshift32 (состояние — Int 0…2³²−1).
@_transparent private func xXor(_ r0: Int) -> Int {
    var r = r0
    r ^= (r << 13) & 0xFFFF_FFFF
    r ^= r >> 17
    r ^= (r << 5) & 0xFFFF_FFFF
    return r
}

@_transparent private func xFlush(_ x: Double) -> Double { (x > 1e-20 || x < -1e-20) ? x : 0 }

/// Формулы ТЗ (отображения ручек) — для движка, подписей ручек и тестов.
enum TextureMap {
    static let base = 220.0
    static let wDark: [Double] = [1, 0.25, 0.08, 0.02]
    static let wBright: [Double] = [0.55, 0.85, 0.9, 0.8]
    static let maxEvents = 150
    /// Уровень выхода: Level 0,7 · 0,9 прототипа (его выход движка — до мастера 0,63 и компрессора; без этого
    /// множителя пики по умолчанию ≈ 1,7 и упираются в лимитер мастера JAMbo).
    static let out = 0.63

    /// Событий в секунду: 2 · 60^d (2…120).
    static func rate(_ d: Double) -> Double { return 2 * pow(60, d) }
    /// Длина события, с: 0,002 · 60^d (2…120 мс).
    static func length(_ d: Double) -> Double { return 0.002 * pow(60, d) }
    /// ФНЧ сухого пути, Гц: 250 · 72^s1 (не выше 0,45 · fs).
    static func lpHz(_ c: Double, _ sr: Double) -> Double {
        return Swift.min(250 * pow(72, xSmooth(0, 0.55, c)), sr * 0.45)
    }
    /// ФВЧ сухого пути, Гц: 30 · 200^s2.
    static func hpHz(_ c: Double) -> Double { return 30 * pow(200, xSmooth(0.55, 1, c)) }
    /// Добротность резонаторов: 2 + tone² · 98.
    static func q(_ tone: Double) -> Double { return 2 + tone * tone * 98 }
    /// Вес резонатора i по цвету.
    static func weight(_ i: Int, _ c: Double) -> Double { return xLerp(wDark[i], wBright[i], xSmooth(0, 1, c)) }
    /// Название цвета на ручке.
    static func colorName(_ c: Double) -> String {
        if c < 0.15 { return "brown" }
        if c < 0.35 { return "pink" }
        if c < 0.6 { return "white" }
        if c < 0.82 { return "light" }
        return "blue"
    }
}

final class TextureVoice {
    private let sr: Double
    static let maxChunk = 256
    private var note = 57.0
    // Ручки 0…1.
    private var color = 0.4, density = 0.5, tone = 0.3, motion = 0.3
    private var rnd = 1
    private var noiseR = 7
    // Сглаженные (≈20 мс) значения: частоты и Q фильтров, веса, усиления.
    private var sLp = 1000.0, sHp = 30.0, sMk = 1.0, sCont = 0.0, sDry = 1.0, sWet = 0.0, sQ = 10.0
    private let sF: UnsafeMutablePointer<Double>
    private let sW: UnsafeMutablePointer<Double>
    /// Коэффициенты 6 фильтров (ФНЧ, ФВЧ, 4 полосовых) по 5: b0, b1, b2, a1, a2; состояния — фильтр·4 (L z1 z2, R z1 z2).
    private let co: UnsafeMutablePointer<Double>
    private let zs: UnsafeMutablePointer<Double>
    private var fresh = true
    // События: огибающая, пик, кадров от начала (отрицательное — ещё не началось), всего кадров, множитель спада,
    // усиления L/R, генератор.
    private let eEnv: UnsafeMutablePointer<Double>
    private let eAmp: UnsafeMutablePointer<Double>
    private let ePos: UnsafeMutablePointer<Int>
    private let eLen: UnsafeMutablePointer<Int>
    private let eK: UnsafeMutablePointer<Double>
    private let eL: UnsafeMutablePointer<Double>
    private let eR: UnsafeMutablePointer<Double>
    private let eRnd: UnsafeMutablePointer<Int>
    /// Дробная позиция чтения шума и прошлый отсчёт: в прототипе вспышка читает буфер шума с дробного смещения —
    /// линейная интерполяция чуть заваливает верх (до −4 dB у 16 кГц).
    private let eFr: UnsafeMutablePointer<Double>
    private let ePrev: UnsafeMutablePointer<Double>
    private(set) var events = 0
    /// Кадров до следующего события; spawning — поток событий идёт (окно активности не закрылось).
    private var nextAt = 0.0
    private var spawning = false
    // MOTION: смещения и цели (цвет, плотность, строй 4), кадров до шага S&H, сглаживание, кадров до обновления (25 мс).
    private var mC = 0.0, mD = 0.0, mCT = 0.0, mDT = 0.0, mTc = 0.1
    private let mP: UnsafeMutablePointer<Double>
    private let mPT: UnsafeMutablePointer<Double>
    private var mHold = 0.0
    private var mTick = 0
    // Шина событий (стерео) на кусок.
    private let busL: UnsafeMutablePointer<Double>
    private let busR: UnsafeMutablePointer<Double>

    init(sampleRate: Double, seed: Int = 1) {
        sr = sampleRate
        rnd = (seed &* 2654435761) & 0xFFFF_FFFF
        if rnd == 0 { rnd = 1 }
        noiseR = xXor(rnd ^ 0x5bd1_e995)
        if noiseR == 0 { noiseR = 7 }
        sF = .allocate(capacity: 4)
        sF.initialize(repeating: 220, count: 4)
        sW = .allocate(capacity: 4)
        sW.initialize(repeating: 0, count: 4)
        co = .allocate(capacity: 30)
        co.initialize(repeating: 0, count: 30)
        zs = .allocate(capacity: 24)
        zs.initialize(repeating: 0, count: 24)
        let n = TextureMap.maxEvents
        eEnv = .allocate(capacity: n)
        eEnv.initialize(repeating: 0, count: n)
        eAmp = .allocate(capacity: n)
        eAmp.initialize(repeating: 0, count: n)
        ePos = .allocate(capacity: n)
        ePos.initialize(repeating: 0, count: n)
        eLen = .allocate(capacity: n)
        eLen.initialize(repeating: 0, count: n)
        eK = .allocate(capacity: n)
        eK.initialize(repeating: 0, count: n)
        eL = .allocate(capacity: n)
        eL.initialize(repeating: 0, count: n)
        eR = .allocate(capacity: n)
        eR.initialize(repeating: 0, count: n)
        eRnd = .allocate(capacity: n)
        eRnd.initialize(repeating: 1, count: n)
        eFr = .allocate(capacity: n)
        eFr.initialize(repeating: 0, count: n)
        ePrev = .allocate(capacity: n)
        ePrev.initialize(repeating: 0, count: n)
        mP = .allocate(capacity: 4)
        mP.initialize(repeating: 0, count: 4)
        mPT = .allocate(capacity: 4)
        mPT.initialize(repeating: 0, count: 4)
        busL = .allocate(capacity: TextureVoice.maxChunk)
        busL.initialize(repeating: 0, count: TextureVoice.maxChunk)
        busR = .allocate(capacity: TextureVoice.maxChunk)
        busR.initialize(repeating: 0, count: TextureVoice.maxChunk)
    }

    deinit {
        for p in [sF, sW, co, zs, eEnv, eAmp, eK, eL, eR, eFr, ePrev, mP, mPT, busL, busR] as [UnsafeMutablePointer<Double>] {
            p.deallocate()
        }
        ePos.deallocate()
        eLen.deallocate()
        eRnd.deallocate()
    }

    /// Равномерное 0…1.
    @inline(__always) private func u() -> Double {
        rnd = xXor(rnd)
        return Double(rnd) / 4294967296
    }

    /// Ручки (0…1) и нота (MIDI).
    @inline(__always) func set(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double) {
        note = n
        color = xClamp(q1, 0, 1)
        density = xClamp(q2, 0, 1)
        tone = xClamp(q3, 0, 1)
        motion = xClamp(q4, 0, 1)
    }

    /// Нота: поток событий не шёл — первое событие через 3 мс; уже идёт — продолжается (моно, без щелчка).
    func trigger(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double) {
        set(note: n, q1, q2, q3, q4)
        if !spawning {
            nextAt = 0.003 * sr
            spawning = true
        }
    }

    /// Голос молчал: событий, состояния фильтров и дрейфа нет, сглаженные значения встают сразу.
    func silence() {
        events = 0
        spawning = false
        fresh = true
        zs.update(repeating: 0, count: 24)
        mC = 0
        mD = 0
        mCT = 0
        mDT = 0
        mHold = 0
        mTick = 0
        for i in 0..<4 {
            mP[i] = 0
            mPT[i] = 0
        }
    }

    // MARK: — цели

    /// Шаг MOTION (раз в 25 мс): S&H-цели и сглаживание к ним.
    private func motionStep() {
        let mo = motion
        if mo > 0.001 {
            if mHold <= 0 {
                let iv: Double = xLerp(0.8, 0.09, mo) * (0.6 + 0.8 * u())
                mHold = iv * sr
                mCT = (u() * 2 - 1) * 0.4 * mo
                mDT = (u() * 2 - 1) * 0.5 * mo
                for i in 0..<4 { mPT[i] = u() * 2 - 1 }
                mTc = xLerp(iv * 0.6, 0.004, xSmooth(0.45, 1, mo))
            }
            let k: Double = 1 - exp(-0.025 / Swift.max(0.004, mTc))
            mC += (mCT - mC) * k
            mD += (mDT - mD) * k
            for i in 0..<4 { mP[i] += (mPT[i] - mP[i]) * k }
        } else {
            // Дрейфа нет — смещения возвращаются в ноль (сглаживание целей ≈ 50 мс).
            let k: Double = 1 - exp(-0.025 / 0.05)
            mC -= mC * k
            mD -= mD * k
            mCT = 0
            mDT = 0
            for i in 0..<4 {
                mP[i] -= mP[i] * k
                mPT[i] = 0
            }
        }
    }

    /// Коэффициенты фильтра f (0 — ФНЧ, 1 — ФВЧ: Q в dB, как в Web Audio; 2…5 — полосовой, Q линейно, 0 dB на пике).
    private func coef(_ f: Int, _ hz: Double, _ q: Double) {
        let w0: Double = 2 * Double.pi * Swift.min(hz, sr * 0.45) / sr
        let c: Double = cos(w0)
        let s: Double = sin(w0)
        let alpha: Double = f < 2 ? s / (2 * pow(10, q / 20)) : s / (2 * q)
        let a0: Double = 1 + alpha
        let p = co + f * 5
        if f == 0 {
            p[0] = (1 - c) / 2 / a0
            p[1] = (1 - c) / a0
            p[2] = p[0]
        } else if f == 1 {
            p[0] = (1 + c) / 2 / a0
            p[1] = -(1 + c) / a0
            p[2] = p[0]
        } else {
            p[0] = alpha / a0
            p[1] = 0
            p[2] = -alpha / a0
        }
        p[3] = -2 * c / a0
        p[4] = (1 - alpha) / a0
    }

    /// Цели по ручкам и MOTION; сглаживание (k — доля шага; 1 — сразу), коэффициенты фильтров.
    private func targets(_ k: Double) {
        let c: Double = xClamp(color + mC, 0, 1)
        let d: Double = xClamp(density + mD, 0, 1)
        let tn: Double = tone
        let lp: Double = TextureMap.lpHz(c, sr)
        let hp: Double = TextureMap.hpHz(c)
        let band: Double = Swift.max(300, lp - hp) / (sr * 0.5)
        let mk: Double = xClamp(0.2 / (0.577 * sqrt(band)), 0.5, 6) * (5.5 - 3.8 * d)
        let cont: Double = xSmooth(0.65, 1, d) * 0.9
        let q: Double = TextureMap.q(tn)
        let f0: Double = 440 * pow(2, (note - 69) / 12)
        let bright: Double = xSmooth(0, 1, c)
        var sum: Double = 0
        for i in 0..<4 {
            let w: Double = xLerp(TextureMap.wDark[i], TextureMap.wBright[i], bright)
            sum += w * w * Double(i + 1)
            sW[i] += (w - sW[i]) * k
            let cents: Double = mP[i] * motion * 25 / 1200
            let fr: Double = Swift.min(f0 * Double(i + 1) * pow(2, cents), sr * 0.45)
            sF[i] += (fr - sF[i]) * k
        }
        let boost: Double = 1 + 5 * pow(1 - d, 1.5)
        let half: Double = tn * Double.pi / 2
        let wet: Double = sin(half) * boost * Swift.min(60, 37.5 * sqrt(q / (f0 * sum)))
        sLp += (lp - sLp) * k
        sHp += (hp - sHp) * k
        sMk += (mk - sMk) * k
        sCont += (cont - sCont) * k
        sDry += (cos(half) - sDry) * k
        sWet += (wet - sWet) * k
        sQ += (q - sQ) * k
        coef(0, sLp, -3)
        coef(1, sHp, -3)
        for i in 0..<4 { coef(2 + i, sF[i], sQ) }
    }

    /// Новое событие через delay кадров (плотность — с учётом MOTION).
    private func spawn(_ delay: Int, _ rate: Double, _ len: Double) {
        if events >= TextureMap.maxEvents { return }
        let k = events
        events += 1
        let amp: Double = (0.4 + 0.6 * u()) / sqrt(Swift.max(1, rate * len))
        let pan: Double = (u() * 2 - 1) * 0.7
        let x: Double = (pan + 1) / 2 * Double.pi / 2
        eEnv[k] = 0
        eAmp[k] = amp
        ePos[k] = -delay
        eLen[k] = Int(((2 * len + 0.004) * sr).rounded())
        eK[k] = exp(-1 / (len / 3 * sr))
        eL[k] = cos(x)
        eR[k] = sin(x)
        var r: Int = xXor(rnd ^ 0x2545_f491)
        if r == 0 { r = 3 }
        eRnd[k] = r
        eFr[k] = u()
        ePrev[k] = 0
        rnd = xXor(rnd)
    }

    // MARK: — звук

    /// Стерео-выход n кадров (n ≤ maxChunk); window — кадров, в которых ещё рождаются события (окно активности:
    /// от ноты до attack + 1,7·decay после отпускания; Int.max — держится).
    func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int, window: Int) {
        // MOTION — каждые 25 мс.
        mTick -= n
        mHold -= Double(n)
        if mTick <= 0 {
            mTick += Int(0.025 * sr)
            motionStep()
        }
        let gOut: Double = TextureMap.out
        let prevMk: Double = sMk * sDry * gOut, prevWet: Double = sWet * gOut, prevCont: Double = sCont
        targets(fresh ? 1 : 1 - exp(-Double(n) / (0.02 * sr)))
        fresh = false
        let bl = busL, br = busR
        var j = 0
        // Непрерывный шум (на обоих каналах, плавно по куску).
        let c1: Double = sCont
        let dc: Double = (c1 - prevCont) / Double(n)
        var cg: Double = prevCont
        var nr: Int = noiseR
        if c1 > 1e-6 || prevCont > 1e-6 {
            while j < n {
                cg += dc
                nr = xXor(nr)
                let x: Double = (Double(nr) / 2147483648 - 1) * cg
                bl[j] = x
                br[j] = x
                j += 1
            }
        } else {
            bl.update(repeating: 0, count: n)
            br.update(repeating: 0, count: n)
        }
        noiseR = nr
        // События: поток Пуассона внутри окна активности.
        if spawning {
            let d: Double = xClamp(density + mD, 0, 1)
            let rate: Double = TextureMap.rate(d)
            let len: Double = TextureMap.length(d)
            while nextAt < Double(n) {
                let at = Int(nextAt < 0 ? 0 : nextAt)
                if at >= window {
                    spawning = false
                    break
                }
                spawn(at, rate, len)
                nextAt += Swift.max(0.0005, -log(1 - u()) / rate) * sr
            }
            nextAt -= Double(n)
            if window <= n { spawning = false }
        }
        let attN: Double = 0.0004 * sr
        var e = 0
        while e < events {
            var pos = ePos[e]
            let len = eLen[e]
            var env = eEnv[e]
            let amp = eAmp[e], k = eK[e], gl = eL[e], gr = eR[e]
            var r = eRnd[e]
            let fr = eFr[e], fr1: Double = 1 - fr
            var prev = ePrev[e]
            var i = 0
            if pos < 0 {
                i = -pos
                pos = 0
            }
            // Нарастание линейно за 0,4 мс до amp, затем экспоненциальный спад (τ = L/3); обрыв через 2L + 4 мс.
            var pd = Double(pos)
            while i < n && pos < len {
                if pd < attN {
                    env = amp * (pd + 1) / attN
                    if env > amp { env = amp }
                } else {
                    env *= k
                }
                r = xXor(r)
                let cur: Double = Double(r) / 2147483648 - 1
                let x: Double = (prev * fr1 + cur * fr) * env
                prev = cur
                bl[i] += x * gl
                br[i] += x * gr
                pos += 1
                pd += 1
                i += 1
            }
            if pos >= len {
                events -= 1
                if e != events {
                    eEnv[e] = eEnv[events]
                    eAmp[e] = eAmp[events]
                    ePos[e] = ePos[events]
                    eLen[e] = eLen[events]
                    eK[e] = eK[events]
                    eL[e] = eL[events]
                    eR[e] = eR[events]
                    eRnd[e] = eRnd[events]
                    eFr[e] = eFr[events]
                    ePrev[e] = ePrev[events]
                }
                continue
            }
            ePos[e] = pos
            eEnv[e] = env
            eRnd[e] = r
            ePrev[e] = prev
            e += 1
        }
        filter(outL, outR, n, prevMk, prevWet)
    }

    /// Сухой путь (ФНЧ → ФВЧ · компенсация · dry) и звенящий (4 полосовых · вес · wet) по каналам.
    private func filter(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int,
                        _ prevDry: Double, _ prevWet: Double) {
        let g: Double = TextureMap.out
        let dryT: Double = sMk * sDry * g
        let dd: Double = (dryT - prevDry) / Double(n)
        let dw: Double = (sWet * g - prevWet) / Double(n)
        let w0 = sW[0], w1 = sW[1], w2 = sW[2], w3 = sW[3]
        let c = co
        var ch = 0
        while ch < 2 {
            let bus: UnsafeMutablePointer<Double> = ch == 0 ? busL : busR
            let out: UnsafeMutablePointer<Float> = ch == 0 ? outL : outR
            let z = zs + ch * 2
            // Состояния фильтров канала: z[f·4 + ch·2], z[f·4 + ch·2 + 1].
            var lz1 = z[0], lz2 = z[1], hz1 = z[4], hz2 = z[5]
            var az1 = z[8], az2 = z[9], bz1 = z[12], bz2 = z[13]
            var cz1 = z[16], cz2 = z[17], ez1 = z[20], ez2 = z[21]
            var gd: Double = prevDry, gw: Double = prevWet
            var j = 0
            while j < n {
                let x: Double = bus[j]
                gd += dd
                gw += dw
                // Сухой: ФНЧ → ФВЧ (TDF II).
                let y0: Double = c[0] * x + lz1
                lz1 = c[1] * x - c[3] * y0 + lz2
                lz2 = c[2] * x - c[4] * y0
                let y1: Double = c[5] * y0 + hz1
                hz1 = c[6] * y0 - c[8] * y1 + hz2
                hz2 = c[7] * y0 - c[9] * y1
                // Звенящий: 4 полосовых (b1 = 0).
                let r0: Double = c[10] * x + az1
                az1 = -c[13] * r0 + az2
                az2 = c[12] * x - c[14] * r0
                let r1: Double = c[15] * x + bz1
                bz1 = -c[18] * r1 + bz2
                bz2 = c[17] * x - c[19] * r1
                let r2: Double = c[20] * x + cz1
                cz1 = -c[23] * r2 + cz2
                cz2 = c[22] * x - c[24] * r2
                let r3: Double = c[25] * x + ez1
                ez1 = -c[28] * r3 + ez2
                ez2 = c[27] * x - c[29] * r3
                let wet: Double = (r0 * w0 + r1 * w1 + r2 * w2 + r3 * w3) * gw
                out[j] = Float(y1 * gd + wet)
                j += 1
            }
            // NaN и денормалы: при сбое состояние — с нуля, кусок — тишина.
            let sum: Double = lz1 + lz2 + hz1 + hz2 + az1 + az2 + bz1 + bz2 + cz1 + cz2 + ez1 + ez2
            if !sum.isFinite {
                for f in 0..<6 {
                    z[f * 4] = 0
                    z[f * 4 + 1] = 0
                }
                out.update(repeating: 0, count: n)
            } else {
                z[0] = xFlush(lz1)
                z[1] = xFlush(lz2)
                z[4] = xFlush(hz1)
                z[5] = xFlush(hz2)
                z[8] = xFlush(az1)
                z[9] = xFlush(az2)
                z[12] = xFlush(bz1)
                z[13] = xFlush(bz2)
                z[16] = xFlush(cz1)
                z[17] = xFlush(cz2)
                z[20] = xFlush(ez1)
                z[21] = xFlush(ez2)
            }
            ch += 1
        }
    }
}
