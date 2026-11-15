import Foundation

// Иконки ударных KICK, SNARE, HAT, CLAP, PERC (16, 20–23) — секция «final mix» прототипа
// (docs/icons/prototype/engine-previews-prototype.html). h, t, m, q — ручки 1.1–1.4, d — Decay (0…1), hx — подсветка
// удара. KICK: одна волна симметрично серой оси; белое — сам удар с коротким спадом (k = 9), серое — хвост того же
// сигнала со спадом от Decay (два прохода одного генератора). SNARE, PERC: одна настоящая волна (видно число волн),
// удар — серый всплеск под её началом, Decay — длина звука.

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

    /// Огибающая SNARE и PERC: звук кончается на 35…100 % ширины (Decay), спадает плавно, чтобы волны было видно.
    static func drumEnv(_ u: Double, _ d: Double) -> Double {
        return pow(clamp(1 - u / lerp(0.35, 1, d)), 1.6)
    }

    /// Серый удар SNARE и PERC: гладкий симметричный всплеск от левого края, сужаясь уходит в волну. a — высота
    /// (доля amp), w — насколько далеко тянется (px); по 41 точке сверху и снизу. Тихий — нет элемента.
    static func drumBurst(y0: Double, amp: Double, _ a: Double, _ w: Double) -> [IconElement] {
        if a < 0.01 { return [] }
        func f(_ x: Double) -> Double {
            return a * amp * (1 - exp(-(x - x0) / 0.5)) * exp(-pow((x - x0) / w, 1.3))
        }
        var cmds: [IconCmd] = [.move(x0, y0)]
        for i in 0...40 {
            let x = x0 + (5 * w * Double(i)) / 40
            cmds.append(.line(x, Swift.max(1.5, y0 - f(x))))
        }
        for i in stride(from: 40, through: 0, by: -1) {
            let x = x0 + (5 * w * Double(i)) / 40
            cmds.append(.line(x, Swift.min(62.5, y0 + f(x))))
        }
        cmds.append(.close)
        return [IconElement(cmds, fill: true, ink: .secondary)]
    }

    /// SNARE: одна волна корпуса — сколько волн — TUNE, SNAPPY — волна переходит в шум, TONE — зерно шума (крупные
    /// бугры ↔ мелкая рябь), PUNCH — первые волны сжаты и серый щелчок под началом; Decay — длина звука.
    static func snareIcon(_ v: IconValues, _ hx: Double?) -> [IconElement] {
        let wb = cos(v.t * Double.pi / 2), wn = sin(v.t * Double.pi / 2)
        let cyc = 3 * pow(3, v.h), hold = 8 * pow(1.2 / 8, clamp(v.m))
        var ph = 0.0
        let a = gen { u, i in
            ph += (cyc * (1 + 2.5 * v.q * exp(-u * 20)) * tau) / ns
            let nn = 0.85 * clamp(1.2 * nzi(Double(i) / hold), -1, 1)
            return clamp(wb * sin(ph) + wn * nn, -1, 1) * drumEnv(u, v.d)
        }
        return [axis(32)] + drumBurst(y0: 32, amp: 25, 1.2 * v.q, 2.6)
            + [lane(a, IconLane(y0: 32, amp: 25, thin: true), hx)]
    }

    /// PERC: одна волна — сколько волн — TUNE; MATERIAL — что на волне: кожа — гладкая, дерево — рябь только в начале
    /// (сухой стук), металл — рваная рябь до конца (звон); BEND — первые волны сжаты; HIT — удар: колотушка — волна
    /// нарастает плавно над низким широким серым толчком, палка — сразу, серый щелчок высокий и узкий; Decay — длина.
    static func percIcon(_ v: IconValues, _ hx: Double?) -> [IconElement] {
        let cyc = 2.5 * pow(3.2, v.h), x = clamp(v.t)
        let rip = x < 0.5 ? lerp(0.05, 0.75, x * 2) : 0.75
        let rk = x < 0.5 ? lerp(10, 8, x * 2) : lerp(8, 0.8, (x - 0.5) * 2)
        let r1 = x < 0.5 ? lerp(2.3, 5.4, x * 2) : lerp(5.4, 3.7, (x - 0.5) * 2)
        let r2 = x < 0.5 ? lerp(2.9, 8.9, x * 2) : lerp(8.9, 5.3, (x - 0.5) * 2)
        let att = 0.16 * pow(1 - clamp(v.q), 1.5)
        var ph = 0.0
        let a = gen { u, _ in
            ph += (cyc * (1 + 1.6 * v.m * exp(-u * 9)) * tau) / ns
            let r = rip * exp(-u * rk) * (0.6 * sin(r1 * ph + 0.7) + 0.4 * sin(r2 * ph + 1.9))
            let sw = att > 0.001 ? sin((Double.pi / 2) * clamp(u / att)) : 1
            return clamp((sin(ph) + r) / (1 + 0.5 * rip), -1, 1) * drumEnv(u, v.d) * sw
        }
        return [axis(32)] + drumBurst(y0: 32, amp: 25, lerp(0.45, 1.2, v.q), lerp(9, 2, v.q))
            + [lane(a, IconLane(y0: 32, amp: 25, thin: true), hx)]
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
