import Foundation

// GRANULAR (26): облако зёрен из сэмпла дорожки (ТЗ «Granular»; эталон — docs/prototype/texture-granular.html, вкладка
// Granular: spawnGrain, granularTick, grainPlan). Полифоничен: голос на слот (у каждой ноты своя шина зёрен), дрейф
// позиции, счёт звучащих нот и лимит зёрен — общие на дорожку (GrainTrack).
// Курсор head идёт за POSITION с постоянной 150 мс; зёрна стартуют по ровной сетке (интервал dur / eff, eff — зёрен
// одновременно), SPRAY квадратично добавляет разброс позиции, высоты (центы), панорамы и (выше 40 %) времени.
// Известен период источника Ts (GrainSrc.period) — позиция зерна кратна Ts, интервал — целое число периодов выхода
// ноты, усиление — по амплитуде (синфазные зёрна). Окно — Ханн (eff ≥ 2; поворотом вектора — точный косинус) или
// Гаусс σ = 0,2 (таблица 128 точек с линейной интерполяцией, как setValueCurveAtTime прототипа); чтение сэмпла —
// линейная интерполяция. Быстрый путь (Ханн, чтение кусок целиком внутри сэмпла) — без проверок на отсчёт.
// Моменты зёрен — с дробной долей отсчёта (чтение и окно сдвигаются на неё). Усиление шины — с постоянной 80 мс.
// Ручки 0…1: 1.1 POSITION, 1.2 SIZE, 1.3 DENSITY, 1.4 SPRAY — SIZE, DENSITY и SPRAY действуют на новые зёрна.
// SIZE и DENSITY для новых зёрен идут за ручкой с постоянной 150 мс (отличие от прототипа: резкий скачок SIZE с
// коротких зёрен на длинные давал провал уровня почти до тишины на ~50 мс — короткие гаснут, длинные нарастают окном).
// Усиление растёт не быстрее, чем доигрывают звучащие зёрна (постоянная — длина самого длинного, не меньше
// 80 мс; отличие от прототипа: SIZE с длинных на короткие давал выброс уровня ×2), спадает — с постоянной 80 мс.
// Зерно держит указатели своего буфера: смена сэмпла не обрывает звучащие зёрна (буфер живёт, пока его держит
// снимок звука — не меньше AudioCore.keepAlive после замены, а зерно не длиннее 0,8 с).
// Стерео-сэмпл читается по каналам, панорама зерна — баланс; моно — равная мощность. В колбэке памяти не выделяет.

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

/// Сэмпл GRANULAR для колбэка — только указатели (SampleData держит снимок звука); period — период источника, с
/// (SampleData.period; 0 — неизвестен, синхронизации по фазе нет).
struct GrainSrc {
    var left: UnsafeMutablePointer<Float>? = nil
    var right: UnsafeMutablePointer<Float>? = nil
    var frames = 0
    var channels = 1
    var period = 0.0
}

/// Общее на дорожку GRANULAR: дрейф позиции, звучащие ноты, зёрна (лимит), последний курсор.
struct GrainTrack {
    var rnd = 1
    var dr = 0.0
    var drT = 0.0
    /// Секунд до новой цели дрейфа.
    var drHold = 0.0
    /// Нот, у которых идёт окно запуска (N; считается в начале блока).
    var notes = 0
    /// Зёрен звучит на дорожке (лимит GranularVoice.maxGrains).
    var grains = 0
    /// Курсор последней звучащей ноты: новая нота при звучащих продолжает его.
    var head = 0.0

    @inline(__always) mutating func r2() -> Double {
        rnd = gXor(rnd)
        return Double(rnd) / 2147483648 - 1
    }

    /// Дрейф за dt секунд (тик прототипа 25 мс: dr += (цель − dr) · 0,012; новая цель каждые 1,5–4,5 с).
    mutating func advance(_ dt: Double) {
        drHold -= dt
        if drHold <= 0 {
            drT = r2()
            drHold += 1.5 + (r2() + 1) * 1.5
            if drHold <= 0 { drHold = 1.5 }
        }
        dr += (drT - dr) * (1 - pow(1 - 0.012, dt / 0.025))
    }
}

final class GranularVoice {
    private let sr: Double
    /// Зёрен на дорожку (и пул голоса) — не больше.
    static let maxGrains = 240
    /// Нота, на которой зерно звучит исходной высотой (как у сэмплера, Params.sampleRoot).
    static let root = 48.0
    /// Точек окна (таблица прототипа) и сами окна: Ханн и Гаусс σ = 0,2 (+ точка за краем для интерполяции).
    static let winPoints = 128
    private static let hann: UnsafeMutablePointer<Double> = {
        let n = GranularVoice.winPoints
        let p = UnsafeMutablePointer<Double>.allocate(capacity: n + 1)
        for i in 0..<n { p[i] = 0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n - 1))) }
        p[n] = 0
        return p
    }()
    private static let gauss: UnsafeMutablePointer<Double> = {
        let n = GranularVoice.winPoints
        let p = UnsafeMutablePointer<Double>.allocate(capacity: n + 1)
        let sg = 0.2, g0 = exp(-0.5 * pow(0.5 / sg, 2))
        for i in 0..<n {
            let x = Double(i) / Double(n - 1)
            p[i] = (exp(-0.5 * pow((x - 0.5) / sg, 2)) - g0) / (1 - g0)
        }
        p[n] = 0
        return p
    }()
    /// Окно w(x), x = 0…1 — по таблице (тесты).
    static func window(_ x: Double, gauss g: Bool) -> Double {
        let t = g ? gauss : hann
        let ph = gClamp(x, 0, 1) * Double(winPoints - 1)
        let i = Int(ph)
        return t[i] + (t[i + 1] - t[i]) * (ph - Double(i))
    }

    private let track: UnsafeMutablePointer<GrainTrack>
    private var note = 48.0
    private var position = 0.08, size = 0.62, density = 0.6, spray = 0.25
    /// SIZE и DENSITY для новых зёрен (сглаженные, 150 мс).
    private var sizeS = 0.62, densS = 0.6
    private var rnd = 1
    /// Курсор (доля сэмпла).
    private(set) var head = 0.08
    /// Сглаженное усиление шины ноты (с множителем выхода).
    private var gain = 0.0
    private var fresh = true
    // Зёрна: позиция чтения и шаг (кадры сэмпла), фаза окна и её шаг (точки таблицы), окно (1 — Гаусс),
    // задержка до первого отсчёта, усиления каналов (моно: L, R; стерео: LL, RL, RR, LR), буфер.
    private let gPos: UnsafeMutablePointer<Double>
    private let gStep: UnsafeMutablePointer<Double>
    private let gPh: UnsafeMutablePointer<Double>
    private let gPhStep: UnsafeMutablePointer<Double>
    private let gGauss: UnsafeMutablePointer<UInt8>
    /// Ханн поворотом: текущий (cos, sin) угла 2π·x и шаг поворота.
    private let gCr: UnsafeMutablePointer<Double>
    private let gCi: UnsafeMutablePointer<Double>
    private let gWr: UnsafeMutablePointer<Double>
    private let gWi: UnsafeMutablePointer<Double>
    private let gAt: UnsafeMutablePointer<Int>
    private let gG: UnsafeMutablePointer<Double>
    private let gSrc: UnsafeMutablePointer<GrainSrc>
    private(set) var grains = 0
    /// Кадров в самом длинном звучащем зерне (прошлый кусок).
    private var longest = 0.0
    /// Время следующего зерна, кадры от начала текущего куска (дробное).
    private var nextAt = 0.0
    private(set) var spawning = false
    private let busL: UnsafeMutablePointer<Double>
    private let busR: UnsafeMutablePointer<Double>
    /// Кадров от ноты (момент зерна для onSpawn); onSpawn — запуск зерна (тесты: момент, позиция, высота, панорама;
    /// в приложении nil).
    private var clock = 0.0
    var onSpawn: ((Double, Double, Double, Double) -> Void)? = nil

    init(sampleRate: Double, seed: Int = 1, track: UnsafeMutablePointer<GrainTrack>? = nil) {
        sr = sampleRate
        rnd = (seed &* 2246822519 + 77) & 0xFFFF_FFFF
        if rnd == 0 { rnd = 1 }
        if let t = track {
            self.track = t
            ownsTrack = false
        } else {
            self.track = .allocate(capacity: 1)
            self.track.initialize(to: GrainTrack(rnd: (seed &* 40503 + 11) & 0xFFFF_FFFF | 1))
            ownsTrack = true
        }
        let n = GranularVoice.maxGrains
        gPos = .allocate(capacity: n)
        gPos.initialize(repeating: 0, count: n)
        gStep = .allocate(capacity: n)
        gStep.initialize(repeating: 0, count: n)
        gPh = .allocate(capacity: n)
        gPh.initialize(repeating: 0, count: n)
        gPhStep = .allocate(capacity: n)
        gPhStep.initialize(repeating: 0, count: n)
        gCr = .allocate(capacity: n)
        gCr.initialize(repeating: 1, count: n)
        gCi = .allocate(capacity: n)
        gCi.initialize(repeating: 0, count: n)
        gWr = .allocate(capacity: n)
        gWr.initialize(repeating: 1, count: n)
        gWi = .allocate(capacity: n)
        gWi.initialize(repeating: 0, count: n)
        gGauss = .allocate(capacity: n)
        gGauss.initialize(repeating: 0, count: n)
        gAt = .allocate(capacity: n)
        gAt.initialize(repeating: 0, count: n)
        gG = .allocate(capacity: n * 4)
        gG.initialize(repeating: 0, count: n * 4)
        gSrc = .allocate(capacity: n)
        gSrc.initialize(repeating: GrainSrc(), count: n)
        busL = .allocate(capacity: TextureVoice.maxChunk)
        busL.initialize(repeating: 0, count: TextureVoice.maxChunk)
        busR = .allocate(capacity: TextureVoice.maxChunk)
        busR.initialize(repeating: 0, count: TextureVoice.maxChunk)
        _ = GranularVoice.hann
        _ = GranularVoice.gauss
    }

    private let ownsTrack: Bool

    deinit {
        for p in [gPos, gStep, gPh, gPhStep, gCr, gCi, gWr, gWi, gG, busL, busR] as [UnsafeMutablePointer<Double>] { p.deallocate() }
        gGauss.deallocate()
        gAt.deallocate()
        gSrc.deallocate()
        if ownsTrack { track.deallocate() }
    }

    /// Равномерное −1…1.
    @inline(__always) private func r2() -> Double {
        rnd = gXor(rnd)
        return Double(rnd) / 2147483648 - 1
    }

    /// Ручки (0…1) и нота (MIDI): SIZE, DENSITY и SPRAY — для новых зёрен, POSITION — через курсор.
    @inline(__always) func set(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double) {
        note = n
        position = gClamp(q1, 0, 1)
        size = gClamp(q2, 0, 1)
        density = gClamp(q3, 0, 1)
        spray = gClamp(q4, 0, 1)
    }

    /// Нота: поток зёрен не шёл — первое зерно через 3 мс; уже идёт — продолжается. Курсор — с курсора звучащих нот
    /// дорожки (иначе сразу на POSITION).
    func trigger(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double) {
        set(note: n, q1, q2, q3, q4)
        if !spawning {
            head = track.pointee.notes > 0 ? track.pointee.head : position
            sizeS = size
            densS = density
            nextAt = 0.003 * sr
            clock = 0
            spawning = true
        }
    }

    /// Голос молчал: зёрен нет, усиление встаёт сразу.
    func silence() {
        track.pointee.grains -= grains
        if track.pointee.grains < 0 { track.pointee.grains = 0 }
        grains = 0
        spawning = false
        fresh = true
        gain = 0
    }

    /// Новое зерно из src: start — момент, кадры от начала куска (дробный, ≥ 0); g — Гаусс.
    private func spawn(_ start: Double, _ src: GrainSrc, dur: Double, gauss g: Bool) {
        if grains >= GranularVoice.maxGrains || track.pointee.grains >= GranularVoice.maxGrains { return }
        let len: Double = Double(src.frames) / sr
        let sp = spray
        let cents: Double = r2() * TexGran.centsSpread(sp)
        let rate: Double = pow(2, (note - GranularVoice.root) / 12 + cents / 1200)
        let tr = track.pointee
        var pos: Double = (head + tr.dr * 0.03 * (0.3 + sp) + r2() * TexGran.posSpread(sp)) * len
        let ts = src.period
        if ts > 0 { pos = (pos / ts).rounded() * ts }
        pos = gClamp(pos, 0, Swift.max(0, len - dur * rate - 0.001))
        let pan: Double = gClamp(r2() * TexGran.panSpread(sp), -1, 1)
        let frames: Double = dur * sr
        if frames < 2 { return }
        let k = grains
        grains += 1
        track.pointee.grains += 1
        let at = start.rounded(.up)
        let frac: Double = at - start
        let phStep: Double = Double(GranularVoice.winPoints - 1) / frames
        gPos[k] = pos * sr + frac * rate
        gStep[k] = rate
        gPh[k] = frac * phStep
        gPhStep[k] = phStep
        let th: Double = 2 * Double.pi * frac / frames
        let dth: Double = 2 * Double.pi / frames
        gCr[k] = cos(th)
        gCi[k] = sin(th)
        gWr[k] = cos(dth)
        gWi[k] = sin(dth)
        gGauss[k] = g ? 1 : 0
        gAt[k] = -Int(at)
        let gg = gG + k * 4
        if src.channels > 1 && src.right != nil {
            // Баланс (StereoPanner веба со стерео-входом).
            let x: Double = (pan <= 0 ? pan + 1 : pan) * Double.pi / 2
            gg[0] = pan <= 0 ? 1 : cos(x)
            gg[1] = pan <= 0 ? cos(x) : 0
            gg[2] = pan <= 0 ? sin(x) : 1
            gg[3] = pan <= 0 ? 0 : sin(x)
        } else {
            let x: Double = (pan + 1) / 2 * Double.pi / 2
            gg[0] = cos(x)
            gg[1] = sin(x)
            gg[2] = 0
            gg[3] = 0
        }
        gSrc[k] = src
        onSpawn?(clock + start, pos, rate, pan)
    }

    /// Стерео-выход n кадров (n ≤ TextureVoice.maxChunk); window — кадров окна запуска (окно активности).
    func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int, window: Int,
                src: GrainSrc) {
        let hasSrc: Bool = src.left != nil && src.frames > 1
        let len: Double = hasSrc ? Double(src.frames) / sr : 0
        // Курсор: постоянная 150 мс.
        let k150: Double = 1 - exp(-Double(n) / (0.15 * sr))
        head += (position - head) * k150
        sizeS += (size - sizeS) * k150
        densS += (density - densS) * k150
        if spawning { track.pointee.head = head }
        let notesN: Int = Swift.max(1, track.pointee.notes)
        let sc: Double = Swift.min(1, 4 / Double(notesN))
        let g0: Double = gain
        if hasSrc {
            let gs = TexGran.state(size: sizeS, density: densS, sc: sc, sampleSeconds: len)
            let pl = TexGran.plan(dur: gs.dur, eff: gs.eff, ts: src.period, semi: note - GranularVoice.root, spray: spray)
            let target: Double = pl.gain * TexGran.out
            let tau: Double = target > g0 ? Swift.max(0.08 * sr, longest) : 0.08 * sr
            gain = fresh ? target : g0 + (target - g0) * (1 - exp(-Double(n) / tau))
            fresh = false
            if spawning {
                let jit: Double = TexGran.jitter(spray)
                let ivF: Double = pl.iv * sr
                let gauss: Bool = gs.eff < 2
                while nextAt < Double(n) {
                    let at: Double = nextAt < 0 ? 0 : nextAt
                    if at >= Double(window) {
                        spawning = false
                        break
                    }
                    spawn(at, src, dur: gs.dur, gauss: gauss)
                    nextAt += jit > 0 ? ivF * (1 + r2() * jit) : ivF
                }
            }
        }
        if spawning {
            nextAt = hasSrc ? nextAt - Double(n) : Swift.max(0, nextAt - Double(n))
            if window <= n { spawning = false }
        }
        clock += Double(n)
        let bl = busL, br = busR
        bl.update(repeating: 0, count: n)
        br.update(repeating: 0, count: n)
        let last: Double = Double(GranularVoice.winPoints - 1)
        var minStep = 1.0
        var e = 0
        while e < grains {
            let s = gSrc[e]
            var at = gAt[e]
            var pos = gPos[e]
            let step = gStep[e]
            var ph = gPh[e]
            let phStep = gPhStep[e]
            if phStep < minStep { minStep = phStep }
            let tab: UnsafeMutablePointer<Double> = gGauss[e] != 0 ? GranularVoice.gauss : GranularVoice.hann
            let g = gG + e * 4
            let ga = g[0], gb = g[1], gc = g[2], gd = g[3]
            let lp = s.left!
            let lastF = s.frames - 1
            var i = 0
            if at < 0 {
                i = -at
                at = 0
            }
            let hannW: Bool = gGauss[e] == 0
            // Весь кусок — внутри сэмпла: без проверки на отсчёт.
            let safe: Bool = Int(pos + step * Double(n - i)) + 1 < lastF
            var cr = gCr[e], ci = gCi[e]
            let wr = gWr[e], wi = gWi[e]
            if hannW && safe {
                if s.channels > 1, let rp = s.right {
                    while i < n && ph < last {
                        let w: Double = 0.5 - 0.5 * cr
                        let ip = Int(pos)
                        let f: Double = pos - Double(ip)
                        let l0 = Double(lp[ip]), r0 = Double(rp[ip])
                        let a: Double = (l0 + (Double(lp[ip + 1]) - l0) * f) * w
                        let b: Double = (r0 + (Double(rp[ip + 1]) - r0) * f) * w
                        bl[i] += a * ga + b * gb
                        br[i] += b * gc + a * gd
                        let t: Double = cr * wr - ci * wi
                        ci = cr * wi + ci * wr
                        cr = t
                        ph += phStep
                        pos += step
                        i += 1
                    }
                } else {
                    while i < n && ph < last {
                        let w: Double = 0.5 - 0.5 * cr
                        let ip = Int(pos)
                        let l0 = Double(lp[ip])
                        let a: Double = (l0 + (Double(lp[ip + 1]) - l0) * (pos - Double(ip))) * w
                        bl[i] += a * ga
                        br[i] += a * gb
                        let t: Double = cr * wr - ci * wi
                        ci = cr * wi + ci * wr
                        cr = t
                        ph += phStep
                        pos += step
                        i += 1
                    }
                }
            } else if s.channels > 1, let rp = s.right {
                while i < n && ph < last {
                    let wi = Int(ph)
                    let w: Double = tab[wi] + (tab[wi + 1] - tab[wi]) * (ph - Double(wi))
                    let ip = Int(pos)
                    let f: Double = pos - Double(ip)
                    var a = 0.0, b = 0.0
                    if ip < lastF {
                        a = Double(lp[ip]) + (Double(lp[ip + 1]) - Double(lp[ip])) * f
                        b = Double(rp[ip]) + (Double(rp[ip + 1]) - Double(rp[ip])) * f
                    }
                    a *= w
                    b *= w
                    bl[i] += a * ga + b * gb
                    br[i] += b * gc + a * gd
                    ph += phStep
                    pos += step
                    i += 1
                }
            } else {
                while i < n && ph < last {
                    let wi = Int(ph)
                    let w: Double = tab[wi] + (tab[wi + 1] - tab[wi]) * (ph - Double(wi))
                    let ip = Int(pos)
                    let f: Double = pos - Double(ip)
                    var a = 0.0
                    if ip < lastF { a = Double(lp[ip]) + (Double(lp[ip + 1]) - Double(lp[ip])) * f }
                    a *= w
                    bl[i] += a * ga
                    br[i] += a * gb
                    ph += phStep
                    pos += step
                    i += 1
                }
            }
            // Медленный путь Ханна (по таблице) — поворот догоняет фазу окна.
            if hannW && !safe {
                let th: Double = 2 * Double.pi * ph / last
                cr = cos(th)
                ci = sin(th)
            }
            if ph >= last {
                grains -= 1
                track.pointee.grains -= 1
                if e != grains {
                    gPos[e] = gPos[grains]
                    gStep[e] = gStep[grains]
                    gPh[e] = gPh[grains]
                    gPhStep[e] = gPhStep[grains]
                    gCr[e] = gCr[grains]
                    gCi[e] = gCi[grains]
                    gWr[e] = gWr[grains]
                    gWi[e] = gWi[grains]
                    gGauss[e] = gGauss[grains]
                    gAt[e] = gAt[grains]
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
            gPh[e] = ph
            gCr[e] = cr
            gCi[e] = ci
            e += 1
        }
        longest = grains > 0 ? last / minStep : 0
        // Усиление шины — плавно по куску.
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
