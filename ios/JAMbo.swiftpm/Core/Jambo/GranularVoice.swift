import Foundation

// GRANULAR (26): облако зёрен из сэмпла дорожки (ТЗ «Texture и Granular»; эталон — веб-прототип). Зерно — отрезок
// сэмпла с окном Ханна (считается на лету поворотом вектора), своя высота (нота + разброс SPRAY до ±3 полутонов),
// позиция (POSITION ± 0,35·SPRAY) и панорама (±0,9·SPRAY); чтение — линейная интерполяция. Планировщик — с точностью
// до отсчёта, первое зерно через 3 мс; общее усиление 3,5 / √(плотность · длина), сглаживание 50 мс.
// Ручки 0…1: 1.1 POSITION, 1.2 SIZE, 1.3 DENSITY, 1.4 SPRAY. Монофоничен (слот 0), выход — стерео.
// Зерно держит указатели своего буфера: смена сэмпла не обрывает звучащие зёрна (буфер живёт, пока его держит
// снимок звука — не меньше AudioCore.keepAlive после замены, а зерно не длиннее 0,5 с).
// Стерео-сэмпл читается по каналам, панорама зерна — баланс; моно — равная мощность.

@_transparent private func gClamp(_ x: Double, _ a: Double, _ b: Double) -> Double {
    return x < a ? a : (x > b ? b : x)
}

@_transparent private func gXor(_ r0: Int) -> Int {
    var r = r0
    r ^= (r << 13) & 0xFFFF_FFFF
    r ^= r >> 17
    r ^= (r << 5) & 0xFFFF_FFFF
    return r
}

/// Сэмпл GRANULAR для колбэка — только указатели (SampleData держит снимок звука).
struct GrainSrc {
    var left: UnsafeMutablePointer<Float>? = nil
    var right: UnsafeMutablePointer<Float>? = nil
    var frames = 0
    var channels = 1
}

final class GranularVoice {
    private let sr: Double
    static let maxGrains = 160
    /// Нота, на которой зерно звучит исходной высотой (как у сэмплера, Params.sampleRoot).
    static let root = 48.0
    private var note = 48.0
    private var position = 0.12, size = 0.45, density = 0.55, spray = 0.2
    private var rnd = 1
    /// Сглаженное усиление облака (с множителем выхода).
    private var gain = 0.0
    private var fresh = true
    // Зёрна: позиция чтения и шаг (кадры сэмпла), кадров всего и прошло, шаг окна (cos, sin) и текущий поворот,
    // усиления каналов (моно: L, R; стерео: LL, RL, RR, LR), буфер.
    private let gPos: UnsafeMutablePointer<Double>
    private let gStep: UnsafeMutablePointer<Double>
    private let gLen: UnsafeMutablePointer<Int>
    private let gAt: UnsafeMutablePointer<Int>
    private let gWr: UnsafeMutablePointer<Double>
    private let gWi: UnsafeMutablePointer<Double>
    private let gCr: UnsafeMutablePointer<Double>
    private let gCi: UnsafeMutablePointer<Double>
    private let gG: UnsafeMutablePointer<Double>
    private let gSrc: UnsafeMutablePointer<GrainSrc>
    private(set) var grains = 0
    private var nextAt = 0.0
    private var spawning = false
    private let busL: UnsafeMutablePointer<Double>
    private let busR: UnsafeMutablePointer<Double>

    init(sampleRate: Double, seed: Int = 1) {
        sr = sampleRate
        rnd = (seed &* 2246822519 + 77) & 0xFFFF_FFFF
        if rnd == 0 { rnd = 1 }
        let n = GranularVoice.maxGrains
        gPos = .allocate(capacity: n)
        gPos.initialize(repeating: 0, count: n)
        gStep = .allocate(capacity: n)
        gStep.initialize(repeating: 0, count: n)
        gLen = .allocate(capacity: n)
        gLen.initialize(repeating: 0, count: n)
        gAt = .allocate(capacity: n)
        gAt.initialize(repeating: 0, count: n)
        gWr = .allocate(capacity: n)
        gWr.initialize(repeating: 1, count: n)
        gWi = .allocate(capacity: n)
        gWi.initialize(repeating: 0, count: n)
        gCr = .allocate(capacity: n)
        gCr.initialize(repeating: 1, count: n)
        gCi = .allocate(capacity: n)
        gCi.initialize(repeating: 0, count: n)
        gG = .allocate(capacity: n * 4)
        gG.initialize(repeating: 0, count: n * 4)
        gSrc = .allocate(capacity: n)
        gSrc.initialize(repeating: GrainSrc(), count: n)
        busL = .allocate(capacity: TextureVoice.maxChunk)
        busL.initialize(repeating: 0, count: TextureVoice.maxChunk)
        busR = .allocate(capacity: TextureVoice.maxChunk)
        busR.initialize(repeating: 0, count: TextureVoice.maxChunk)
    }

    deinit {
        for p in [gPos, gStep, gWr, gWi, gCr, gCi, gG, busL, busR] as [UnsafeMutablePointer<Double>] { p.deallocate() }
        gLen.deallocate()
        gAt.deallocate()
        gSrc.deallocate()
    }

    /// Равномерное −1…1.
    @inline(__always) private func r2() -> Double {
        rnd = gXor(rnd)
        return Double(rnd) / 2147483648 - 1
    }

    /// Ручки (0…1) и нота (MIDI): меняют только новые зёрна.
    @inline(__always) func set(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double) {
        note = n
        position = gClamp(q1, 0, 1)
        size = gClamp(q2, 0, 1)
        density = gClamp(q3, 0, 1)
        spray = gClamp(q4, 0, 1)
    }

    /// Нота: поток зёрен не шёл — первое зерно через 3 мс; уже идёт — продолжается.
    func trigger(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double) {
        set(note: n, q1, q2, q3, q4)
        if !spawning {
            nextAt = 0.003 * sr
            spawning = true
        }
    }

    /// Голос молчал: зёрен нет, усиление встаёт сразу.
    func silence() {
        grains = 0
        spawning = false
        fresh = true
    }

    /// Новое зерно из src через delay кадров.
    private func spawn(_ delay: Int, _ src: GrainSrc) {
        if grains >= GranularVoice.maxGrains { return }
        let total: Double = Double(src.frames) / sr
        let dur: Double = Swift.min(TexGran.grainSize(size), total * 0.9)
        let rate: Double = pow(2, (note - GranularVoice.root + r2() * spray * 3) / 12)
        var pos: Double = (position + r2() * spray * 0.35) * total
        pos = gClamp(pos, 0, Swift.max(0, total - dur * rate - 0.001))
        let pan: Double = gClamp(r2() * spray * 0.9, -1, 1)
        let n = Int((dur * sr).rounded())
        if n < 2 { return }
        let k = grains
        grains += 1
        gPos[k] = pos * sr
        gStep[k] = rate
        gLen[k] = n
        gAt[k] = -delay
        let w: Double = 2 * Double.pi / Double(n)
        gWr[k] = cos(w)
        gWi[k] = sin(w)
        gCr[k] = 1
        gCi[k] = 0
        let g = gG + k * 4
        if src.channels > 1 && src.right != nil {
            // Баланс (StereoPanner веба со стерео-входом).
            let x: Double = (pan <= 0 ? pan + 1 : pan) * Double.pi / 2
            g[0] = pan <= 0 ? 1 : cos(x)
            g[1] = pan <= 0 ? cos(x) : 0
            g[2] = pan <= 0 ? sin(x) : 1
            g[3] = pan <= 0 ? 0 : sin(x)
        } else {
            let x: Double = (pan + 1) / 2 * Double.pi / 2
            g[0] = cos(x)
            g[1] = sin(x)
            g[2] = 0
            g[3] = 0
        }
        gSrc[k] = src
    }

    /// Стерео-выход n кадров (n ≤ TextureVoice.maxChunk); window — кадров окна активности (как у TEXTURE).
    func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int, window: Int,
                src: GrainSrc) {
        let dens: Double = TexGran.grainRate(density)
        let target: Double = 3.5 / sqrt(Swift.max(1, dens * TexGran.grainSize(size))) * TextureMap.out
        let g0: Double = gain
        gain = fresh ? target : g0 + (target - g0) * (1 - exp(-Double(n) / (0.05 * sr)))
        fresh = false
        let bl = busL, br = busR
        bl.update(repeating: 0, count: n)
        br.update(repeating: 0, count: n)
        let hasSrc: Bool = src.left != nil && src.frames > 1
        if spawning {
            if !hasSrc {
                nextAt = Swift.max(0, nextAt - Double(n))
            } else {
                while nextAt < Double(n) {
                    let at = Int(nextAt < 0 ? 0 : nextAt)
                    if at >= window {
                        spawning = false
                        break
                    }
                    spawn(at, src)
                    nextAt += (1 / dens) * (1 + r2() * spray * 0.8) * sr
                }
                nextAt -= Double(n)
            }
            if window <= n { spawning = false }
        }
        var e = 0
        while e < grains {
            let s = gSrc[e]
            let len = gLen[e]
            var at = gAt[e]
            var pos = gPos[e]
            let step = gStep[e]
            let wr = gWr[e], wi = gWi[e]
            var cr = gCr[e], ci = gCi[e]
            let g = gG + e * 4
            let ga = g[0], gb = g[1], gc = g[2], gd = g[3]
            let lp = s.left!
            let last = s.frames - 1
            var i = 0
            if at < 0 {
                i = -at
                at = 0
            }
            if s.channels > 1, let rp = s.right {
                while i < n && at < len {
                    let w: Double = 0.5 - 0.5 * cr
                    let ip = Int(pos)
                    let f: Double = pos - Double(ip)
                    var a = 0.0, b = 0.0
                    if ip < last {
                        a = Double(lp[ip]) + (Double(lp[ip + 1]) - Double(lp[ip])) * f
                        b = Double(rp[ip]) + (Double(rp[ip + 1]) - Double(rp[ip])) * f
                    }
                    a *= w
                    b *= w
                    bl[i] += a * ga + b * gb
                    br[i] += b * gc + a * gd
                    let t: Double = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = t
                    pos += step
                    at += 1
                    i += 1
                }
            } else {
                while i < n && at < len {
                    let w: Double = 0.5 - 0.5 * cr
                    let ip = Int(pos)
                    let f: Double = pos - Double(ip)
                    var a = 0.0
                    if ip < last { a = Double(lp[ip]) + (Double(lp[ip + 1]) - Double(lp[ip])) * f }
                    a *= w
                    bl[i] += a * ga
                    br[i] += a * gb
                    let t: Double = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = t
                    pos += step
                    at += 1
                    i += 1
                }
            }
            if at >= len {
                grains -= 1
                if e != grains {
                    gPos[e] = gPos[grains]
                    gStep[e] = gStep[grains]
                    gLen[e] = gLen[grains]
                    gAt[e] = gAt[grains]
                    gWr[e] = gWr[grains]
                    gWi[e] = gWi[grains]
                    gCr[e] = gCr[grains]
                    gCi[e] = gCi[grains]
                    let h = gG + grains * 4
                    g[0] = h[0]
                    g[1] = h[1]
                    g[2] = h[2]
                    g[3] = h[3]
                    gSrc[e] = gSrc[grains]
                }
                continue
            }
            gAt[e] = at
            gPos[e] = pos
            gCr[e] = cr
            gCi[e] = ci
            e += 1
        }
        // Усиление облака — плавно по куску (первый кусок ноты — от нуля).
        let dg: Double = (gain - g0) / Double(n)
        var gg: Double = g0
        var j = 0
        while j < n {
            gg += dg
            outL[j] = Float(bl[j] * gg)
            outR[j] = Float(br[j] * gg)
            j += 1
        }
    }
}
