import Foundation

// TEXTURE и GRANULAR (ТЗ «Texture и Granular», GRANULAR — ТЗ «Granular»): значения на ручках 1.1–1.4 (ручки хранятся
// 0…100, как у всех синтов) и формулы GRANULAR (эталон — docs/prototype/texture-granular.html, вкладка Granular).

enum TexGran {
    /// Длина сэмпла GRANULAR выбранной дорожки, с (ставит интерфейс; 0 — нет): POSITION на ручке — в секундах.
    static var sourceSeconds: Double = 0

    /// Длина зерна GRANULAR, с: 0,01 · 80^v (10…800 мс).
    @inline(__always) static func grainSize(_ v: Double) -> Double { return 0.01 * pow(80, v) }
    /// Зёрен звучит одновременно: 0,5 · 48^v (0,5…24).
    @inline(__always) static func overlap(_ v: Double) -> Double { return 0.5 * pow(48, v) }
    /// Зёрен в секунду на ноту — не больше (MAX_RATE прототипа).
    static let maxRate = 100.0

    @inline(__always) static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t: Double = Swift.min(1, Swift.max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Разброс высоты зерна, центы (×rnd): 25·sp² + 120·smoothstep(0,75; 1; sp).
    @inline(__always) static func centsSpread(_ sp: Double) -> Double {
        return 25 * sp * sp + 120 * smooth(0.75, 1, sp)
    }
    /// Разброс панорамы (×rnd, затем clamp −1…1): 0,1 + 0,6·sp².
    @inline(__always) static func panSpread(_ sp: Double) -> Double { return 0.1 + 0.6 * sp * sp }
    /// Разброс позиции, доля сэмпла (×rnd): 0,2·sp².
    @inline(__always) static func posSpread(_ sp: Double) -> Double { return 0.2 * sp * sp }
    /// Дрожание интервала (×rnd): 0,4 · smoothstep(0,4; 1; sp)².
    @inline(__always) static func jitter(_ sp: Double) -> Double {
        let s: Double = smooth(0.4, 1, sp)
        return 0.4 * s * s
    }

    /// Длина зерна (с), зёрен одновременно и частота запуска на ноту (grainState прототипа); sc — min(1; 4 / N).
    @inline(__always) static func state(size v: Double, density d: Double, sc: Double, sampleSeconds len: Double)
        -> (dur: Double, eff: Double, rate: Double) {
        let dur: Double = Swift.min(grainSize(v), len * 0.9)
        let eff: Double = Swift.min(overlap(d) * sc, maxRate * dur)
        return (dur, eff, dur > 0 ? eff / dur : 0)
    }

    /// Константа усиления шины ноты (GRAIN_K прототипа).
    static let gainK = 1.3
    /// Уровень выхода GRANULAR: как у TEXTURE (×0,63 — Level 0,7 · 0,9 прототипа) и ×2,8 под мастер JAMbo (ТЗ: RMS
    /// на выходе мастера около 0,1 на ручках по умолчанию — как у ANALOG и FM; итог — GRAIN_K 1,3 → 3,64).
    static let out = 0.63 * 2.8

    /// Интервал запуска (с) и усиление шины ноты (grainPlan прототипа). ts — период источника, с (0 — неизвестен),
    /// semi — полутоны от исходной высоты.
    @inline(__always) static func plan(dur: Double, eff: Double, ts: Double, semi: Double, spray sp: Double)
        -> (iv: Double, gain: Double) {
        var iv: Double = eff > 0 ? dur / eff : dur
        if ts > 0 {
            let tout: Double = ts / pow(2, semi / 12)
            iv = Swift.max(1, (iv / tout).rounded()) * tout
        }
        let effA: Double = dur / iv
        let inc: Double = gainK / Swift.max(1, effA).squareRoot()
        if ts <= 0 { return (iv, inc) }
        let coh: Double = 1.5 * gainK / Swift.max(1, effA)
        return (iv, coh + (inc - coh) * smooth(0.3, 0.7, sp))
    }

    /// Свой формат ручки k движка e (nil — проценты).
    static func format(_ e: Int, _ k: Int) -> ((Double) -> String)? {
        if e == Jambo.texture && k == 0 { return { v in TextureMap.colorName(v / 100) } }
        if e == Jambo.granular && k == 0 {
            return { v in
                let s: Double = sourceSeconds
                return s > 0 ? String(format: "%.2f s", v / 100 * s) : Fmt.pct(v)
            }
        }
        if e == Jambo.granular && k == 1 {
            // Стиль ручек JAMbo (Fmt.ms): «151ms» (предел 800 мс — всегда в мс).
            return { v in Fmt.ms(grainSize(v / 100) * 1000) }
        }
        if e == Jambo.granular && k == 2 { return { v in String(format: "×%.1f", overlap(v / 100)) } }
        return nil
    }
}
