import Foundation

// Ударные JAMbo (S12, этап 3): SNARE, HAT, CLAP, PERC (20–23). Затухают сами, монофоничны (слот 0): новый удар
// обрывает прошлый — хвост гаснет за ~2 мс (добавкой последнего отсчёта, как у KICK). Выход — через tanh (пик < 0 dBFS).
// Горячие циклы — без вызовов из других файлов, состояние — в локальных переменных (отладочная сборка Playgrounds).

/// Синус по фазе в периодах (таблица 4096 с линейной интерполяцией).
@_transparent private func dSin(_ table: UnsafePointer<Float>, _ ph: Double) -> Double {
    var x = ph - ph.rounded(.down)
    x *= 4096
    let i = Int(x)
    let a = Double(table[i]), b = Double(table[i + 1])
    return a + (b - a) * (x - Double(i))
}

/// PolyBLEP: поправка у разрыва (t — фаза 0…1, dt — шаг фазы).
@_transparent private func dBlep(_ t0: Double, _ dt: Double) -> Double {
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

@_transparent private func dFlush(_ x: Double) -> Double { (x > 1e-20 || x < -1e-20) ? x : 0 }

/// xorshift32 (состояние — Int 0…2³²−1), как JamboDrift.xorshift — здесь, чтобы не звать другой файл на отсчёт.
@_transparent private func dXor(_ r0: Int) -> Int {
    var r = r0
    r ^= (r << 13) & 0xFFFF_FFFF
    r ^= r >> 17
    r ^= (r << 5) & 0xFFFF_FFFF
    return r
}

/// Коэффициенты фильтра состояний (TPT SVF): a1, a2, a3 и k = 1/Q.
private struct DSvf {
    var a1 = 0.0, a2 = 0.0, a3 = 0.0, k = 1.0

    init() {}

    init(_ hz: Double, _ q: Double, _ sr: Double) {
        let f = Swift.min(hz, sr * 0.45)
        let g = tan(Double.pi * f / sr)
        k = 1 / q
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }
}

final class JamboDrumVoice {
    private let tables: JamboTables
    private let sr: Double
    private(set) var engine = Jambo.snare
    // Цели ручек и сглаженные значения (5 мс).
    private var t1 = 0.5, t2 = 0.5, t3 = 0.5, t4 = 0.5, td = 300.0
    private var s1 = 0.5, s2 = 0.5, s3 = 0.5, s4 = 0.5, sd = 300.0
    private var t = 0.0
    private var rnd = 12345
    /// Стык при ретриге: хвост прошлого удара; last — последний отсчёт (0 — голос молчал).
    private var dc = 0.0
    var last = 0.0
    // Фазы (SNARE: 2, HAT: 6, PERC: 6).
    private let ph: UnsafeMutablePointer<Double>
    // Фильтры: состояния ic1, ic2 (до 3 фильтров).
    private let ic: UnsafeMutablePointer<Double>
    // HAT: ×2 передискретизация — буфер полуполосного фильтра.
    private let hb: UnsafeMutablePointer<Float>
    private var hbPos = 0
    // CLAP: времена вспышек (кадры), их число; огибающие кластера и хвоста.
    private let burstAt: UnsafeMutablePointer<Double>
    private var bursts = 4
    private var envC = 0.0, envT = 0.0
    // PERC: толчок — однополюсный фильтр шума.
    private var lp = 0.0

    init(tables: JamboTables, sampleRate: Double) {
        self.tables = tables
        sr = sampleRate
        ph = .allocate(capacity: 6)
        ph.initialize(repeating: 0, count: 6)
        ic = .allocate(capacity: 6)
        ic.initialize(repeating: 0, count: 6)
        hb = .allocate(capacity: Jambo.hbLen * 2)
        hb.initialize(repeating: 0, count: Jambo.hbLen * 2)
        burstAt = .allocate(capacity: 6)
        burstAt.initialize(repeating: 0, count: 6)
    }

    deinit {
        ph.deallocate()
        ic.deallocate()
        hb.deallocate()
        burstAt.deallocate()
    }

    /// Белый шум −1…1 (xorshift32).
    @inline(__always) private func noise() -> Double {
        rnd = dXor(rnd)
        return Double(rnd) / 2147483648 - 1
    }

    @inline(__always) func set(_ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double, decay: Double) {
        t1 = q1
        t2 = q2
        t3 = q3
        t4 = q4
        td = decay
    }

    /// Удар движка e; прошлый удар того же голоса гаснет за ~2 мс.
    func trigger(engine e: Int, _ q1: Double, _ q2: Double, _ q3: Double, _ q4: Double, decay: Double) {
        dc = last
        engine = e
        set(q1, q2, q3, q4, decay: decay)
        s1 = t1
        s2 = t2
        s3 = t3
        s4 = t4
        sd = td
        t = 0
        ph.update(repeating: 0, count: 6)
        ic.update(repeating: 0, count: 6)
        hb.update(repeating: 0, count: Jambo.hbLen * 2)
        hbPos = 0
        lp = 0
        if e == Jambo.hat {
            // Фазы квадратов — разные (как у свободно бегущих генераторов 808).
            var k = 0
            while k < 6 {
                rnd = dXor(rnd)
                ph[k] = Double(rnd) / 4294967296
                k += 1
            }
        }
        if e == Jambo.clap { planBursts() }
        envC = 0
        envT = 0
    }

    /// CLAP: вспышки по BURSTS и SPREAD (выше 60 % — случайный разброс до ±40 %).
    private func planBursts() {
        bursts = Swift.min(6, Swift.max(1, Int(t2 * 6) + 1))
        let gap = (Jambo.clapGapMin + (Jambo.clapGapMax - Jambo.clapGapMin) * pow(s3, 1.2)) / 1000 * sr
        let jitter = s3 > 0.6 ? 0.4 * (s3 - 0.6) / 0.4 : 0
        var at = 0.0
        var k = 0
        while k < bursts {
            burstAt[k] = at
            let r = noise()
            at += gap * (1 + jitter * r)
            k += 1
        }
    }

    /// Кусок n кадров (n ≤ 24).
    func render(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let k = 1 - exp(-Double(n) / (Jambo.smooth * sr))
        s1 += (t1 - s1) * k
        s2 += (t2 - s2) * k
        s3 += (t3 - s3) * k
        s4 += (t4 - s4) * k
        sd += (td - sd) * k
        if engine == Jambo.snare {
            snare(out, n)
        } else if engine == Jambo.hat {
            hat(out, n)
        } else if engine == Jambo.clap {
            clap(out, n)
        } else {
            perc(out, n)
        }
    }

    /// Выход: стык ретрига (+ хвост прошлого удара) → tanh; last — для следующего стыка.
    @inline(__always) private func finish(_ out: UnsafeMutablePointer<Float>, _ i: Int, _ x: Double, _ d: inout Double,
                                          _ dDc: Double) {
        let y = tanh(x + d)
        out[i] = Float(y)
        last = y
        d *= dDc
    }

    // MARK: — SNARE: два синуса корпуса (f, 1.8·f) с падением высоты + шум через полосовой.

    @inline(__always) private func snare(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sine = UnsafePointer(tables.sine)
        let f = 120 * pow(400.0 / 120, s1)
        let dec = Swift.min(800, Swift.max(30, sd)) / 1000
        let tauN = dec / 6.9, tauB = tauN * 0.6
        let semis = 12 * s4
        let tauS = (0.010 + 0.020 * s4) / 3
        let ang = s2 * Double.pi / 2
        let gB = cos(ang), gN = sin(ang) * 2.2
        let fl = DSvf(800 * pow(10, s3), 0.8, sr)
        let click = 0.6 * s4, clickLen = 0.001 * sr
        let dEnvN = exp(-1 / (tauN * sr)), dEnvB = exp(-1 / (tauB * sr)), dSw = exp(-1 / (tauS * sr))
        let dDc = exp(-1 / (0.002 * sr))
        var tt = t
        var envN = exp(-tt / (tauN * sr)), envB = exp(-tt / (tauB * sr)), sw = exp(-tt / (tauS * sr))
        var p0 = ph[0], p1 = ph[1], c1 = ic[0], c2 = ic[1], d = dc
        let ln2 = 0.057762265
        var i = 0
        while i < n {
            let fb = f * exp(ln2 * semis * sw)
            p0 += fb / sr
            if p0 >= 1 { p0 -= 1 }
            p1 += 1.8 * fb / sr
            if p1 >= 1 { p1 -= 1 }
            var body = envB * (dSin(sine, p0) + 0.5 * dSin(sine, p1)) / 1.5
            if tt < clickLen { body += click * (1 - tt / clickLen) }
            // Шум: полосовой (TPT SVF).
            let x = noise()
            let v3 = x - c2
            let v1 = fl.a1 * c1 + fl.a2 * v3
            let v2 = c2 + fl.a2 * c1 + fl.a3 * v3
            c1 = 2 * v1 - c1
            c2 = 2 * v2 - c2
            finish(out, i, gB * body + gN * envN * v1, &d, dDc)
            envN *= dEnvN
            envB *= dEnvB
            sw *= dSw
            tt += 1
            i += 1
        }
        ph[0] = p0
        ph[1] = p1
        ic[0] = dFlush(c1)
        ic[1] = dFlush(c2)
        dc = dFlush(d)
        t = tt
    }

    // MARK: — HAT (808): шесть квадратов (×2, PolyBLEP) или шум → два полосовых → ФВЧ.

    @inline(__always) private func hat(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sr2 = sr * 2
        let tune = pow(2, 2 * s1 - 1)
        let spread = 2 * s2
        let tone = pow(2, 2 * s3 - 1)
        let ang = s4 * Double.pi / 2
        let gM = cos(ang), gN = sin(ang) * 0.6
        let dec = Swift.min(1500, Swift.max(20, sd)) / 1000
        let dEnv = exp(-1 / (dec / 6.9 * sr))
        let dDc = exp(-1 / (0.002 * sr))
        // Шаги фаз шести квадратов (по ряду 808, разнос — степень отношений к среднему тону).
        let m = Jambo.hatMean
        let dt0 = Swift.min(0.45, tune * m * pow(205.3 / m, spread) / sr2)
        let dt1 = Swift.min(0.45, tune * m * pow(304.4 / m, spread) / sr2)
        let dt2 = Swift.min(0.45, tune * m * pow(369.6 / m, spread) / sr2)
        let dt3 = Swift.min(0.45, tune * m * pow(522.7 / m, spread) / sr2)
        let dt4 = Swift.min(0.45, tune * m * pow(540.0 / m, spread) / sr2)
        let dt5 = Swift.min(0.45, tune * m * pow(800.0 / m, spread) / sr2)
        let b1 = DSvf(3440 * tone, 3, sr2), b2 = DSvf(7100 * tone, 3, sr2), hpf = DSvf(Swift.min(18000, 5500 * tone), 0.7, sr2)
        var q0 = ph[0], q1 = ph[1], q2 = ph[2], q3 = ph[3], q4 = ph[4], q5 = ph[5]
        var c0 = ic[0], c1 = ic[1], c2 = ic[2], c3 = ic[3], c4 = ic[4], c5 = ic[5]
        var env = exp(-t / (dec / 6.9 * sr)), d = dc, hp = hbPos
        let buf = hb, len = Jambo.hbLen
        let kIdx = tables.hbIdx, kK = tables.hbK, kN = tables.hbN
        var i = 0
        while i < n {
            var j = 0
            while j < 2 {
                var sq = (q0 < 0.5 ? 1.0 : -1.0) + dBlep(q0, dt0) - dBlep(q0 < 0.5 ? q0 + 0.5 : q0 - 0.5, dt0)
                sq += (q1 < 0.5 ? 1.0 : -1.0) + dBlep(q1, dt1) - dBlep(q1 < 0.5 ? q1 + 0.5 : q1 - 0.5, dt1)
                sq += (q2 < 0.5 ? 1.0 : -1.0) + dBlep(q2, dt2) - dBlep(q2 < 0.5 ? q2 + 0.5 : q2 - 0.5, dt2)
                sq += (q3 < 0.5 ? 1.0 : -1.0) + dBlep(q3, dt3) - dBlep(q3 < 0.5 ? q3 + 0.5 : q3 - 0.5, dt3)
                sq += (q4 < 0.5 ? 1.0 : -1.0) + dBlep(q4, dt4) - dBlep(q4 < 0.5 ? q4 + 0.5 : q4 - 0.5, dt4)
                sq += (q5 < 0.5 ? 1.0 : -1.0) + dBlep(q5, dt5) - dBlep(q5 < 0.5 ? q5 + 0.5 : q5 - 0.5, dt5)
                let x = gM * sq / 6 + gN * noise()
                // Два полосовых параллельно, затем ФВЧ.
                var v3 = x - c1
                var v1 = b1.a1 * c0 + b1.a2 * v3
                var v2 = c1 + b1.a2 * c0 + b1.a3 * v3
                c0 = 2 * v1 - c0
                c1 = 2 * v2 - c1
                let bp1 = v1
                v3 = x - c3
                v1 = b2.a1 * c2 + b2.a2 * v3
                v2 = c3 + b2.a2 * c2 + b2.a3 * v3
                c2 = 2 * v1 - c2
                c3 = 2 * v2 - c3
                let y = bp1 + v1
                v3 = y - c5
                v1 = hpf.a1 * c4 + hpf.a2 * v3
                v2 = c5 + hpf.a2 * c4 + hpf.a3 * v3
                c4 = 2 * v1 - c4
                c5 = 2 * v2 - c5
                let h = y - hpf.k * v1 - v2
                let z = Float(h)
                buf[hp] = z
                buf[hp + len] = z
                hp = hp + 1 == len ? 0 : hp + 1
                q0 += dt0
                if q0 >= 1 { q0 -= 1 }
                q1 += dt1
                if q1 >= 1 { q1 -= 1 }
                q2 += dt2
                if q2 >= 1 { q2 -= 1 }
                q3 += dt3
                if q3 >= 1 { q3 -= 1 }
                q4 += dt4
                if q4 >= 1 { q4 -= 1 }
                q5 += dt5
                if q5 >= 1 { q5 -= 1 }
                j += 1
            }
            var acc = 0.0
            var q = 0
            while q < kN {
                acc += Double(kK[q]) * Double(buf[hp + kIdx[q]])
                q += 1
            }
            finish(out, i, Jambo.hatOut * env * acc, &d, dDc)
            env *= dEnv
            i += 1
        }
        ph[0] = q0
        ph[1] = q1
        ph[2] = q2
        ph[3] = q3
        ph[4] = q4
        ph[5] = q5
        ic[0] = dFlush(c0)
        ic[1] = dFlush(c1)
        ic[2] = dFlush(c2)
        ic[3] = dFlush(c3)
        ic[4] = dFlush(c4)
        ic[5] = dFlush(c5)
        hbPos = hp
        dc = dFlush(d)
        t += Double(n)
    }

    // MARK: — CLAP: шум → полосовой Q≈2; кластер вспышек и хвост «комнаты».

    @inline(__always) private func clap(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let fl = DSvf(Jambo.clapTone(s1), 2, sr)
        let dec = Swift.min(1200, Swift.max(50, sd)) / 1000
        let dC = exp(-1 / (0.004 * sr)), dT = exp(-1 / (dec / 6.9 * sr))
        let dDc = exp(-1 / (0.002 * sr))
        let tail = s4
        let nb = bursts
        let lastAt = burstAt[nb - 1]
        var c1 = ic[0], c2 = ic[1], eC = envC, eT = envT, d = dc
        var tt = t
        var i = 0
        while i < n {
            // Начало вспышки — огибающая кластера с 1; после последней — ещё и хвост.
            var k = 0
            while k < nb {
                if tt >= burstAt[k] && tt < burstAt[k] + 1 { eC = 1 }
                k += 1
            }
            if tt >= lastAt && tt < lastAt + 1 { eT = tail }
            let x = noise()
            let v3 = x - c2
            let v1 = fl.a1 * c1 + fl.a2 * v3
            let v2 = c2 + fl.a2 * c1 + fl.a3 * v3
            c1 = 2 * v1 - c1
            c2 = 2 * v2 - c2
            finish(out, i, Jambo.clapOut * (eC + eT) * v1, &d, dDc)
            eC *= dC
            eT *= dT
            tt += 1
            i += 1
        }
        ic[0] = dFlush(c1)
        ic[1] = dFlush(c2)
        envC = dFlush(eC)
        envT = dFlush(eT)
        dc = dFlush(d)
        t = tt
    }

    // MARK: — PERC: шесть затухающих синусов (моды по MATERIAL) + шумовой толчок (HIT), падение высоты (BEND).

    @inline(__always) private func perc(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sine = UnsafePointer(tables.sine)
        let f = 60 * pow(2000.0 / 60, s1)
        let dec = Swift.min(2000, Swift.max(30, sd)) / 1000
        let tau0 = dec / 6.9
        let semis = 12 * s3
        let dSw = exp(-1 / (0.020 * sr))
        let hit = s4
        let hitLen = (0.008 - 0.007 * hit) * sr
        let lpK = 1 - exp(-2 * Double.pi * (1000 + 9000 * hit) / sr)
        let dDc = exp(-1 / (0.002 * sr))
        // Моды: отношения и уровни по MATERIAL; выше 20 кГц — без звука; затухание короче у высоких.
        let m0 = Jambo.percModeAt(s2, hit, 0), m1 = Jambo.percModeAt(s2, hit, 1), m2 = Jambo.percModeAt(s2, hit, 2)
        let m3 = Jambo.percModeAt(s2, hit, 3), m4 = Jambo.percModeAt(s2, hit, 4), m5 = Jambo.percModeAt(s2, hit, 5)
        let r1 = m1.r, r2 = m2.r, r3 = m3.r, r4 = m4.r, r5 = m5.r
        let g0 = m0.a
        var g1 = m1.a, g2 = m2.a, g3 = m3.a, g4 = m4.a, g5 = m5.a
        let top = 20000 / f
        if r1 > top { g1 = 0 }
        if r2 > top { g2 = 0 }
        if r3 > top { g3 = 0 }
        if r4 > top { g4 = 0 }
        if r5 > top { g5 = 0 }
        let norm = 1 / Swift.max(1, g0 + g1 + g2 + g3 + g4 + g5) * 1.6
        let tt0 = t
        var e0 = g0 * exp(-tt0 / (tau0 * sr)), e1 = g1 * exp(-tt0 / (tau0 / r1.squareRoot() * sr))
        var e2 = g2 * exp(-tt0 / (tau0 / r2.squareRoot() * sr)), e3 = g3 * exp(-tt0 / (tau0 / r3.squareRoot() * sr))
        var e4 = g4 * exp(-tt0 / (tau0 / r4.squareRoot() * sr)), e5 = g5 * exp(-tt0 / (tau0 / r5.squareRoot() * sr))
        let k0 = exp(-1 / (tau0 * sr)), k1 = exp(-r1.squareRoot() / (tau0 * sr)), k2 = exp(-r2.squareRoot() / (tau0 * sr))
        let k3 = exp(-r3.squareRoot() / (tau0 * sr)), k4 = exp(-r4.squareRoot() / (tau0 * sr))
        let k5 = exp(-r5.squareRoot() / (tau0 * sr))
        var p0 = ph[0], p1 = ph[1], p2 = ph[2], p3 = ph[3], p4 = ph[4], p5 = ph[5]
        var sw = exp(-tt0 / (0.020 * sr)), l = lp, d = dc, tt = tt0
        let ln2 = 0.057762265
        var i = 0
        while i < n {
            let df = f * exp(ln2 * semis * sw) / sr
            p0 += df
            p1 += df * r1
            p2 += df * r2
            p3 += df * r3
            p4 += df * r4
            p5 += df * r5
            var y = e0 * dSin(sine, p0) + e1 * dSin(sine, p1) + e2 * dSin(sine, p2)
            y += e3 * dSin(sine, p3) + e4 * dSin(sine, p4) + e5 * dSin(sine, p5)
            // Толчок: шум через однополюсный ФНЧ (мягкая — длинный тёмный, палка — короткий яркий) и щелчок.
            if tt < hitLen {
                l += (noise() - l) * lpK
                y += l * (1 - tt / hitLen) * (0.5 + 0.5 * hit)
                if tt < 0.0003 * sr { y += 0.5 * hit }
            }
            finish(out, i, norm * y, &d, dDc)
            e0 *= k0
            e1 *= k1
            e2 *= k2
            e3 *= k3
            e4 *= k4
            e5 *= k5
            sw *= dSw
            tt += 1
            i += 1
        }
        ph[0] = p0 - p0.rounded(.down)
        ph[1] = p1 - p1.rounded(.down)
        ph[2] = p2 - p2.rounded(.down)
        ph[3] = p3 - p3.rounded(.down)
        ph[4] = p4 - p4.rounded(.down)
        ph[5] = p5 - p5.rounded(.down)
        lp = dFlush(l)
        dc = dFlush(d)
        t = tt
    }
}
