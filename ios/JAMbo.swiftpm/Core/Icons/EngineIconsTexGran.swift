import Foundation

// Иконки TEXTURE (25) и GRANULAR (26) — чистые функции ручек (как у остальных движков; анимация — только от ручек,
// решение пользователя); у GRANULAR фон — огибающая настоящего сэмпла SOURCE (как кадр таблицы у WTABLE). Время иконки — окно в доли секунды слева направо; случайность — детерминированная (hash).

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

    /// TEXTURE — одна волна во времени (окно 0,6 с): сплошной шум (подложка, пауз нет) с щелчками Grit поверх (чаще и
    /// короче с ростом Grit; у нуля — ровное шипение); Tone переводит шум в звенящую волну ноты; Color — мелкость шума
    /// и яркость звона (веса резонаторов); Metal — обертоны волны от 1, 2, 3, 4 к 1, 2.76, 5.40, 8.93.
    public static func textureIcon(_ v: IconValues) -> [IconElement] {
        let c0 = clamp(v.h), g0 = clamp(v.t), tone = clamp(v.m), metal = clamp(v.q)
        let w = texWindow
        // Щелчки на иконке гуще, чем в звуке (видны и на малом Grit), их сила — как у звука.
        let ev = iconEvents(TextureMap.rate(g0) * 1.5, w, 3.1, max: 120)
        var amps: [Double] = []
        for k in 0..<ev.count { amps.append(0.5 + 0.5 * hash(Double(k) * 2.71 + 5)) }
        let lv: Double = Swift.max(TextureMap.length(g0), 0.006)
        let crack: Double = TextureMap.gain(g0) / 2.2
        let dry: Double = cos(tone * Double.pi / 2), wet: Double = sin(tone * Double.pi / 2)
        var ws: [Double] = []
        var ra: [Double] = []
        var wsum: Double = 0
        for i in 0..<4 {
            ws.append(TextureMap.weight(i, c0))
            ra.append(TextureMap.ratio(i, metal))
            wsum += ws[i]
        }
        let fine: Double = 0.12 * pow(8.3, c0)
        let a = gen { u, i in
            let t = u * w
            var e = 0.0
            for (k, tk) in ev.enumerated() {
                if tk > t { break }
                let dt = t - tk
                if dt < 2 * lv + 0.004 { e += amps[k] * exp(-dt / (lv / 3)) }
            }
            let n: Double = nzi(Double(i) * fine + 11)
            let ph: Double = tau * 6 * u
            var s1: Double = 0
            for k in 0..<4 { s1 += ws[k] * sin(ph * ra[k]) }
            let level: Double = 0.45 + crack * Swift.min(1, e) * 0.55
            let x: Double = (dry * n + wet * s1 / wsum) * level
            return clamp(x * 1.3, -1, 1)
        }
        return [lane(a, IconLane(y0: 32, amp: 26))]
    }

    /// GRANULAR — одна картинка, как волна сэмпла с зёрнами: серая сплошная волна (целый файл) во всё поле; полупрозрачная зона — откуда
    /// читаются зёрна (POSITION ± 0,2·SPRAY², как разброс позиции движка); белая линия — POSITION; зёрна — подсвеченные окном Ханна участки волны
    /// (ширина — SIZE, сколько — DENSITY, разброс по зоне — SPRAY); сверху — штрихи вспышек зёрен (их число — DENSITY).
    /// peaks — огибающая настоящего сэмпла SOURCE (samplePeaks, 433 точки 0…1); nil — условный сплошной файл.
    public static func granularIcon(_ v: IconValues, peaks: [Double]? = nil) -> [IconElement] {
        let pos = clamp(v.h), size = clamp(v.t), dens = clamp(v.m), sp = clamp(v.q)
        let span: Double = x1 - x0
        // Ширина зерна на поле: 2…16 точек (ручка SIZE уже логарифмическая).
        let gw: Double = (2 + 14 * size) / span
        let n: Int = 2 + Int((dens * 14).rounded())
        let half: Double = TexGran.posSpread(sp)
        var starts: [Double] = []
        for k in 0..<n {
            let x: Double = pos + rnd(k, 7.7) * half
            starts.append(clamp(x, 0, Swift.max(0, 1 - gw)))
        }
        let real: [Double]? = peaks.flatMap { $0.count == Int(ns) + 1 ? $0 : nil }
        func wave(_ u: Double, _ i: Int) -> Double {
            if let p = real { return p[i] }
            return TexGranIcon.sampleEnv(u) * (0.55 + 0.45 * abs(nz(i * 5 + 3)))
        }
        let smp = gen { u, i in wave(u, i) }
        let grains = gen { u, i in
            var g = 0.0
            for s0 in starts {
                let x = (u - s0) / gw
                if x <= 0 || x >= 1 { continue }
                g += 0.5 * (1 - cos(tau * x))
            }
            return wave(u, i) * Swift.min(1, g)
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

extension EngineIcons {
    /// Огибающая сэмпла для иконки GRANULAR: наибольший модуль (оба канала) на каждую из 433 точек, к максимуму 1
    /// (тишина — нули). В длинном файле точка смотрит не больше 512 отсчётов (иконке хватает).
    public static func samplePeaks(_ s: SampleData) -> [Double] {
        let n: Int = Int(ns) + 1
        var out = [Double](repeating: 0, count: n)
        let frames: Int = s.frames
        if frames < 2 { return out }
        let l = s.left
        let r: UnsafeMutablePointer<Float>? = s.channels > 1 ? s.right : nil
        var top: Double = 0
        for i in 0..<n {
            let a: Int = Swift.min(frames - 1, i * frames / n)
            let b: Int = Swift.max(a + 1, Swift.min(frames, (i + 1) * frames / n))
            let step: Int = Swift.max(1, (b - a) / 512)
            var m: Float = 0
            var k: Int = a
            while k < b {
                let x: Float = abs(l[k])
                if x > m { m = x }
                if let rr = r {
                    let y: Float = abs(rr[k])
                    if y > m { m = y }
                }
                k += step
            }
            out[i] = Double(m)
            if out[i] > top { top = out[i] }
        }
        if top > 0 { for i in 0..<n { out[i] /= top } }
        return out
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
