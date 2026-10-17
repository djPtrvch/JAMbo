import Foundation

// Голос своих движков JAMbo — DRUM, ANALOG, FM (перенос класса Voice из public/jambo-synth-worklet.js 1:1).
// Состояние и арифметика — в Double (как JS), отсчёты выхода и буфер фильтра децимации — во Float (Float32Array).
// Горячие циклы — без вызовов из других файлов, состояние — в локальных переменных (отладочная сборка Playgrounds).

/// frac(x) = x − floor(x).
@_transparent private func jFrac(_ x: Double) -> Double { x - x.rounded(.down) }

/// Синус по фазе в периодах (таблица 4096 с линейной интерполяцией), как sinT в worklet.
@_transparent private func jSin(_ table: UnsafePointer<Float>, _ ph: Double) -> Double {
    var x = ph - ph.rounded(.down)
    x *= 4096
    let i = Int(x)
    let a = Double(table[i]), b = Double(table[i + 1])
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
@_transparent private func jShapeAt(_ sine: UnsafePointer<Float>, _ k: Int, _ a: Double, _ dt: Double,
                                    _ tri: Double) -> Double {
    if k == 0 { return jSin(sine, a) }
    if k == 1 { return tri }
    if k == 2 { return 1 - 2 * a + jBlep(a, dt) }
    return (a < 0.5 ? 1 : -1) + jBlep(a, dt) - jBlep(a < 0.5 ? a + 0.5 : a - 0.5, dt)
}

@_transparent private func jFlush(_ x: Double) -> Double { (x > 1e-20 || x < -1e-20) ? x : 0 }

final class JamboVoice {
    private let tables: JamboTables
    private let sr: Double
    private(set) var engine = Jambo.drum
    private var note = 48.0
    // Цели ручек и сглаженные значения.
    private var t1 = 0.5, t2 = 0.5, t3 = 0.5, td = 500.0
    private var s1 = 0.5, s2 = 0.5, s3 = 0.5, sd = 500.0
    private var t = 0.0
    private var rnd = 22222
    // DRUM
    private var p1 = 0.0, dc = 0.0
    /// Последний отсчёт DRUM до клиппера (сглаживание стыка при ретриге); 0 — голос молчал.
    var last = 0.0
    // ANALOG
    private var a1 = 0.0, a2 = 0.0, aSub = 0.0, tri1 = 0.0, tri2 = 0.0
    private var wCur = 0, wPrev = 0, wMix = 1.0
    // FM
    private var pc = 0.0, pm = 0.0, m1 = 0.0, m2 = 0.0
    private let hb: UnsafeMutablePointer<Float>
    private var hbPos = 0
    // Вход новой ноты (кадров с её начала).
    private var fade = Jambo.fadeIn

    init(tables: JamboTables, sampleRate: Double) {
        self.tables = tables
        sr = sampleRate
        hb = .allocate(capacity: Jambo.hbLen * 2)
        hb.initialize(repeating: 0, count: Jambo.hbLen * 2)
    }

    deinit { hb.deallocate() }

    /// Ручки (mod): p1–p3 — 0…1, decay — мс.
    @inline(__always) func set(note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, decay: Double) {
        note = n
        t1 = q1
        t2 = q2
        t3 = q3
        td = decay
    }

    /// Нота в кадре now (абсолютный кадр), tau — время дорожки с дрейфом на этот кадр.
    func trigger(engine e: Int, note n: Double, _ q1: Double, _ q2: Double, _ q3: Double, decay: Double,
                 now: Double, tau: Double) {
        // DRUM монофонична: новый удар в тот же слот, хвост прошлого гаснет за drumDeclick.
        dc = e == Jambo.drum && engine == Jambo.drum ? last : 0
        engine = e
        set(note: n, q1, q2, q3, decay: decay)
        // Новая нота — ручки сразу на своих местах (сглаживание — только для смены на лету).
        s1 = t1
        s2 = t2
        s3 = t3
        sd = td
        t = 0
        p1 = 0
        m1 = 0
        m2 = 0
        hb.update(repeating: 0, count: Jambo.hbLen * 2)
        // Фаза новой ноты — как у генератора, который бежит непрерывно (frac(f·t)); оба осциллятора ANALOG — из одной точки.
        let f = 440 * pow(2, (note - 69) / 12) / sr
        let det = Jambo.analogDetune / 2 * s2 * s2
        a1 = jFrac(f * pow(2, det / 1200) * tau)
        a2 = jFrac(f * pow(2, -det / 1200) * tau)
        aSub = jFrac(0.5 * f * tau)
        tri1 = jTriAt(a1)
        tri2 = jTriAt(a2)
        wCur = Jambo.waveIndex(t1)
        wPrev = wCur
        wMix = 1
        pc = jFrac(f * now)
        pm = jFrac(Jambo.fmRatio(s1) * f * now)
        fade = 0
    }

    /// Кусок n кадров (n ≤ 24) в out; driftRatio — множитель дрейфа дорожки (ANALOG).
    func render(_ out: UnsafeMutablePointer<Float>, _ n: Int, driftRatio: Double) {
        let k = 1 - exp(-Double(n) / (Jambo.smooth * sr))
        s1 += (t1 - s1) * k
        s2 += (t2 - s2) * k
        s3 += (t3 - s3) * k
        sd += (td - sd) * k
        if engine == Jambo.drum {
            drum(out, n)
        } else if engine == Jambo.analog {
            analog(out, n, driftRatio)
        } else if engine == Jambo.fm {
            fm(out, n)
        } else {
            out.update(repeating: 0, count: n)
        }
        // Начало ноты ANALOG и FM — плавно за fadeIn кадров (после фильтра децимации); у DRUM свой старт.
        if fade < Jambo.fadeIn && engine != Jambo.drum {
            var i = 0
            while i < n && fade < Jambo.fadeIn {
                fade += 1
                out[i] = Float(Double(out[i]) * Double(fade) / Double(Jambo.fadeIn))
                i += 1
            }
        }
    }

    // MARK: — DRUM: синус со свипом высоты + клик → мягкий клиппер.

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
        // DRIVE: клик (до 1.0) и tanh (запас 1 → 12), компенсация.
        let dg = 1 + 11 * s3
        let comp = Jambo.drumSine / tanh(dg * Jambo.drumSine)
        let click = s3
        let clickLen = Jambo.drumClick * sr
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

    // MARK: — ANALOG: два осциллятора PolyBLEP + суб, ×2 передискретизация и полуполосный фильтр.

    @inline(__always) private func analog(_ out: UnsafeMutablePointer<Float>, _ n: Int, _ ratio: Double) {
        let sr2 = sr * 2
        let sine = UnsafePointer(tables.sine)
        let f0 = 440 * pow(2, (note - 69) / 12) * ratio
        // DETUNE: OSC1 вверх, OSC2 вниз, в сумме 0…60 центов по кривой x².
        let det = Jambo.analogDetune / 2 * s2 * s2
        let dt1 = Swift.min(0.45, f0 * pow(2, det / 1200) / sr2)
        let dt2 = Swift.min(0.45, f0 * pow(2, -det / 1200) / sr2)
        let dts = f0 * 0.5 / sr2
        // WAVE — ступенчатая (пункт по ручке, без сглаживания); смена пункта — кроссфейд форм за 5 мс.
        let idx = Jambo.waveIndex(t1)
        if idx != wCur {
            wPrev = wCur
            wCur = idx
            wMix = 0
        }
        let cur = wCur, prev = wPrev
        let gCur = Double(tables.shapeGain[cur]), gPrev = Double(tables.shapeGain[prev])
        let xfStep = 1 / (Jambo.analogWaveXf * sr2)
        var mix = wMix
        // SUB: 0…100 % по амплитуде, общий уровень компенсируется.
        let sub = s3
        let gain = Jambo.analogOut / (1 + 0.5 * sub)
        let leak = 1 - 20 / sr2
        var o1 = a1, o2 = a2, os = aSub, tr1 = tri1, tr2 = tri2, hp = hbPos
        let buf = hb, len = Jambo.hbLen
        let kIdx = tables.hbIdx, kK = tables.hbK, kN = tables.hbN
        var i = 0
        while i < n {
            var j = 0
            while j < 2 {
                // Треугольник — интеграл квадрата, сдвинутого на четверть периода (пик на φ = 0.25).
                let b1 = o1 < 0.75 ? o1 + 0.25 : o1 - 0.75, b2 = o2 < 0.75 ? o2 + 0.25 : o2 - 0.75
                tr1 = tr1 * leak + 4 * dt1 * ((b1 < 0.5 ? 1 : -1) + jBlep(b1, dt1) - jBlep(b1 < 0.5 ? b1 + 0.5 : b1 - 0.5, dt1))
                tr2 = tr2 * leak + 4 * dt2 * ((b2 < 0.5 ? 1 : -1) + jBlep(b2, dt2) - jBlep(b2 < 0.5 ? b2 + 0.5 : b2 - 0.5, dt2))
                var osc = 0.5 * gCur * (jShapeAt(sine, cur, o1, dt1, tr1) + jShapeAt(sine, cur, o2, dt2, tr2))
                if mix < 1 {
                    mix = Swift.min(1, mix + xfStep)
                    let old = 0.5 * gPrev * (jShapeAt(sine, prev, o1, dt1, tr1) + jShapeAt(sine, prev, o2, dt2, tr2))
                    osc = old + (osc - old) * mix
                }
                let sb = (os < 0.5 ? 1 : -1) + jBlep(os, dts) - jBlep(os < 0.5 ? os + 0.5 : os - 0.5, dts)
                let y = Float(gain * (osc + sub * sb))
                buf[hp] = y
                buf[hp + len] = y
                hp = hp + 1 == len ? 0 : hp + 1
                o1 += dt1
                if o1 >= 1 { o1 -= 1 }
                o2 += dt2
                if o2 >= 1 { o2 -= 1 }
                os += dts
                if os >= 1 { os -= 1 }
                j += 1
            }
            var acc = 0.0
            var q = 0
            while q < kN {
                acc += Double(kK[q]) * Double(buf[hp + kIdx[q]])
                q += 1
            }
            out[i] = Float(acc)
            i += 1
        }
        wMix = mix
        a1 = o1
        a2 = o2
        aSub = os
        tri1 = jFlush(tr1)
        tri2 = jFlush(tr2)
        hbPos = hp
        t += Double(n)
    }

    // MARK: — FM: несущая (ratio 1) и модулятор (RATIO) с обратной связью, ×2 передискретизация.

    @inline(__always) private func fm(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sine = UnsafePointer(tables.sine)
        let f0 = 440 * pow(2, (note - 69) / 12)
        let ratio = Jambo.fmRatio(s1)
        let idxNorm = pow(s2, 1.5)
        // Индекс в радианах → в долях периода.
        let index = Jambo.fmIndex * idxNorm / (2 * Double.pi)
        let fb = Jambo.fmFeedback * idxNorm
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
        let kIdx = tables.hbIdx, kK = tables.hbK, kN = tables.hbN
        let fmOut = Jambo.fmOut
        var i = 0
        while i < n {
            var j = 0
            while j < 2 {
                let mod = jSin(sine, md + fb * 0.5 * (x1 + x2))
                x2 = x1
                x1 = mod
                let y = Float(jSin(sine, c + index * env * mod))
                md += ratio * dt
                if md >= 1 { md -= md.rounded(.down) }
                c += dt
                if c >= 1 { c -= 1 }
                buf[hp] = y
                buf[hp + len] = y
                hp = hp + 1 == len ? 0 : hp + 1
                j += 1
            }
            // Децимация: свёртка с полуполосным фильтром (только ненулевые отводы).
            var acc = 0.0
            var q = 0
            while q < kN {
                acc += Double(kK[q]) * Double(buf[hp + kIdx[q]])
                q += 1
            }
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
}
