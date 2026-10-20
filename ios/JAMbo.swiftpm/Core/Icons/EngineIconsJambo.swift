import Foundation

// Иконки синтов ANALOG, FM, WTABLE, SUB (17–19, 24) — версия v3 прототипа (объект V3 в
// docs/icons/prototype/engine-previews-prototype.html): колонки с минимальной толщиной, без серой оси, одним
// основным цветом с прозрачностью. h, t, m, q — ручки 1.1–1.4, d — Decay (0…1).

extension EngineIcons {
    /// ANALOG: сверху волна A (WAVE A, 1.1), снизу B (WAVE B, 1.2), при смене пункта форма перетекает; B уходит
    /// по фазе с DETUNE (1.3); прозрачность A и B — по MIX (1.4), у преобладающей — полная.
    static func analogIcon(_ v: IconValues) -> [IconElement] {
        let ang = clamp(v.q) * Double.pi / 2
        let ga = cos(ang), gb = sin(ang), mx = Swift.max(ga, gb)
        let dd = v.m * v.m, sc = still * 0.16
        let waves = [0, 1, 2, 3]
        let a = gen { u, _ in morph(waves, v.h * 3, u * 2 - sc) }
        let b = gen { u, _ in morph(waves, v.t * 3, u * 2 * (1 + 0.06 * dd) + 0.15 * dd - sc) }
        return [lane(a, IconLane(y0: 20, amp: 10.5, alpha: 0.15 + 0.85 * ga / mx)),
                lane(b, IconLane(y0: 44, amp: 10.5, alpha: 0.15 + 0.85 * gb / mx))]
    }

    /// FM: сверху модулятор (частота — RATIO, 1.1; искажается сам по FEEDBACK, 1.4), полупрозрачный; снизу несущая:
    /// глубина модуляции — INDEX (1.2), спадает вдоль иконки по CONTOUR (1.3) и Decay; в углу — отношение.
    static func fmIcon(_ v: IconValues) -> [IconElement] {
        let r = 0.5 * pow(16, v.h), idx = 2.5 * pow(clamp(v.t), 1.5)
        let k = v.m < 0.5 ? 2 * v.m : 1 + 8 * (v.m - 0.5)
        let dec = k * (1.6 - 1.3 * v.d)
        let fb = v.q * 1.4, sc = still * 0.2
        func modS(_ u: Double) -> Double {
            let a = tau * (u * 1.5 - sc) * r
            return sin(a + fb * sin(a))
        }
        let mod = gen { u, _ in modS(u) }
        let car = gen { u, _ in
            let ph = u * 1.5 - sc
            return sin(tau * ph + idx * exp(-u * dec) * modS(u))
        }
        let sn = Jambo.fmRatio(v.h)
        let whole = sn >= 1 && abs(sn - sn.rounded()) < 0.01
        let label = whole ? "×\(Int(sn.rounded()))" : "×" + String(format: "%.1f", sn)
        return [lane(mod, IconLane(y0: 13, amp: 7, alpha: 0.5)), lane(car, IconLane(y0: 38, amp: 14)),
                IconElement(text: label, x: 49, y: 61, size: 8)]
    }

    /// SUB: сверху основной осциллятор (WAVE, 1.1: треугольник, пила, квадрат), снизу — вдвое медленнее (октава
    /// вниз), расходится по фазе с FAT (1.3); прозрачность — по SUB (1.2), верхушки срезаются по GRIT (1.4).
    static func subIcon(_ v: IconValues) -> [IconElement] {
        let q = clamp(v.q)
        let gn = pow(10, 1.2 * q), wg = Swift.min(1, q / 0.1)
        func grit(_ x: Double) -> Double { return (1 - wg) * x + (wg * tanh(gn * x)) / tanh(gn) }
        let ang = clamp(v.t) * Double.pi / 2
        let ga = cos(ang), gb = sin(ang), mx = Swift.max(ga, gb)
        let fat = 0.12 * clamp(v.m), sc = still * 0.16, idx = v.h * 2
        let waves = [1, 2, 3]
        let a = gen { u, _ in grit(morph(waves, idx, u * 2 - sc)) }
        let b = gen { u, _ in grit(morph(waves, idx, u + fat * u - sc / 2)) }
        return [lane(a, IconLane(y0: 20, amp: 10, alpha: 0.15 + 0.85 * ga / mx)),
                lane(b, IconLane(y0: 46, amp: 10, alpha: 0.15 + 0.85 * gb / mx))]
    }
}

extension EngineIcons {
    /// Кадр встроенной BASIC прототипа: POSITION 0 → 0.5 → 1 — синус → пила → квадрат.
    static func basicFrame(_ pos: Double, _ p: Double) -> Double {
        let pp = clamp(pos)
        if pp < 0.5 { return lerp(shSine(p), shSaw(p), sstep(pp * 2)) }
        return lerp(shSaw(p), shSq(p), sstep((pp - 0.5) * 2))
    }

    /// WTABLE: текущий кадр таблицы (POSITION, 1.1, между кадрами — плавно); WARP (1.2) изгибает фазу, выше 50 % —
    /// синхронизация; UNISON (1.3) добавляет бледные копии (3 или 5), DETUNE (1.4) разводит их по фазе.
    /// frame(position, phase) — значение кадра −1…1 (фаза — любое число, период 1).
    public static func wtableIcon(_ v: IconValues, _ frame: (Double, Double) -> Double) -> [IconElement] {
        let pos = v.h, warp = v.t, uni = v.m, det = v.q
        let sc = still * 0.2, cyc = 1.5
        let a = clamp(warp * 2)
        let sy = warp <= 0.5 ? 1 : 1 + (warp - 0.5) * 6
        func warpP(_ p: Double) -> Double { return pow(frac(p), 1 + 3 * a) * sy }
        func mk(_ off: Double) -> [Double] { return gen { u, _ in frame(pos, warpP(cyc * u - sc - off)) } }
        let a3 = clamp(uni * 2), a5 = clamp(uni * 2 - 1)
        let d = det * 0.2 * (1 + 0.12 * sin(still * 1.7))
        var els: [IconElement] = []
        let ghosts: [(Double, Double)] = [(d, 0.3 * a3), (-d, 0.3 * a3), (d / 2, 0.3 * a5), (-d / 2, 0.3 * a5)]
        for (off, al) in ghosts where al > 0.01 {
            els.append(lane(mk(off), IconLane(y0: 32, amp: 22, alpha: al)))
        }
        els.append(lane(mk(0), IconLane(y0: 32, amp: 22)))
        return els
    }

    /// Кадр таблицы дорожки для wtableIcon: уровень 0 мипмапа, между кадрами и отсчётами — линейно.
    public static func tableFrame(_ tb: WtTable) -> (Double, Double) -> Double {
        return { pos, p in
            let size = tb.sizes[0]
            let data = tb.data[0]
            let fpos = clamp(pos) * Double(tb.frames - 1)
            let fi = Swift.min(Swift.max(0, tb.frames - 2), Int(fpos.rounded(.down)))
            let rowB = tb.frames > 1 ? fi + 1 : fi
            let ff = tb.frames > 1 ? fpos - Double(fi) : 0
            let x = frac(p) * Double(size)
            let j = Swift.min(size - 1, Int(x.rounded(.down)))
            let j1 = (j + 1) % size
            let fj = x - Double(j)
            func at(_ row: Int, _ k: Int) -> Double { return Double(data[row * size + k]) }
            let va = at(fi, j) + (at(fi, j1) - at(fi, j)) * fj
            let vb = at(rowB, j) + (at(rowB, j1) - at(rowB, j)) * fj
            return va + (vb - va) * ff
        }
    }
}
