import Foundation

// Иконки TEXTURE (25) и GRANULAR (26) — чистые функции ручек (как у остальных движков; анимация — только от ручек,
// решение пользователя). Время иконки — окно в доли секунды слева направо; случайность — детерминированная (hash).

extension EngineIcons {
    /// Окно иконки TEXTURE, с.
    static let texWindow = 0.6

    /// Моменты событий (с) пуассоновского потока rate в окне w; первое — через 3 мс. Не больше max.
    static func iconEvents(_ rate: Double, _ w: Double, _ seed: Double, max: Int = 150) -> [Double] {
        var out: [Double] = []
        var t = 0.003
        var k = 0
        while t < w && out.count < max {
            out.append(t)
            let u: Double = Swift.min(0.999, hash(Double(k) * 1.37 + seed))
            t += Swift.max(0.0005, -log(1 - u) / rate)
            k += 1
        }
        return out
    }

    /// TEXTURE — одна волна во времени (окно 0,6 с): при малой DENSITY звук распадается на отдельные частицы-вспышки,
    /// с ростом они сливаются в сплошной шум; TONE переводит и частицы, и шум в чистую волну тона (вспышки звенят
    /// дольше); COLOR — мелкость шума (тёмный — плавный, светлый — частый) и яркость звона (вторая гармоника);
    /// MOTION — плотность, громкость и цвет гуляют по волне (на малом — плавно, на большом — ступеньками).
    public static func textureIcon(_ v: IconValues) -> [IconElement] {
        let c0 = clamp(v.h), d0 = clamp(v.t), tone = clamp(v.m), mo = clamp(v.q)
        let w = texWindow
        // MOTION: шаги S&H по окну, сглаживание — плавное на малом, ступеньки на большом.
        let steps: Int = 2 + Int((mo * 8).rounded())
        let edge: Double = lerp(0.5, 0.03, sstep(clamp((mo - 0.45) / 0.55)))
        func drift(_ u: Double, _ seed: Double) -> Double {
            if mo <= 0.001 { return 0 }
            let x = u * Double(steps)
            let i = Swift.min(steps - 1, Int(x.rounded(.down)))
            let f = x - Double(i)
            let s = f < 1 - edge ? 0 : sstep((f - (1 - edge)) / edge)
            return lerp(rnd(i, seed), rnd(i + 1, seed), s)
        }
        // Частицы на иконке гуще, чем в звуке (5…150 в секунду: и на минимуме видно несколько); поток — по наибольшей
        // плотности, у каждой частицы плотность в своём месте (MOTION) решает, видна ли она.
        func iconRate(_ d: Double) -> Double { return 5 * pow(30, d) }
        let dHi: Double = clamp(d0 + 0.5 * mo)
        let rateHi: Double = iconRate(dHi)
        let ev = iconEvents(rateHi, w, 3.1)
        var keep: [Bool] = []
        var amps: [Double] = []
        for (k, tk) in ev.enumerated() {
            let dk: Double = clamp(d0 + drift(tk / w, 2.9) * 0.5 * mo)
            keep.append(hash(Double(k) * 0.77 + 13) < iconRate(dk) / rateHi)
            amps.append(0.45 + 0.55 * hash(Double(k) * 2.71 + 5))
        }
        let len: Double = TextureMap.length(d0)
        // Видимая длина частицы — не короче 8 мс (иначе точка в одну колонку).
        let lv: Double = Swift.max(len, 0.008)
        let life: Double = 2 * lv + 0.004
        let ring: Double = lv / 3 + 0.004 + tone * tone * 0.12
        let dry: Double = cos(tone * Double.pi / 2), wet: Double = sin(tone * Double.pi / 2)
        let w0: Double = TextureMap.weight(0, c0), w1: Double = TextureMap.weight(1, c0)
        let a = gen { u, i in
            let t = u * w
            let du: Double = drift(u, 2.9)
            let d: Double = clamp(d0 + du * 0.5 * mo)
            // Шум: плотный край — сплошной (раньше, чем в звуке, чтобы переход был виден).
            let cont: Double = TexGranIcon.smooth(0.5, 0.95, d)
            let norm: Double = 1 / sqrt(Swift.max(1, iconRate(d) * TextureMap.length(d) * 0.6))
            var e = 0.0, r = 0.0
            for (k, tk) in ev.enumerated() {
                if tk > t { break }
                if !keep[k] { continue }
                let dt = t - tk
                if dt < life { e += amps[k] * exp(-dt / (lv / 3)) }
                if dt < ring * 5 { r += amps[k] * exp(-dt / ring) }
            }
            let c: Double = clamp(c0 + du * 0.4 * mo)
            let fine: Double = 0.12 * pow(8.3, c)
            let n: Double = nzi(Double(i) * fine + 11)
            // Тон — чистая волна (6 периодов на окно), яркость — вторая гармоника по COLOR.
            let ph: Double = tau * 6 * u
            let s1: Double = (w0 * sin(ph) + w1 * 0.5 * sin(2 * ph)) / (w0 + w1 * 0.5)
            let parts: Double = (dry * e + wet * r) * norm * (1 - cont)
            let amod: Double = 1 + 0.5 * mo * drift(u, 4.3)
            let x: Double = (dry * n + wet * s1) * (parts + cont * 0.85) * amod
            return clamp(x * 1.15, -1, 1)
        }
        return [lane(a, IconLane(y0: 32, amp: 26))]
    }

    /// GRANULAR — одна картинка, как волна сэмпла с зёрнами: серая сплошная волна (целый файл) во всё поле; полупрозрачная зона — откуда
    /// читаются зёрна (POSITION ± 0,35·SPRAY); белая линия — POSITION; зёрна — подсвеченные окном Ханна участки волны
    /// (ширина — SIZE, сколько — DENSITY, разброс по зоне — SPRAY); сверху — штрихи вспышек зёрен (их число — DENSITY).
    public static func granularIcon(_ v: IconValues) -> [IconElement] {
        let pos = clamp(v.h), size = clamp(v.t), dens = clamp(v.m), sp = clamp(v.q)
        let span: Double = x1 - x0
        // Ширина зерна на поле: 2…16 точек (ручка SIZE уже логарифмическая).
        let gw: Double = (2 + 14 * size) / span
        let n: Int = 2 + Int((dens * 14).rounded())
        let half: Double = 0.35 * sp
        var starts: [Double] = []
        for k in 0..<n {
            let x: Double = pos + rnd(k, 7.7) * half
            starts.append(clamp(x, 0, Swift.max(0, 1 - gw)))
        }
        let smp = gen { u, i in TexGranIcon.sampleEnv(u) * (0.55 + 0.45 * abs(nz(i * 5 + 3))) }
        let grains = gen { u, i in
            var g = 0.0
            for s0 in starts {
                let x = (u - s0) / gw
                if x <= 0 || x >= 1 { continue }
                g += 0.5 * (1 - cos(tau * x))
            }
            return TexGranIcon.sampleEnv(u) * (0.55 + 0.45 * abs(nz(i * 5 + 3))) * Swift.min(1, g)
        }
        let lo = clamp(pos - half), hi = clamp(pos + half)
        let xa = x0 + span * lo, xp = x0 + span * pos
        // Зона — не уже зерна и в пределах волны.
        let za: Double = Swift.max(x0, Swift.min(xa, xp - 1))
        let zb: Double = Swift.min(x1, Swift.max(x0 + span * hi, x0 + span * (pos + gw)))
        // Штрихи вспышек: по зоне (не уже зерна), их число — DENSITY, высота — разная.
        var ticks: [IconRect] = []
        for k in 0..<n {
            let f: Double = (Double(k) + 0.5 + 0.35 * rnd(k, 3.3)) / Double(n)
            let x: Double = za + (zb - za) * clamp(f)
            let h: Double = 3 + 3 * hash(Double(k) * 1.9 + 4)
            ticks.append(IconRect(x - 0.4, 3, 0.8, h))
        }
        return [
            lane(smp, IconLane(y0: 34, amp: 22, mirror: true, ink: .secondary)),
            IconElement(rects: [IconRect(za, 2, Swift.max(0.8, zb - za), 60)], op: 0.18),
            lane(grains, IconLane(y0: 34, amp: 22, mirror: true, thin: true)),
            IconElement(rects: ticks, op: 0.8),
            IconElement(rects: [IconRect(xp - 0.5, 2, 1, 60)]),
        ]
    }
}

/// Вспомогательное для иконок TEXTURE и GRANULAR.
enum TexGranIcon {
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = Swift.min(1, Swift.max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Огибающая условного сэмпла — сплошной файл: громкость плавно гуляет (0,5…1) без пауз и провалов, по краям —
    /// короткие подъём и спад.
    static func sampleEnv(_ p: Double) -> Double {
        let x = Swift.min(1, Swift.max(0, p))
        var e: Double = 0.74 + 0.14 * sin(EngineIcons.tau * 1.3 * x + 0.4) + 0.09 * sin(EngineIcons.tau * 3.7 * x + 1.1)
        e += 0.06 * EngineIcons.nzi(x * 40 + 5)
        let edge: Double = Swift.min(1, Swift.min(x, 1 - x) / 0.04)
        return Swift.min(1, Swift.max(0.45, e)) * (0.3 + 0.7 * edge)
    }
}
