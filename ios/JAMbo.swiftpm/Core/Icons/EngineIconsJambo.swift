import Foundation

// Иконки своих движков DRUM, ANALOG, FM (16–18): перенос src/engineIcons.ts. d — Decay (у DRUM — его своя шкала).

extension EngineIcons {
    /// DRUM: затухающая волна — частота по PITCH (1.1), в начале выше на SWEEP (1.2), насыщение по DRIVE (1.3),
    /// длина затухания по Decay.
    static func drumIcon(_ v: IconValues) -> [IconElement] {
        let d = v.d
        let g = 1 + 11 * v.m, cmp = 0.7 / tanh(g * 0.7), k = 4.5 - 3.5 * d
        var ph = 0.0
        let w = fx(6, 58, 240) { _, u in
            let f = (0.8 + 0.9 * v.h) * (1 + 9 * v.t * exp(-u * 14))
            ph += f * tau / 240 * 3
            return 32 - 22 * cmp * tanh(g * 0.7 * sin(ph) * exp(-u * k))
        }
        return [IconElement(pts(w)), IconElement([.move(6, 32), .hTo(58)], op: 0.25)]
    }

    /// ANALOG: волна по WAVE (1.1, пункт: синус, треугольник, пила, квадрат), копия расходится по фазе с DETUNE (1.2),
    /// снизу квадрат суба — размах по SUB (1.3).
    static func analogIcon(_ v: IconValues) -> [IconElement] {
        func shp(_ k: Int, _ p0: Double) -> Double {
            let p = p0 - p0.rounded(.down)
            if k == 0 { return sin(tau * p) }
            if k == 1 { return 1 - 4 * abs(p < 0.75 ? p - 0.25 : p - 1.25) }
            if k == 2 { return 1 - 2 * p }
            return p < 0.5 ? 1 : -1
        }
        let kind = Swift.min(3, Int((clamp(v.h) * 4).rounded(.down)))
        var els: [IconElement] = [IconElement(pts(fx(6, 58, 200) { _, u in 24 - 13 * shp(kind, u * 2) }))]
        if v.t > 0.02 {
            let tt = v.t * v.t
            els.append(IconElement(pts(fx(6, 58, 200) { _, u in 24 - 13 * shp(kind, u * 2 * (1 + 0.06 * tt) + 0.15 * tt) }),
                                   op: 0.5))
        }
        els.append(IconElement([.move(6, 51), .hTo(58)], op: 0.25))
        if v.m > 0.02 {
            els.append(IconElement(pts(fx(6, 58, 200) { _, u in 51 - 6 * v.m * shp(3, u) })))
        }
        return els
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
