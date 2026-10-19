import Foundation

// Иконки своих движков KICK, ANALOG, FM (16–18): перенос src/engineIcons.ts; KICK и ANALOG — с ручкой 1.4 (S12).
// d — Decay (у KICK — его своя шкала).

extension EngineIcons {
    /// KICK: затухающая волна — частота по PITCH (1.1), в начале выше на SWEEP (1.2), насыщение по DRIVE (1.3),
    /// длина затухания по Decay; в самом начале — вертикальная полоса клика, высота по CLICK (1.4).
    static func drumIcon(_ v: IconValues) -> [IconElement] {
        let d = v.d
        let g = 1 + 11 * v.m, cmp = 0.7 / tanh(g * 0.7), k = 4.5 - 3.5 * d
        var ph = 0.0
        let w = fx(6, 58, 240) { _, u in
            let f = (0.8 + 0.9 * v.h) * (1 + 9 * v.t * exp(-u * 14))
            ph += f * tau / 240 * 3
            return 32 - 22 * cmp * tanh(g * 0.7 * sin(ph) * exp(-u * k))
        }
        var els: [IconElement] = [IconElement(pts(w)), IconElement([.move(6, 32), .hTo(58)], op: 0.25)]
        if v.q > 0.02 {
            els.append(IconElement([.move(6, 32), .vTo(32 - 26 * clamp(v.q))]))
        }
        return els
    }

    /// ANALOG: сверху волна A (пункт WAVE A, 1.1), снизу — B (WAVE B, 1.2), расходится по фазе с DETUNE (1.3);
    /// прозрачность A и B — по MIX (1.4): у преобладающего осциллятора — полная.
    static func analogIcon(_ v: IconValues) -> [IconElement] {
        func shp(_ k: Int, _ p0: Double) -> Double {
            let p = p0 - p0.rounded(.down)
            if k == 0 { return sin(tau * p) }
            if k == 1 { return 1 - 4 * abs(p < 0.75 ? p - 0.25 : p - 1.25) }
            if k == 2 { return 1 - 2 * p }
            return p < 0.5 ? 1 : -1
        }
        let ka = Swift.min(3, Int((clamp(v.h) * 4).rounded(.down)))
        let kb = Swift.min(3, Int((clamp(v.t) * 4).rounded(.down)))
        let ang = clamp(v.q) * Double.pi / 2
        let ga = cos(ang), gb = sin(ang)
        let opA = 0.15 + 0.85 * ga / Swift.max(ga, gb), opB = 0.15 + 0.85 * gb / Swift.max(ga, gb)
        let dd = v.m * v.m
        let a = fx(6, 58, 200) { _, u in 20 - 10 * shp(ka, u * 2) }
        let b = fx(6, 58, 200) { _, u in 44 - 10 * shp(kb, u * 2 * (1 + 0.06 * dd) + 0.15 * dd) }
        return [IconElement(pts(a), op: opA < 0.999 ? opA : nil), IconElement(pts(b), op: opB < 0.999 ? opB : nil),
                IconElement([.move(6, 32), .hTo(58)], op: 0.25)]
    }

    /// FM: сверху модулятор (частота по RATIO, 1.1), ниже несущая с фазовой модуляцией: глубина по INDEX (1.2),
    /// спадает вдоль иконки по CONTOUR (1.3) и Decay; в углу — отношение.
    static func fmIcon(_ v: IconValues) -> [IconElement] {
        let r = Jambo.fmRatio(v.h)
        let idx = 2.5 * pow(clamp(v.t), 1.5)
        let k = v.m < 0.5 ? 2 * v.m : 1 + 8 * (v.m - 0.5)
        let dec = k * (1.6 - 1.3 * v.d)
        let car = fx(6, 58, 400) { _, u in
            let ph = u * 1.5
            return 38 - 14 * sin(tau * ph + idx * exp(-u * dec) * sin(tau * ph * r))
        }
        let modulator = fx(6, 58, 300) { _, u in 12 - 4 * sin(tau * u * 1.5 * r) }
        let whole = r >= 1 && abs(r - Double(round(r))) < 0.01
        let label = whole ? "×\(round(r))" : "×" + String(format: "%.1f", r)
        return [IconElement(pts(modulator), op: 0.5), IconElement(pts(car)), IconElement(text: label, x: 49, y: 61, size: 8)]
    }
}

extension EngineIcons {
    /// Кадр таблицы WTABLE в окне синта (renderTableFrame веба): POSITION — кадр (с интерполяцией между кадрами),
    /// WARP — изгиб и синхронизация фазы; уровень 0 мипмапа, 129 точек, линия нуля.
    public static func tableFrame(_ tb: WtTable, position pos: Double, warp: Double) -> [IconElement] {
        let size = tb.sizes[0]
        let data = tb.data[0]
        let fpos = pos * Double(tb.frames - 1)
        let fi = Swift.min(tb.frames - 2, Swift.max(0, Int(fpos.rounded(.down))))
        let ff = tb.frames > 1 ? fpos - Double(fi) : 0
        let rowB = tb.frames > 1 ? fi + 1 : fi
        let bend = 1 + 3 * Swift.min(1, warp * 2)
        let sync = warp > 0.5 ? 1 + 3 * (warp - 0.5) * 2 : 1
        let n = 128
        var pts: [(Double, Double)] = []
        for k in 0...n {
            var ph = Double(k) / Double(n) * sync
            ph = pow(ph - ph.rounded(.down), bend)
            let j = Swift.min(size - 1, Int((ph * Double(size)).rounded(.down)))
            let a = Double(data[fi * size + j]), b = Double(data[rowB * size + j])
            pts.append((4 + Double(k) / Double(n) * 56, 32 - 26 * (a + (b - a) * ff)))
        }
        return [IconElement([.move(4, 32), .hTo(60)], op: 0.25), IconElement(self.pts(pts))]
    }
}
