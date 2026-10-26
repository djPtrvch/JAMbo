import Foundation

// Миниатюра ENV (окно MOD): форма — по ручкам с условным гейтом, точка — всегда на кривой. Пока нота держится — по
// времени; после отпускания — в том месте кривой, где её уровень равен настоящему уровню ENV (ModEngine.env): нота
// отпущена во время Attack или Decay — точка спускается по участку Decay, ниже Sustain — по Release; обычное
// отпускание — по Release. Всё в миллисекундах.

public enum EnvDot {
    /// Уровень кривой миниатюры (ADSR с гейтом gate) в момент x.
    public static func curve(_ a: Double, _ d: Double, _ s: Double, _ r: Double, _ x: Double, _ gate: Double) -> Double {
        if x < 0 { return 0 }
        if x < gate { return ads(a, d, s, x) }
        let rel = x - gate
        return rel < r ? ads(a, d, s, gate) * (1 - rel / r) : 0
    }

    static func ads(_ a: Double, _ d: Double, _ s: Double, _ y: Double) -> Double {
        if y < a { return a > 0 ? y / a : 1 }
        if y < a + d { return d > 0 ? 1 - (1 - s) * (y - a) / d : s }
        return s
    }

    /// Точка на кривой: t — время от начала ноты, g — гейт ноты (мс; держится — больше t), gate — условный гейт
    /// миниатюры. Возвращает x на кривой (0…gate + r); t < 0 (ноты не было) — 0.
    public static func x(_ a: Double, _ d: Double, _ s: Double, _ r: Double, t: Double, g: Double,
                         gate: Double) -> Double {
        if t < 0 { return 0 }
        if t < g { return Swift.min(gate, t) }
        let rel: Double = t - g
        if rel >= r { return gate + r }
        // Настоящий уровень после отпускания (как ModEngine.env).
        let level: Double = ads(a, d, s, g) * (1 - rel / r)
        // Отпустили до конца Attack + Decay и уровень выше Sustain — место на участке Decay с тем же уровнем.
        if g < a + d && level > s && d > 0 && s < 1 {
            return a + d * (1 - level) / (1 - s)
        }
        // Иначе — на Release (от Sustain к нулю) с тем же уровнем.
        if s <= 0 { return gate + r }
        let k: Double = Swift.min(1, level / s)
        return gate + r * (1 - k)
    }
}
