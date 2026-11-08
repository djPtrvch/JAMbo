import Foundation

// TEXTURE (25) по ТЗ docs/texture-engine.md (8.11): непрерывный стереошум (подложка: общий источник C и свои L, R,
// ширина WIDTH = 0,7, bed 0,9) и поверх — треск Grit (пуассоновский поток коротких шумовых щелчков со случайной
// панорамой). Шина идёт двумя путями: Color (ФНЧ → ФВЧ, Q −3 dB, выравнивание громкости) и Tone (четыре полосовых
// на f0·ra[i], Metal сдвигает ra от 1, 2, 3, 4 к 1, 2.76, 5.40, 8.93), смешение — по Tone. Своей модуляции, ширины
// и пауз нет; огибающая, фильтр и Pan голоса стоят после движка. Ручки 0…1: 1.1 Color, 1.2 Grit, 1.3 Tone,
// 1.4 Metal. Монофоничен (слот 0); новая нота не перезапускает шум.
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

/// Формулы ТЗ (отображения ручек) — для движка, подписей ручек, иконки и тестов.
enum TextureMap {
    static let wDark: [Double] = [1, 0.25, 0.08, 0.02]
    static let wBright: [Double] = [0.55, 0.85, 0.9, 0.8]
    static let ratios: [Double] = [1, 2, 3, 4]
    static let ratiosMetal: [Double] = [1, 2.76, 5.40, 8.93]
    static let maxEvents = 150
    /// Ширина подложки и панорамы щелчков (зашита).
    static let width = 0.7
    static let bed = 0.9
    /// Уровень выхода: Level 0,7 · 0,9 прототипа (как прежде; выход прототипа — до мастера и компрессора).
    static let out = 0.63

    /// Щелчков Grit в секунду: 5 · 30^g (5…150).
    static func rate(_ g: Double) -> Double { return 5 * pow(30, g) }
    /// Длина щелчка, с: max(3 мс, 12 мс · 0,25^g).
    static func length(_ g: Double) -> Double { return Swift.max(0.003, 0.012 * pow(0.25, g)) }
    /// Усиление щелчков: 2,2 · smooth(0,04; 0,6; g) (у нуля щелчков нет).
    static func gain(_ g: Double) -> Double { return 2.2 * xSmooth(0.04, 0.6, g) }
    /// ФНЧ сухого пути, Гц: 250 · 72^smooth(0; 0,55; c) (не выше 0,45 · fs).
    static func lpHz(_ c: Double, _ sr: Double) -> Double {
        return Swift.min(250 * pow(72, xSmooth(0, 0.55, c)), sr * 0.45)
    }
    /// ФВЧ сухого пути, Гц: 30 · 200^smooth(0,55; 1; c).
    static func hpHz(_ c: Double) -> Double { return 30 * pow(200, xSmooth(0.55, 1, c)) }
    /// Добротность резонаторов: 2 + tone² · 98.
    static func q(_ tone: Double) -> Double { return 2 + tone * tone * 98 }
    /// Вес резонатора i по цвету: lerp(тёмный, светлый, c).
    static func weight(_ i: Int, _ c: Double) -> Double { return xLerp(wDark[i], wBright[i], c) }
    /// Отношение частоты резонатора i к ноте по Metal.
    static func ratio(_ i: Int, _ m: Double) -> Double { return xLerp(ratios[i], ratiosMetal[i], m) }
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
    private var color = 0.4, grit = 0.3, tone = 0.3, metal = 0.0
    private var rnd = 1
    /// Генераторы подложки: общий C и свои L, R (некоррелированные).
    private var nC = 7, nL = 11, nR = 13
    // Сглаженные (30 мс) значения: частоты и Q фильтров, веса, усиления.
    private var sLp = 1000.0, sHp = 30.0, sMk = 1.0, sDry = 1.0, sWet = 0.0, sQ = 10.0
    private let sF: UnsafeMutablePointer<Double>
    private let sW: UnsafeMutablePointer<Double>
    /// Коэффициенты 6 фильтров (ФНЧ, ФВЧ, 4 полосовых) по 5: b0, b1, b2, a1, a2; состояния — фильтр·4 (L z1 z2, R z1 z2).
    private let co: UnsafeMutablePointer<Double>
    private let zs: UnsafeMutablePointer<Double>
    private var fresh = true
    // Щелчки: огибающая, пик, кадров от начала (отрицательное — ещё не начался), всего кадров, множитель спада,
    // усиления L/R, генератор.
    private let eEnv: UnsafeMutablePointer<Double>
    private let eAmp: UnsafeMutablePointer<Double>
    private let ePos: UnsafeMutablePointer<Int>
    private let eLen: UnsafeMutablePointer<Int>
    private let eK: UnsafeMutablePointer<Double>
    private let eL: UnsafeMutablePointer<Double>
    private let eR: UnsafeMutablePointer<Double>
    private let eRnd: UnsafeMutablePointer<Int>
    private(set) var events = 0
    /// Кадров до следующего щелчка; spawning — поток идёт (окно активности не закрылось).
    private var nextAt = 0.0
    private var spawning = false
    // Шина (стерео) на кусок.
    private let busL: UnsafeMutablePointer<Double>
    private let busR: UnsafeMutablePointer<Double>

    init(sampleRate: Double, seed: Int = 1) {
        sr = sampleRate
        rnd = (seed &* 2654435761) & 0xFFFF_FFFF
        if rnd == 0 { rnd = 1 }
        nC = xXor(rnd ^ 0x5bd1_e995) | 1
        nL = xXor(nC ^ 0x2545_f491) | 1
        nR = xXor(nL ^ 0x68e3_1da4) | 1
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
        busL = .allocate(capacity: TextureVoice.maxChunk)
        busL.initialize(repeating: 0, count: TextureVoice.maxChunk)
        busR = .allocate(capacity: TextureVoice.maxChunk)
        busR.initialize(repeating: 0, count: TextureVoice.maxChunk)
    }

    deinit {
        for p in [sF, sW, co, zs, eEnv, eAmp, eK, eL, eR, busL, busR] as [UnsafeMutablePointer<Double>] {
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
        grit = xClamp(q2, 0, 1)
        tone = xClamp(q3, 0, 1)
        metal = xClamp(q4, 0, 1)
    }

    /// Нота: поток щелчков не шёл — первый через 3 мс; уже идёт — продолжается (моно, шум не перезапускается).
    func trigger(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double) {
        set(note: n, q1, q2, q3, q4)
        if !spawning {
            nextAt = 0.003 * sr
            spawning = true
        }
    }

    /// Голос молчал: щелчков и состояния фильтров нет, сглаженные значения встают сразу.
    func silence() {
        events = 0
        spawning = false
        fresh = true
        zs.update(repeating: 0, count: 24)
    }

    // MARK: — цели

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

    /// Цели по ручкам; сглаживание (k — доля шага; 1 — сразу), коэффициенты фильтров.
    private func targets(_ k: Double) {
        let c: Double = color, g: Double = grit, tn: Double = tone, m: Double = metal
        let lp: Double = TextureMap.lpHz(c, sr)
        let hp: Double = TextureMap.hpHz(c)
        let band: Double = Swift.max(300, lp - hp) / (sr * 0.5)
        let mk: Double = xClamp(0.2 / (0.577 * sqrt(band)), 0.5, 6) * (1 - 0.15 * xSmooth(0.2, 1, g))
        let q: Double = TextureMap.q(tn)
        let f0: Double = 440 * pow(2, (note - 69) / 12)
        var sum: Double = 0
        for i in 0..<4 {
            let w: Double = TextureMap.weight(i, c)
            let ra: Double = TextureMap.ratio(i, m)
            sum += w * w * ra
            sW[i] += (w - sW[i]) * k
            let fr: Double = Swift.min(f0 * ra, sr * 0.45)
            sF[i] += (fr - sF[i]) * k
        }
        let half: Double = tn * Double.pi / 2
        let wet: Double = sin(half) * Swift.min(60, 37.5 * sqrt(q / (f0 * sum)))
        sLp += (lp - sLp) * k
        sHp += (hp - sHp) * k
        sMk += (mk - sMk) * k
        sDry += (cos(half) - sDry) * k
        sWet += (wet - sWet) * k
        sQ += (q - sQ) * k
        coef(0, sLp, -3)
        coef(1, sHp, -3)
        for i in 0..<4 { coef(2 + i, sF[i], sQ) }
    }

    /// Новый щелчок через delay кадров.
    private func spawn(_ delay: Int, _ rate: Double, _ len: Double, _ gain: Double) {
        if events >= TextureMap.maxEvents { return }
        let k = events
        events += 1
        let amp: Double = (0.5 + 0.5 * u()) * gain / sqrt(Swift.max(1, rate * len))
        let pan: Double = (u() * 2 - 1) * 0.7 * TextureMap.width
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
        rnd = xXor(rnd)
    }

    // MARK: — звук

    /// Стерео-выход n кадров (n ≤ maxChunk); window — кадров, в которых ещё рождаются щелчки (окно активности:
    /// от ноты до attack + 1,7·decay после отпускания; Int.max — держится). Подложка звучит всё время голоса.
    func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int, window: Int) {
        let gOut: Double = TextureMap.out
        let prevMk: Double = sMk * sDry * gOut, prevWet: Double = sWet * gOut
        targets(fresh ? 1 : 1 - exp(-Double(n) / (0.03 * sr)))
        fresh = false
        let bl = busL, br = busR
        // Подложка: L = bed·(gc·C + gl·L), R = bed·(gc·C + gr·R).
        let wa: Double = TextureMap.width * Double.pi / 2
        let gc: Double = TextureMap.bed * cos(wa), gs: Double = TextureMap.bed * sin(wa)
        var c0: Int = nC, l0: Int = nL, r0: Int = nR
        var j = 0
        while j < n {
            c0 = xXor(c0)
            l0 = xXor(l0)
            r0 = xXor(r0)
            let c: Double = (Double(c0) / 2147483648 - 1) * gc
            bl[j] = c + (Double(l0) / 2147483648 - 1) * gs
            br[j] = c + (Double(r0) / 2147483648 - 1) * gs
            j += 1
        }
        nC = c0
        nL = l0
        nR = r0
        // Щелчки Grit: поток Пуассона внутри окна активности.
        if spawning {
            let g: Double = grit
            let gain: Double = TextureMap.gain(g)
            let rate: Double = TextureMap.rate(g)
            let len: Double = TextureMap.length(g)
            while nextAt < Double(n) {
                let at = Int(nextAt < 0 ? 0 : nextAt)
                if at >= window {
                    spawning = false
                    break
                }
                if gain > 0 { spawn(at, rate, len, gain) }
                nextAt += Swift.max(0.0005, -log(1 - u()) / rate) * sr
            }
            nextAt -= Double(n)
            if window <= n { spawning = false }
        }
        let attN: Double = 0.0015 * sr
        var e = 0
        while e < events {
            var pos = ePos[e]
            let len = eLen[e]
            var env = eEnv[e]
            let amp = eAmp[e], k = eK[e], gl = eL[e], gr = eR[e]
            var r = eRnd[e]
            var i = 0
            if pos < 0 {
                i = -pos
                pos = 0
            }
            // Нарастание линейно за 1,5 мс до amp, затем экспоненциальный спад (τ = len/3); обрыв через 2·len + 4 мс.
            var pd = Double(pos)
            while i < n && pos < len {
                if pd < attN {
                    env = amp * (pd + 1) / attN
                    if env > amp { env = amp }
                } else {
                    env *= k
                }
                r = xXor(r)
                let x: Double = (Double(r) / 2147483648 - 1) * env
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
                }
                continue
            }
            ePos[e] = pos
            eEnv[e] = env
            eRnd[e] = r
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
