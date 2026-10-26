import Foundation

// Иконки TEXTURE (25) и GRANULAR (26) — чистые функции ручек (как у остальных движков; анимация — только от ручек,
// решение пользователя). Время иконки — окно в доли секунды слева направо; случайность — детерминированная (hash).

extension EngineIcons {
    /// Окно иконки TEXTURE, с.
    static let texWindow = 0.6
    /// Окно иконки GRANULAR, с.
    static let granWindow = 1.0

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

    /// TEXTURE: вспышки шума во времени. DENSITY (1.2) — сколько вспышек и их длина (на плотном краю — сплошной шум);
    /// COLOR (1.1) — мелкость шума (тёмный — плавный, светлый — частый) и яркость звона; TONE (1.3) — вспышки
    /// переходят в звенящую волну с долгим хвостом; MOTION (1.4) — серая линия дрейфа внизу (плавная → ступеньки),
    /// высота и цвет вспышек гуляют вместе с ней.
    public static func textureIcon(_ v: IconValues) -> [IconElement] {
        let c0 = clamp(v.h), d = clamp(v.t), tone = clamp(v.m), mo = clamp(v.q)
        let w = texWindow
        let rate: Double = TextureMap.rate(d)
        let len: Double = TextureMap.length(d)
        let ev = iconEvents(rate, w, 3.1)
        let amps: [Double] = ev.indices.map { k in (0.4 + 0.6 * hash(Double(k) * 2.71 + 5)) }
        let norm: Double = 1 / sqrt(Swift.max(1, rate * len))
        // MOTION: шаги S&H по окну (их больше с ручкой), сглаживание — плавное на малом, ступеньки на большом.
        let steps: Int = 1 + Int((mo * 9).rounded())
        let edge: Double = lerp(0.5, 0.02, sstep(clamp((mo - 0.45) / 0.55)))
        func drift(_ u: Double, _ seed: Double) -> Double {
            if mo <= 0.001 { return 0 }
            let x = u * Double(steps)
            let i = Swift.min(steps - 1, Int(x.rounded(.down)))
            let f = x - Double(i)
            let a = rnd(i, seed), b = rnd(i + 1, seed)
            let s = f < 1 - edge ? 0 : sstep((f - (1 - edge)) / edge)
            return lerp(a, b, s)
        }
        // Видимая длина вспышки — не короче 10 мс (иначе редкие щелчки — точки в одну колонку).
        let lv: Double = Swift.max(len, 0.01)
        let life: Double = 2 * lv + 0.004
        let ring: Double = lv / 3 + 0.004 + tone * tone * 0.09
        let dry: Double = cos(tone * Double.pi / 2), wet: Double = sin(tone * Double.pi / 2)
        let cont: Double = 0.9 * TexGranIcon.smooth(0.65, 1, d)
        let wb: [Double] = (0..<2).map { TextureMap.weight($0, c0) }
        let a = gen { u, i in
            let t = u * w
            let dc: Double = drift(u, 1.7) * 0.4 * mo
            let c: Double = clamp(c0 + dc)
            let fine: Double = 0.12 * pow(8.3, c)
            let amod: Double = 1 + 0.8 * mo * drift(u, 4.3)
            var e = 0.0, r = 0.0
            for (k, tk) in ev.enumerated() {
                if tk > t { break }
                let dt = t - tk
                if dt < life { e += amps[k] * exp(-dt / (lv / 3)) }
                if wet > 0.01 && dt < ring * 5 {
                    var s = 0.0
                    // Звон — основной тон и вторая гармоника (выше — мельче шага точек), яркость — по COLOR.
                    s += wb[0] * sin(tau * 14 * dt) + wb[1] * sin(tau * 28 * dt)
                    r += amps[k] * exp(-dt / ring) * s / (wb[0] + wb[1])
                }
            }
            let n: Double = nzi(Double(i) * fine + 11)
            let x: Double = (dry * n * (e * norm + cont) + wet * r * norm * 1.6) * amod
            return clamp(x * 1.3, -1, 1)
        }
        var els: [IconElement] = [lane(a, IconLane(y0: 27, amp: 21))]
        if mo > 0.001 {
            let b = gen { u, _ in drift(u, 1.7) }
            els.append(lane(b, IconLane(y0: 56, amp: 4.5, ink: .secondary)))
        } else {
            els.append(axis(56))
        }
        return els
    }

    /// GRANULAR: сверху облако зёрен во времени (окно Ханна; SIZE — ширина, DENSITY — сколько, SPRAY — разброс
    /// высоты и ритма), снизу серая волна сэмпла: POSITION — метка, SPRAY — подсвеченная зона, откуда читаются зёрна.
    public static func granularIcon(_ v: IconValues) -> [IconElement] {
        let pos = clamp(v.h), size0 = TexGran.grainSize(clamp(v.t)), rate = TexGran.grainRate(clamp(v.m))
        // Видимая длина зерна — не короче 15 мс (5 мс — две точки).
        let size: Double = Swift.max(size0, 0.015)
        let sp = clamp(v.q)
        let w = granWindow
        var starts: [Double] = []
        var t = 0.003
        var k = 0
        while t < w && starts.count < 160 {
            starts.append(t)
            t += 1 / rate * (1 + rnd(k, 2.3) * sp * 0.8)
            k += 1
        }
        let gainC: Double = 1 / sqrt(Swift.max(1, rate * size0))
        let gp: [Double] = starts.indices.map { k in clamp(pos + rnd(k, 7.7) * sp * 0.35) }
        let gf: [Double] = starts.indices.map { k in 60 * pow(2, rnd(k, 9.1) * sp * 3 / 12) }
        let ga: [Double] = gp.map { 0.25 + 0.75 * TexGranIcon.sampleEnv($0) }
        let cloud = gen { u, _ in
            let t = u * w
            var s = 0.0
            for (k, tk) in starts.enumerated() {
                if tk > t { break }
                let x = (t - tk) / size
                if x >= 1 { continue }
                let hann = 0.5 * (1 - cos(tau * x))
                s += hann * ga[k] * sin(tau * gf[k] * (t - tk) + gp[k] * 40)
            }
            return clamp(s * gainC * 1.2, -1, 1)
        }
        let smp = gen { u, i in TexGranIcon.sampleEnv(u) * (0.55 + 0.45 * abs(nz(i * 5 + 3))) }
        let lo = clamp(pos - 0.35 * sp), hi = clamp(pos + 0.35 * sp)
        let xa = x0 + (x1 - x0) * lo, xb = x0 + (x1 - x0) * hi, xp = x0 + (x1 - x0) * pos
        return [
            lane(cloud, IconLane(y0: 22, amp: 17)),
            lane(smp, IconLane(y0: 54, amp: 7, mirror: true, ink: .secondary)),
            IconElement(rects: [IconRect(xa, 45, Swift.max(0.8, xb - xa), 18)], op: 0.22),
            IconElement(rects: [IconRect(xp - 0.5, 44, 1, 19)]),
        ]
    }
}

/// Вспомогательное для иконок TEXTURE и GRANULAR.
enum TexGranIcon {
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = Swift.min(1, Swift.max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Огибающая условного сэмпла (как демо прототипа): восемь затухающих нот арпеджио, затем нарастающий пэд.
    static func sampleEnv(_ p: Double) -> Double {
        if p < 0.57 {
            let step = 0.0667
            let k = (p / step).rounded(.down)
            let dt = p - k * step
            return 0.15 + 0.85 * exp(-dt / 0.035)
        }
        let x = (p - 0.57) / 0.43
        return 0.1 + 0.6 * pow(sin(Double.pi * Swift.min(1, x)), 1.5)
    }
}
