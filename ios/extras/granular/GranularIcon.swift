// ОТЛОЖЕНО (решение пользователя): иконка GRANULAR, вырезана из Core/Icons/EngineIconsTexGran.swift.
// Вернуть: granularIcon — в extension EngineIcons того файла (перед закрывающей скобкой), samplePeaks — отдельным
// extension EngineIcons; в EngineIcons.elements — `case 26: return granularIcon(v)`.

extension EngineIcons {
    /// GRANULAR — одна картинка, как волна сэмпла с зёрнами: серая сплошная волна (целый файл) во всё поле; полупрозрачная зона — откуда
    /// читаются зёрна (POSITION ± 0,35·SPRAY); белая линия — POSITION; зёрна — подсвеченные окном Ханна участки волны
    /// (ширина — SIZE, сколько — DENSITY, разброс по зоне — SPRAY); сверху — штрихи вспышек зёрен (их число — DENSITY).
    /// peaks — огибающая настоящего сэмпла SOURCE (samplePeaks, 433 точки 0…1); nil — условный сплошной файл.
    public static func granularIcon(_ v: IconValues, peaks: [Double]? = nil) -> [IconElement] {
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

