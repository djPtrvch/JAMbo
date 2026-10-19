import Foundation

// Иконки ударных JAMbo (S12, этап 3): SNARE, HAT, CLAP, PERC (20–23). h, t, m, q — ручки 1.1–1.4, d — Decay
// (0…1 по шкале ручки). Стиль — как у своих движков (одна линия, без подсветки частей).

extension EngineIcons {
    /// SNARE: снизу затухающая волна корпуса — сумма двух тонов f и 1.8·f (частота по TUNE, начало выше на PUNCH),
    /// сверху шумовая полоса
    /// (размах — SNAPPY, мелкость — TONE); длина — по Decay.
    static func snareIcon(_ v: IconValues) -> [IconElement] {
        let k = 4.5 - 3.5 * v.d
        var ph = 0.0
        let body = fx(6, 58, 300) { _, u in
            let f = (3 + 4 * v.h) * (1 + 2 * v.q * exp(-u * 18))
            ph += f * tau / 300
            let two = (sin(ph) + 0.5 * sin(1.8 * ph)) / 1.5
            return 44 - 13 * (1 - 0.4 * v.t) * two * exp(-u * k)
        }
        var rnd = IconRandom(7)
        let steps = 16 + Int(60 * clamp(v.m))
        let noise = fx(6, 58, steps) { _, u in 18 + 10 * v.t * (rnd.next() * 2 - 1) * exp(-u * k * 0.8) }
        return [IconElement(pts(body)), IconElement(pts(noise)), IconElement([.move(6, 44), .hTo(58)], op: 0.25)]
    }

    /// HAT: шесть вертикальных линий — частоты ряда 808 (положение — TUNE и SPREAD), при NOISE линии рвутся;
    /// под ними горб полосового фильтра (по TONE); снизу — длина хвоста (Decay).
    static func hatIcon(_ v: IconValues) -> [IconElement] {
        let base: [Double] = [205.3, 304.4, 369.6, 522.7, 540, 800]
        let spread = 2 * clamp(v.t)
        let shift = (2 * clamp(v.h) - 1) * 0.5
        var els: [IconElement] = []
        var rnd = IconRandom(11)
        for f in base {
            let lx = log2(f / Jambo.hatMean) * spread * 0.9 + shift
            let x = 32 + 22 * Swift.max(-1, Swift.min(1, lx / 1.4))
            if v.q < 0.05 {
                els.append(IconElement([.move(x, 8), .vTo(34)]))
            } else {
                // Шум: линия рвётся на куски со сдвигом — тем сильнее, чем больше NOISE.
                var y = 8.0
                while y < 34 {
                    let len = 3 + 6 * (1 - v.q)
                    let dx = (rnd.next() * 2 - 1) * 3 * v.q
                    els.append(IconElement([.move(x + dx, y), .vTo(Swift.min(34, y + len))]))
                    y += len + 2 * v.q
                }
            }
        }
        let c = 32 + 20 * (2 * clamp(v.m) - 1)
        let hump = fx(6, 58, 120) { x, _ in 50 - 10 * exp(-pow((x - c) / 7, 2)) }
        els.append(IconElement(pts(hump), op: 0.6))
        els.append(IconElement([.move(6, 58), .hTo(6 + 52 * clamp(v.d))], op: 0.5))
        return els
    }

    /// CLAP: вспышки-пики (число — BURSTS, промежутки — SPREAD, выше 60 % — неровные; ширина — по TONE),
    /// за ними затухающий хвост (высота — TAIL, длина — Decay).
    static func clapIcon(_ v: IconValues) -> [IconElement] {
        let n = Swift.min(6, Int(clamp(v.t) * 6) + 1)
        // Кластер — не шире 30 из 64 (с разбросом до ±40 %): иначе промежутки ужимаются.
        let gap0 = 3 + 6 * pow(clamp(v.m), 1.2)
        let room = 30 / Swift.max(1, (Double(n) * 3 + Double(n - 1) * gap0 * 1.4))
        let gap = gap0 * Swift.min(1, room)
        let jitter = v.m > 0.6 ? 0.4 * (v.m - 0.6) / 0.4 : 0
        let w = 3 - 2 * clamp(v.h)
        var rnd = IconRandom(5)
        var cmds: [IconCmd] = [.move(6, 44)]
        var x = 8.0
        for _ in 0..<n {
            cmds += [.line(x, 44), .line(x + w / 2, 12), .line(x + w, 44)]
            x += w + gap * (1 + jitter * (rnd.next() * 2 - 1))
        }
        let len = 10 + 40 * clamp(v.d)
        let tail = fx(x, Swift.min(58, Swift.max(x + 2, x + len)), 60) { _, u in 44 - 26 * v.q * exp(-u * 4) }
        cmds += pts(tail).dropFirst()
        return [IconElement(cmds), IconElement([.move(6, 44), .hTo(58)], op: 0.25)]
    }

    /// PERC: затухающая волна (частота — TUNE, в начале выше на BEND), справа — линии мод (расстановка — MATERIAL,
    /// высота — уровень), в самом начале — полоса удара (высота — HIT).
    static func percIcon(_ v: IconValues) -> [IconElement] {
        let k = 5 - 4 * v.d
        var ph = 0.0
        let w = fx(10, 40, 200) { _, u in
            let f = (1 + 3 * v.h) * (1 + 1.5 * v.m * exp(-u * 10))
            ph += f * tau / 200 * 2
            return 32 - 16 * sin(ph) * exp(-u * k)
        }
        var els: [IconElement] = [IconElement(pts(w)), IconElement([.move(10, 32), .hTo(40)], op: 0.25)]
        if v.q > 0.02 { els.append(IconElement([.move(10, 32), .vTo(32 - 26 * clamp(v.q))])) }
        for i in 0..<6 {
            let md = Jambo.percModeAt(v.t, v.q, i)
            let x = 46 + 12 * log(md.r) / log(19.0)
            els.append(IconElement([.move(x, 48), .vTo(48 - 30 * md.a)]))
        }
        return els
    }
}
