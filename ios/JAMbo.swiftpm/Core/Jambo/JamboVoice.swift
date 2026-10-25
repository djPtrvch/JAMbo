import Foundation

// Голос своих движков JAMbo — KICK, ANALOG, FM, WTABLE (перенос класса Voice из public/jambo-synth-worklet.js;
// ручки 1.4 и новые режимы — S12).
// Состояние и арифметика — в Double (как JS), отсчёты выхода и буфер фильтра децимации — значения Float (Float32Array;
// буфер хранит их в Double — без преобразования на каждом отводе).
// Горячие циклы — без вызовов из других файлов, состояние — в локальных переменных (отладочная сборка Playgrounds).

/// frac(x) = x − floor(x).
@_transparent private func jFrac(_ x: Double) -> Double { x - x.rounded(.down) }

/// floor(x) для |x| < 2⁶³ (rounded(.down) в отладочной сборке — медленный вызов; S14b).
@_transparent private func jFloor(_ x: Double) -> Double {
    let f = Double(Int(x))
    return f > x ? f - 1 : f
}

/// Синус по фазе в периодах (таблица 4096 с линейной интерполяцией), как sinT в worklet; таблица — sineD (значения
/// Float в Double).
@_transparent private func jSin(_ table: UnsafePointer<Double>, _ ph: Double) -> Double {
    var x = ph - jFloor(ph)
    x *= 4096
    let i = Int(x)
    let a = table[i], b = table[i + 1]
    return a + (b - a) * (x - Double(i))
}

/// PolyBLEP: поправка у разрыва (t — фаза 0…1, dt — шаг фазы).
@_transparent private func jBlep(_ t0: Double, _ dt: Double) -> Double {
    if t0 < dt {
        let t = t0 / dt
        return t + t - t * t - 1
    }
    if t0 > 1 - dt {
        let t = (t0 - 1) / dt
        return t * t + t + t + 1
    }
    return 0
}

/// Треугольник ANALOG (пик на φ = 0.25).
@_transparent private func jTriAt(_ ph: Double) -> Double { 1 - 4 * abs(ph < 0.75 ? ph - 0.25 : ph - 1.25) }

/// Отсчёт формы k осциллятора с фазой a, шагом dt и треугольником tri.
@_transparent private func jShapeAt(_ sine: UnsafePointer<Double>, _ k: Int, _ a: Double, _ dt: Double,
                                    _ tri: Double) -> Double {
    if k == 0 { return jSin(sine, a) }
    if k == 1 { return tri }
    if k == 2 { return 1 - 2 * a + jBlep(a, dt) }
    return (a < 0.5 ? 1 : -1) + jBlep(a, dt) - jBlep(a < 0.5 ? a + 0.5 : a - 0.5, dt)
}

/// Полуполосный фильтр децимации (63 отвода, S14b): x — центр окна, k — hbHK (пары центр ∓ (2j + 1)), kc — центр;
/// без цикла (в отладочной сборке счётчик и индексы цикла дороже самих умножений).
@_transparent private func jHalf(_ x: UnsafeMutablePointer<Double>, _ k: UnsafeMutablePointer<Double>, _ kc: Double) -> Double {
    var a: Double = k[0] * (x[-1] + x[1])
    a += k[1] * (x[-3] + x[3])
    a += k[2] * (x[-5] + x[5])
    a += k[3] * (x[-7] + x[7])
    a += k[4] * (x[-9] + x[9])
    a += k[5] * (x[-11] + x[11])
    a += k[6] * (x[-13] + x[13])
    a += k[7] * (x[-15] + x[15])
    a += k[8] * (x[-17] + x[17])
    a += k[9] * (x[-19] + x[19])
    a += k[10] * (x[-21] + x[21])
    a += k[11] * (x[-23] + x[23])
    a += k[12] * (x[-25] + x[25])
    a += k[13] * (x[-27] + x[27])
    a += k[14] * (x[-29] + x[29])
    a += k[15] * (x[-31] + x[31])
    return a + kc * x[0]
}

@_transparent private func jFlush(_ x: Double) -> Double { (x > 1e-20 || x < -1e-20) ? x : 0 }

/// Таблица WTABLE для колбэка — только указатели (WtTable живёт в кэше и снимке звука).
struct WtRef {
    var frames = 0
    var sizes: UnsafePointer<Int>? = nil
    var data: UnsafePointer<UnsafeMutablePointer<Float>>? = nil
}

final class JamboVoice {
    private let tables: JamboTables
    private let sr: Double
    private(set) var engine = Jambo.drum
    private var note = 48.0
    // Цели ручек и сглаженные значения.
    private var t1 = 0.5, t2 = 0.5, t3 = 0.5, t4 = 0.5, td = 500.0
    private var s1 = 0.5, s2 = 0.5, s3 = 0.5, s4 = 0.5, sd = 500.0
    private var t = 0.0
    private var rnd = 22222
    // DRUM
    private var p1 = 0.0, dc = 0.0
    /// Последний отсчёт DRUM до клиппера (сглаживание стыка при ретриге); 0 — голос молчал.
    var last = 0.0
    // ANALOG: осцилляторы A и B, у каждого своя форма (смена — кроссфейд).
    private var a1 = 0.0, a2 = 0.0, tri1 = 0.0, tri2 = 0.0
    private var wCur = 0, wPrev = 0, wMix = 1.0
    private var bCur = 0, bPrev = 0, bMix = 1.0
    // SUB: фильтр постоянной составляющей после GRIT.
    private var hx = 0.0, hy = 0.0
    // FM
    private var pc = 0.0, pm = 0.0, m1 = 0.0, m2 = 0.0
    private let hb: UnsafeMutablePointer<Double>
    private var hbPos = 0
    // WTABLE: центр и до четырёх боковых голосов (±DETUNE, ±DETUNE/2).
    private var w0 = 0.0, wl = 0.0, wr = 0.0, wl2 = 0.0, wr2 = 0.0
    // Вход новой ноты (кадров с её начала).
    private var fade = Jambo.fadeIn

    /// xorshift32 голоса (rand в worklet; состояние — Int 0…2³²−1).
    private func rand() -> Double {
        rnd = JamboDrift.xorshift(rnd)
        return Double(rnd) / 4294967296
    }

    init(tables: JamboTables, sampleRate: Double) {
        self.tables = tables
        sr = sampleRate
        hb = .allocate(capacity: Jambo.hbLen * 2)
        hb.initialize(repeating: 0, count: Jambo.hbLen * 2)
    }

    deinit { hb.deallocate() }

    /// Ручки (mod): p1–p4 — 0…1, decay — мс.
    @inline(__always) func set(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double, decay: Double) {
        note = n
        t1 = q1
        t2 = q2
        t3 = q3
        t4 = q4
        td = decay
    }

    /// Нота в кадре now (абсолютный кадр), tau — время дорожки с дрейфом на этот кадр.
    func trigger(engine e: Int, note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double, decay: Double,
                 now: Double, tau: Double) {
        // KICK и SUB монофоничны: новый удар (нота) в тот же слот, хвост прошлого гаснет за ~2 мс.
        dc = (e == Jambo.drum && engine == Jambo.drum) || (e == Jambo.sub && engine == Jambo.sub) ? last : 0
        // SUB на звучащей ноте: фазы генераторов продолжаются (сброс на каждой ноте давал щелчок — проверено на стенде).
        let subGoesOn: Bool = e == Jambo.sub && engine == Jambo.sub && last != 0
        engine = e
        set(note: n, q1, q2, q3, q4, decay: decay)
        // Новая нота — ручки сразу на своих местах (сглаживание — только для смены на лету).
        s1 = t1
        s2 = t2
        s3 = t3
        s4 = t4
        sd = td
        t = 0
        p1 = 0
        m1 = 0
        m2 = 0
        // Фаза новой ноты — как у генератора, который бежит непрерывно (frac(f·t)); оба осциллятора ANALOG — из одной точки.
        let f = 440 * pow(2, (note - 69) / 12) / sr
        if !subGoesOn {
            // Буфер децимации и фазы — заново; у продолжающегося SUB — как есть (иначе разрыв волны).
            hb.update(repeating: 0, count: Jambo.hbLen * 2)
            // ANALOG: DETUNE — ручка 1.3 (S12).
            let det = Jambo.analogDetune / 2 * s3 * s3
            a1 = jFrac(f * pow(2, det / 1200) * tau)
            a2 = jFrac(f * pow(2, -det / 1200) * tau)
            tri1 = jTriAt(a1)
            tri2 = jTriAt(a2)
            wCur = Jambo.waveIndex(t1)
            wPrev = wCur
        }
        wMix = 1
        bCur = Jambo.waveIndex(t2)
        bPrev = bCur
        bMix = 1
        // SUB после тишины: фазы обоих осцилляторов — там, где волна проходит ноль (треугольник — 0, пила — середина
        // периода), иначе нота начиналась бы с пика (щелчок); на звучащей ноте — продолжаются.
        if e == Jambo.sub && !subGoesOn {
            wCur = Swift.min(2, Int(t1 * 3)) + 1
            let p0: Double = wCur == 2 ? 0.5 : 0
            a1 = p0
            a2 = p0
            tri1 = 0
            tri2 = 0
            wPrev = wCur
            hx = 0
            hy = 0
        }
        pc = jFrac(f * now)
        pm = jFrac(Jambo.fmRatio(s1) * f * now)
        // WTABLE: центр — так же, боковые — со случайной фазы.
        w0 = jFrac(f * now)
        wl = rand()
        wr = rand()
        wl2 = rand()
        wr2 = rand()
        fade = 0
        // SUB на звучащей ноте: волна непрерывна — без плавного входа и без хвоста прошлой ноты (вместе они дают горб
        // громкости на стыке).
        if subGoesOn {
            fade = Jambo.fadeIn
            dc = 0
        }
    }

    /// Кусок n кадров (n ≤ 24) в out; driftRatio — множитель дрейфа дорожки (ANALOG).
    func render(_ out: UnsafeMutablePointer<Float>, _ n: Int, driftRatio: Double, table: WtRef = WtRef()) {
        let k = 1 - exp(-Double(n) / (Jambo.smooth * sr))
        // Свойства — через локальные (в отладочной сборке каждое обращение к свойству класса — проверка доступа).
        let v1: Double = s1, v2: Double = s2, v3: Double = s3, v4: Double = s4, vd: Double = sd
        s1 = v1 + (t1 - v1) * k
        s2 = v2 + (t2 - v2) * k
        s3 = v3 + (t3 - v3) * k
        s4 = v4 + (t4 - v4) * k
        sd = vd + (td - vd) * k
        let e: Int = engine
        if e == Jambo.drum {
            drum(out, n)
        } else if e == Jambo.analog {
            analog(out, n, driftRatio)
        } else if e == Jambo.fm {
            fm(out, n)
        } else if e == Jambo.wtable {
            wtable(out, n, table)
        } else if e == Jambo.sub {
            subBass(out, n)
        } else {
            out.update(repeating: 0, count: n)
        }
        // Начало ноты ANALOG, FM, WTABLE — плавно за fadeIn кадров (после фильтра децимации); у KICK свой старт, у SUB —
        // внутри движка (поверх идёт хвост прошлой ноты).
        let fadeIn: Int = Jambo.fadeIn
        var fd: Int = fade
        if fd < fadeIn && e != Jambo.drum && e != Jambo.sub {
            var i = 0
            while i < n && fd < fadeIn {
                fd += 1
                out[i] = Float(Double(out[i]) * Double(fd) / Double(fadeIn))
                i += 1
            }
            fade = fd
        }
    }

    // MARK: — KICK: синус со свипом высоты + клик → мягкий клиппер.

    @inline(__always) private func drum(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let tauSec = 2 * Double.pi
        // PITCH: 30 → 100 Гц логарифмически; нота высоту не меняет.
        let f0 = Jambo.drumPitchMin * pow(Jambo.drumPitchMax / Jambo.drumPitchMin, s1)
        // Decay — время до −60 dB (постоянная = Decay / 6.9), не больше 1000 мс.
        let decay = Swift.min(Jambo.drumDecayMax, sd)
        let tauE = Swift.max(0.001, decay / 1000 / Jambo.drumT60)
        // SWEEP: 0…+48 полутонов, время свипа = clamp(0.08 × Decay, 6, 80 мс).
        let tauSweep = Swift.min(0.08, Swift.max(0.006, 0.08 * decay / 1000))
        let semis = 48 * s2
        // DRIVE: tanh (запас 1 → 12), компенсация. CLICK (S12): уровень клика 0 → 1.0, длина 3 → 1 мс.
        let dg = 1 + 11 * s3
        let comp = Jambo.drumSine / tanh(dg * Jambo.drumSine)
        let click = s4
        let clickLen = Jambo.drumClick * (1.5 - s4) * sr
        let dEnv = exp(-1 / (tauE * sr))
        let dSweep = exp(-1 / (tauSweep * sr))
        let dDc = exp(-1 / (Jambo.drumDeclick * sr))
        let sine = Jambo.drumSine, outG = Jambo.drumOut
        var tt = t
        var env = exp(-tt / (tauE * sr))
        var sw = exp(-tt / (tauSweep * sr))
        var ph = p1, d = dc, x = 0.0
        var i = 0
        while i < n {
            let f = f0 * pow(2, semis * sw / 12)
            ph += f / sr
            if ph >= 1 { ph -= 1 }
            x = env * sine * sin(tauSec * ph)
            if tt < clickLen { x += click * (1 - tt / clickLen) }
            // Ретриг: хвост прошлого удара гаснет за ~2 мс — до клиппера.
            x += d
            out[i] = Float(outG * comp * tanh(dg * x))
            d *= dDc
            env *= dEnv
            sw *= dSweep
            tt += 1
            i += 1
        }
        p1 = ph
        dc = jFlush(d)
        last = x
        t = tt
    }

    // MARK: — ANALOG: осцилляторы A и B (PolyBLEP, своя форма у каждого), ×2 передискретизация и полуполосный фильтр.

    @inline(__always) private func analog(_ out: UnsafeMutablePointer<Float>, _ n: Int, _ ratio: Double) {
        let sr2 = sr * 2
        let sine = UnsafePointer(tables.sineD)
        let f0 = 440 * pow(2, (note - 69) / 12) * ratio
        // DETUNE (1.3): A вверх, B вниз, в сумме 0…60 центов по кривой x².
        let det = Jambo.analogDetune / 2 * s3 * s3
        let dt1 = Swift.min(0.45, f0 * pow(2, det / 1200) / sr2)
        let dt2 = Swift.min(0.45, f0 * pow(2, -det / 1200) / sr2)
        // WAVE A и WAVE B — ступенчатые (пункт по ручке, без сглаживания); смена пункта — кроссфейд форм за 5 мс.
        let ia = Jambo.waveIndex(t1)
        if ia != wCur {
            wPrev = wCur
            wCur = ia
            wMix = 0
        }
        let ib = Jambo.waveIndex(t2)
        if ib != bCur {
            bPrev = bCur
            bCur = ib
            bMix = 0
        }
        let ca = wCur, pa = wPrev, cb = bCur, pb = bPrev
        let gA = Double(tables.shapeGain[ca]), gAp = Double(tables.shapeGain[pa])
        let gB = Double(tables.shapeGain[cb]), gBp = Double(tables.shapeGain[pb])
        let xfStep = 1 / (Jambo.analogWaveXf * sr2)
        var mixA = wMix, mixB = bMix
        // MIX (1.4): доли по постоянной мощности (cos/sin), нормированные на сумму — пик не растёт; 50 % — поровну.
        let ang = s4 * Double.pi / 2
        let ka = cos(ang), kb = sin(ang)
        let wa = Jambo.analogOut * ka / (ka + kb), wb = Jambo.analogOut * kb / (ka + kb)
        let leak = 1 - 20 / sr2
        var o1 = a1, o2 = a2, tr1 = tri1, tr2 = tri2, hp = hbPos
        let buf = hb, len = Jambo.hbLen
        let hk = tables.hbHK, kC = tables.hbCK, mid = Jambo.hbLen / 2
        var i = 0
        while i < n {
            var j = 0
            while j < 2 {
                // Треугольник — интеграл квадрата, сдвинутого на четверть периода (пик на φ = 0.25).
                let b1 = o1 < 0.75 ? o1 + 0.25 : o1 - 0.75, b2 = o2 < 0.75 ? o2 + 0.25 : o2 - 0.75
                tr1 = tr1 * leak + 4 * dt1 * ((b1 < 0.5 ? 1 : -1) + jBlep(b1, dt1) - jBlep(b1 < 0.5 ? b1 + 0.5 : b1 - 0.5, dt1))
                tr2 = tr2 * leak + 4 * dt2 * ((b2 < 0.5 ? 1 : -1) + jBlep(b2, dt2) - jBlep(b2 < 0.5 ? b2 + 0.5 : b2 - 0.5, dt2))
                var xa = gA * jShapeAt(sine, ca, o1, dt1, tr1)
                if mixA < 1 {
                    mixA = Swift.min(1, mixA + xfStep)
                    let old = gAp * jShapeAt(sine, pa, o1, dt1, tr1)
                    xa = old + (xa - old) * mixA
                }
                var xb = gB * jShapeAt(sine, cb, o2, dt2, tr2)
                if mixB < 1 {
                    mixB = Swift.min(1, mixB + xfStep)
                    let old = gBp * jShapeAt(sine, pb, o2, dt2, tr2)
                    xb = old + (xb - old) * mixB
                }
                let y = Double(Float(wa * xa + wb * xb))
                buf[hp] = y
                buf[hp + len] = y
                hp = hp + 1 == len ? 0 : hp + 1
                o1 += dt1
                if o1 >= 1 { o1 -= 1 }
                o2 += dt2
                if o2 >= 1 { o2 -= 1 }
                j += 1
            }
            let acc: Double = jHalf(buf + hp + mid, hk, kC)
            out[i] = Float(acc)
            i += 1
        }
        wMix = mixA
        bMix = mixB
        a1 = o1
        a2 = o2
        tri1 = jFlush(tr1)
        tri2 = jFlush(tr2)
        hbPos = hp
        t += Double(n)
    }

    // MARK: — SUB: OSC1 (нота) и OSC2 (октавой ниже, FAT), одна форма; GRIT (tanh), ×2 и полуполосный фильтр.

    @inline(__always) private func subBass(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sr2 = sr * 2
        let sine = UnsafePointer(tables.sineD)
        let f0 = 440 * pow(2, (note - 69) / 12)
        let dt1 = Swift.min(0.45, f0 / sr2)
        let dt2 = Swift.min(0.45, 0.5 * f0 * pow(2, Jambo.subFat * s3 / 1200) / sr2)
        // WAVE — ступенчатая: Triangle, Saw, Square (формы ANALOG 1–3); смена — кроссфейд за 5 мс.
        let idx = Swift.min(2, Int(t1 * 3)) + 1
        if idx != wCur {
            wPrev = wCur
            wCur = idx
            wMix = 0
        }
        let cur = wCur, prev = wPrev
        let gC = Double(tables.shapeGain[cur]), gP = Double(tables.shapeGain[prev])
        let xfStep = 1 / (Jambo.analogWaveXf * sr2)
        var mix = wMix
        // SUB: OSC2 подмешивается к OSC1 (0 — только основной, 100 % — оба поровну), нормировка на сумму (пик не растёт).
        let w1 = 1 / (1 + s2), w2 = s2 / (1 + s2)
        // GRIT: tanh с усилением 0 → +24 дБ, нормировка на tanh(усиления) — пик прежний; у нуля — прозрачно.
        let gg = pow(10, 1.2 * s4)
        let wg = Swift.min(1, s4 / 0.1)
        let tg = tanh(gg)
        let rHp = 1 - 2 * Double.pi * 3 / sr2
        let leak = 1 - 20 / sr2
        let dDc = exp(-1 / (0.002 * sr))
        var o1 = a1, o2 = a2, tr1 = tri1, tr2 = tri2, hp = hbPos, x0 = hx, y0 = hy, d = dc, fd = fade
        let fadeN = Jambo.fadeIn
        let buf = hb, len = Jambo.hbLen
        let hk = tables.hbHK, kC = tables.hbCK, mid = Jambo.hbLen / 2
        let outG = Jambo.subOut
        var i = 0
        while i < n {
            var j = 0
            while j < 2 {
                let b1 = o1 < 0.75 ? o1 + 0.25 : o1 - 0.75, b2 = o2 < 0.75 ? o2 + 0.25 : o2 - 0.75
                tr1 = tr1 * leak + 4 * dt1 * ((b1 < 0.5 ? 1 : -1) + jBlep(b1, dt1) - jBlep(b1 < 0.5 ? b1 + 0.5 : b1 - 0.5, dt1))
                tr2 = tr2 * leak + 4 * dt2 * ((b2 < 0.5 ? 1 : -1) + jBlep(b2, dt2) - jBlep(b2 < 0.5 ? b2 + 0.5 : b2 - 0.5, dt2))
                var x = gC * (w1 * jShapeAt(sine, cur, o1, dt1, tr1) + w2 * jShapeAt(sine, cur, o2, dt2, tr2))
                if mix < 1 {
                    mix = Swift.min(1, mix + xfStep)
                    let old = gP * (w1 * jShapeAt(sine, prev, o1, dt1, tr1) + w2 * jShapeAt(sine, prev, o2, dt2, tr2))
                    x = old + (x - old) * mix
                }
                if wg > 0 { x = (1 - wg) * x + wg * tanh(gg * x) / tg }
                // Постоянная составляющая — ФВЧ 3 Гц.
                let y = x - x0 + rHp * y0
                x0 = x
                y0 = y
                let z = Double(Float(y))
                buf[hp] = z
                buf[hp + len] = z
                hp = hp + 1 == len ? 0 : hp + 1
                o1 += dt1
                if o1 >= 1 { o1 -= 1 }
                o2 += dt2
                if o2 >= 1 { o2 -= 1 }
                j += 1
            }
            let acc: Double = jHalf(buf + hp + mid, hk, kC)
            // Вход ноты — за fadeIn кадров; хвост прошлой ноты (d) гаснет за ~2 мс.
            var g = outG
            if fd < fadeN {
                fd += 1
                g *= Double(fd) / Double(fadeN)
            }
            let o = g * acc + d
            out[i] = Float(o)
            last = o
            d *= dDc
            i += 1
        }
        wMix = mix
        a1 = o1
        a2 = o2
        tri1 = jFlush(tr1)
        tri2 = jFlush(tr2)
        hbPos = hp
        hx = x0
        hy = jFlush(y0)
        dc = jFlush(d)
        fade = fd
        t += Double(n)
    }

    // MARK: — FM: несущая (ratio 1) и модулятор (RATIO) с обратной связью, ×2 передискретизация.

    @inline(__always) private func fm(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sine = UnsafePointer(tables.sineD)
        let f0 = 440 * pow(2, (note - 69) / 12)
        let ratio = Jambo.fmRatio(s1)
        let idxNorm = pow(s2, 1.5)
        // Индекс в радианах → в долях периода.
        let index = Jambo.fmIndex * idxNorm / (2 * Double.pi)
        // FEEDBACK (1.4, S12): 50 % — как прежде.
        let fb = Jambo.fmFeedback * idxNorm * s4 * 2
        // CONTOUR: индекс спадает с постоянной от Decay: 0 % — постоянный, 50 % — как амплитуда, 100 % — в 5 раз быстрее.
        let m = s3
        let k = m < 0.5 ? 2 * m : 1 + 8 * (m - 0.5)
        let tauA = Swift.max(0.001, sd / 4000)
        let rate = k / tauA
        let dt = f0 / (2 * sr)
        var env = exp(-t / sr * rate)
        let dEnv = exp(-rate / sr)
        var c = pc, md = pm, x1 = m1, x2 = m2, hp = hbPos
        let buf = hb, len = Jambo.hbLen
        let hk = tables.hbHK, kC = tables.hbCK, mid = Jambo.hbLen / 2
        let fmOut = Jambo.fmOut
        var i = 0
        while i < n {
            var j = 0
            while j < 2 {
                let mod = jSin(sine, md + fb * 0.5 * (x1 + x2))
                x2 = x1
                x1 = mod
                let y = Double(Float(jSin(sine, c + index * env * mod)))
                md += ratio * dt
                if md >= 1 { md -= jFloor(md) }
                c += dt
                if c >= 1 { c -= 1 }
                buf[hp] = y
                buf[hp + len] = y
                hp = hp + 1 == len ? 0 : hp + 1
                j += 1
            }
            // Децимация: свёртка с полуполосным фильтром (только ненулевые отводы; симметричные — парами, затем центр).
            let acc: Double = jHalf(buf + hp + mid, hk, kC)
            out[i] = Float(fmOut * acc)
            env *= dEnv
            i += 1
        }
        pc = c
        pm = md
        m1 = x1
        m2 = x2
        hbPos = hp
        t += Double(n)
    }

    // MARK: — WTABLE: кадры таблицы по фазе и между кадрами, мипмап по октаве, WARP и UNISON.

    @inline(__always) private func wtable(_ out: UnsafeMutablePointer<Float>, _ n: Int, _ tb: WtRef) {
        guard tb.frames > 0, let sizes = tb.sizes, let levels = tb.data else {
            out.update(repeating: 0, count: n)
            return
        }
        let f0 = 440 * pow(2, (note - 69) / 12)
        let frames = tb.frames
        let fpos = s1 * Double(frames - 1)
        let fi = Swift.min(frames - 2, Swift.max(0, Int(fpos.rounded(.down))))
        let ff = frames > 1 ? fpos - Double(fi) : 0
        // WARP: 0…50 % — изгиб фазы φ^(1+3w); 50…100 % — плюс синхронизация 1 → 4.
        let w = s2
        let bend = 1 + 3 * Swift.min(1, w * 2)
        let sync = w > 0.5 ? 1 + 3 * (w - 0.5) * 2 : 1
        // UNISON (1.3, ступенчатая): 1 / 3 / 5 голосов; DETUNE (1.4): 0 → 60 центов — боковые на ±DETUNE
        // (у пяти — ещё ±DETUNE/2), на −3 дБ; громкость нормируется по числу голосов.
        let un = t3 < 1.0 / 3 ? 1 : (t3 < 2.0 / 3 ? 3 : 5)
        let side = Jambo.wtSide
        let cents = un == 1 ? 0 : Jambo.wtDetune * s4
        let norm = Jambo.wtOut / (1 + Double(un - 1) * side * side).squareRoot()
        let dt0 = f0 / sr
        let dtl = dt0 * pow(2, -cents / 1200), dtr = dt0 * pow(2, cents / 1200)
        let dtl2 = dt0 * pow(2, -cents / 2400), dtr2 = dt0 * pow(2, cents / 2400)
        // Мипмап: уровень, где гармоники (с учётом синхронизации и изгиба) не выше Найквиста.
        let fEff = f0 * pow(2, cents / 1200) * sync * (1 + (bend - 1) * 0.5)
        let lvf = log2(1024 * fEff / (0.5 * sr)).rounded(.up)
        let lv = Swift.min(WtTable.levelCount - 1, Swift.max(0, Int(Swift.max(-1, Swift.min(64, lvf)))))
        let size = sizes[lv]
        let data = levels[lv]
        let rowA = fi * size, rowB = (frames > 1 ? fi + 1 : fi) * size
        var c0 = w0, cl = wl, cr = wr, cl2 = wl2, cr2 = wr2
        let bent = bend != 1
        let sizeF = Double(size)
        var i = 0
        while i < n {
            var y = 0.0
            var v = 0
            while v < un {
                var ph = v == 0 ? c0 : (v == 1 ? cl : (v == 2 ? cr : (v == 3 ? cl2 : cr2)))
                if sync != 1 {
                    ph *= sync
                    ph -= jFloor(ph)
                }
                if bent { ph = pow(ph, bend) }
                let x = ph * sizeF
                let j = Int(x)
                let fr = x - Double(j)
                let j2 = j + 1 == size ? 0 : j + 1
                let a0 = Double(data[rowA + j]), a1 = Double(data[rowA + j2])
                let b0 = Double(data[rowB + j]), b1 = Double(data[rowB + j2])
                let a = a0 + (a1 - a0) * fr
                let b = b0 + (b1 - b0) * fr
                y += (v == 0 ? 1 : side) * (a + (b - a) * ff)
                v += 1
            }
            out[i] = Float(norm * y)
            c0 += dt0
            if c0 >= 1 { c0 -= 1 }
            cl += dtl
            if cl >= 1 { cl -= 1 }
            cr += dtr
            if cr >= 1 { cr -= 1 }
            cl2 += dtl2
            if cl2 >= 1 { cl2 -= 1 }
            cr2 += dtr2
            if cr2 >= 1 { cr2 -= 1 }
            i += 1
        }
        w0 = c0
        wl = cl
        wr = cr
        wl2 = cl2
        wr2 = cr2
        t += Double(n)
    }
}
