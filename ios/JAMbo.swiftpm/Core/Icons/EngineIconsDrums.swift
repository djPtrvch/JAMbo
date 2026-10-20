import Foundation

// Иконки ударных KICK, SNARE, HAT, CLAP, PERC (16, 20–23) — секция «final mix» прототипа
// (docs/icons/prototype/engine-previews-prototype.html). h, t, m, q — ручки 1.1–1.4, d — Decay (0…1), hx — подсветка
// удара. KICK, SNARE, PERC: одна волна симметрично серой оси; белое — сам удар с коротким спадом (k = 9), серое —
// хвост того же сигнала со спадом от Decay (два прохода одного генератора).

extension EngineIcons {
    /// Короткий спад белого удара у KICK, SNARE, PERC.
    static let hitDecay = 9.0

    /// Белый удар поверх серого хвоста: ось, хвост (спад tail), удар (спад hitDecay) с всплеском spike.
    static func hitTail(_ mk: (Double) -> [Double], tail: Double, spike: @escaping (Double) -> Double,
                        _ hx: Double?) -> [IconElement] {
        let back = IconLane(y0: 32, amp: 26, mirror: true, thin: true, ink: .secondary)
        let front = IconLane(y0: 32, amp: 26, mirror: true, thin: true, ext: spike)
        return [axis(32), lane(mk(tail), back, hx), lane(mk(hitDecay), front, hx)]
    }

    /// KICK: частота тела — PITCH, в начале выше на SWEEP, вершины сплющиваются по DRIVE, всплеск в начале — CLICK;
    /// серый хвост — Decay.
    static func kickIcon(_ v: IconValues, _ hx: Double?) -> [IconElement] {
        let gg = 1 + 11 * v.m
        let cmp = 0.7 / tanh(gg * 0.7)
        func mk(_ k: Double) -> [Double] {
            var ph = 0.0
            return gen { u, _ in
                let f = (0.8 + 0.9 * v.h) * (1 + 9 * v.t * exp(-u * 14))
                ph += (f * tau * 3) / ns
                return (cmp * tanh(gg * 0.7 * sin(ph) * exp(-u * k))) / 0.7
            }
        }
        return hitTail(mk, tail: 4.5 - 3.5 * v.d, spike: startSpike(0.55 * v.q, 1.3), hx)
    }

    /// SNARE: корпус (f и 1.8·f, частота — TUNE, начало выше и всплеск — PUNCH) смешан с шумом по SNAPPY;
    /// TONE — мелкость шума (медленный и ослабленный, без «пилы»); серый хвост — Decay.
    static func snareIcon(_ v: IconValues, _ hx: Double?) -> [IconElement] {
        let wb = cos(v.t * Double.pi / 2), wn = sin(v.t * Double.pi / 2)
        let hold = Double(sub) * (1.5 + 2.5 * (1 - clamp(v.m)))
        func mk(_ k: Double) -> [Double] {
            var p1 = 0.0
            return gen { u, i in
                let f = (2 + 3 * v.h) * (1 + 2 * v.q * exp(-u * 18))
                p1 += (f * tau) / ns
                let body = (exp(-u * k) * (0.62 * sin(p1) + 0.34 * sin(1.8 * p1))) / 0.96
                let noise = 0.75 * exp(-u * k * 0.8) * nzi(Double(i) / hold)
                return clamp(wb * body + wn * noise, -1, 1)
            }
        }
        return hitTail(mk, tail: 4.5 - 3.5 * v.d, spike: startSpike(0.3 * v.q, 1.3), hx)
    }

    /// PERC: сумма шести мод (MATERIAL — набор от кожи к дереву и металлу, HIT — яркость высоких мод и ширина
    /// всплеска), частота — TUNE, в начале выше на BEND; серый хвост — Decay, высокие моды гаснут быстрее.
    static func percIcon(_ v: IconValues, _ hx: Double?) -> [IconElement] {
        let f0 = lerp(2.5, 8, v.h)
        var mr = [Double](repeating: 0, count: 6), ma = [Double](repeating: 0, count: 6)
        var fade = [Double](repeating: 0, count: 6)
        var sum = 0.0
        for j in 0..<6 {
            let md = Jambo.percModeAt(v.t, v.q, j)
            mr[j] = md.r
            ma[j] = md.a
            sum += md.a
            fade[j] = clamp((150 - f0 * md.r * (1 + v.m)) / 30)
        }
        let norm = (1 / Swift.max(1, sum)) * 1.6 / 1.3
        func mk(_ k0: Double) -> [Double] {
            var ph = [Double](repeating: 0, count: 6)
            return gen { u, _ in
                let dr = 1 + v.m * exp(-u * 10)
                var s = 0.0
                for j in 0..<6 {
                    ph[j] += (f0 * mr[j] * dr * tau) / ns
                    s += fade[j] * ma[j] * sin(ph[j]) * exp(-u * k0 * mr[j].squareRoot())
                }
                return clamp(s * norm, -1, 1)
            }
        }
        let a = 0.25 + 0.5 * v.q, w = lerp(5, 1.2, v.q)
        let spike: (Double) -> Double = { x in a * exp(-(x - 4) / w) * 0.5 }
        // Хвост PERC — свой спад от Decay (5 − 4·d), как у звука.
        return hitTail(mk, tail: 5 - 4 * v.d, spike: spike, hx)
    }

    /// HAT: спектр, а не время — шесть линий ряда 808 (сдвиг — TUNE, растяжение — SPREAD, рваные по NOISE),
    /// высота линий — Decay (линии сплошные, без градиента), серый горб полосового фильтра — TONE.
    static func hatIcon(_ v: IconValues, _ hx: Double?) -> [IconElement] {
        let base: [Double] = [205.3, 304.4, 369.6, 522.7, 540, 800]
        let spread = 2 * clamp(v.t), shift = (2 * clamp(v.h) - 1) * 0.5
        let cc = 32 + 20 * (2 * clamp(v.m) - 1)
        var hump: [IconCmd] = [.move(4, 59)]
        for i in 0...56 {
            let x = 4 + Double(i)
            let z = (x - cc) / 8
            hump.append(.line(x, 59 - 3 - 11 * exp(-z * z)))
        }
        hump += [.line(60, 59), .close]
        var lines: [IconRect] = []
        let q = clamp(v.q)
        let bottom = 46.0, hh = 8 + 30 * clamp(v.d), top = bottom - hh, len = 3 + 6 * (1 - q)
        for (i, f) in base.enumerated() {
            let lx = log2(f / Jambo.hatMean) * spread * 0.9 + shift
            let x = 32 + 22 * Swift.max(-1, Swift.min(1, lx / 1.4))
            var sw = 0.0
            if let h = hx {
                let z = (x - h) / 7
                sw = 3 * exp(-z * z)
            }
            var y = top - sw
            var j = 0
            while y < bottom {
                let dx = rnd(i * 40 + j, 11) * 3 * q
                let y1 = Swift.min(bottom, y + len)
                // Кусок линии — сплошной (в прототипе к верху бледнел — решение пользователя: без градиента).
                lines.append(IconRect(x + dx - 0.6, y, 1.2, y1 - y + 0.05))
                y += len + 2 * q
                j += 1
            }
        }
        let els: [IconElement] = [IconElement(hump, fill: true, ink: .secondary), IconElement(rects: lines)]
        return els
    }

    /// CLAP: белые вспышки (число — BURSTS, новая вырастает плавно; промежутки — SPREAD, выше 60 % неровные;
    /// ширина — TONE), за ними серый хвост «комнаты» (высота — TAIL, длина — Decay).
    static func clapIcon(_ v: IconValues, _ hx: Double?) -> [IconElement] {
        let nEff = 1 + 5 * clamp(v.t)
        let gap0 = 3 + 6 * pow(clamp(v.m), 1.2)
        let room = 30 / Swift.max(1, nEff * 3 + (nEff - 1) * gap0 * 1.4)
        let gap = gap0 * Swift.min(1, room)
        let jit = v.m > 0.6 ? (0.4 * (v.m - 0.6)) / 0.4 : 0
        let w = 3 - 2 * clamp(v.h)
        var xs: [Double] = []
        var ends: [Double] = [5.5]
        for k in 0..<6 {
            xs.append(ends[k])
            ends.append(ends[k] + w + gap * (1 + jit * rnd(k, 5)))
        }
        let fl = Int(nEff.rounded(.down)), fr = nEff - Double(fl)
        let xT = lerp(ends[fl], ends[Swift.min(6, fl + 1)], fr)
        let len = 10 + 40 * clamp(v.d), tb = 0.45 * w + 0.35
        let burst = gen { u, _ in
            let x = x0 + u * (x1 - x0)
            var env = 0.0
            for k in 0..<6 {
                let p = x - xs[k]
                if p < 0 { continue }
                let ak = sstep(clamp(nEff - Double(k))) * (1 - 0.08 * Double(k))
                if ak > 0 { env = Swift.max(env, ak * exp(-p / tb)) }
            }
            return env
        }
        let tail = gen { u, _ in
            let x = x0 + u * (x1 - x0)
            return x >= xT ? 0.92 * v.q * exp((-4 * (x - xT)) / len) : 0
        }
        return [axis(32),
                lane(tail, IconLane(y0: 32, amp: 26, mirror: true, thin: true, ink: .secondary), hx),
                lane(burst, IconLane(y0: 32, amp: 26, mirror: true, thin: true), hx)]
    }
}
