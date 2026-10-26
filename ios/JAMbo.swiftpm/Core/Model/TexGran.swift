import Foundation

// TEXTURE и GRANULAR (ТЗ «Texture и Granular»): значения на ручках 1.1–1.4 (ручки хранятся 0…100, как у всех синтов).

enum TexGran {
    /// Длина сэмпла GRANULAR выбранной дорожки, с (ставит интерфейс; 0 — нет): POSITION на ручке — в секундах.
    static var sourceSeconds: Double = 0

    /// Длина зерна GRANULAR, с: 0,005 · 100^v (5…500 мс).
    static func grainSize(_ v: Double) -> Double { return 0.005 * pow(100, v) }
    /// Зёрен в секунду: 2 · 40^v (2…80).
    static func grainRate(_ v: Double) -> Double { return 2 * pow(40, v) }

    /// Свой формат ручки k движка e (nil — проценты).
    static func format(_ e: Int, _ k: Int) -> ((Double) -> String)? {
        if e == Jambo.texture && k == 0 { return { v in TextureMap.colorName(v / 100) } }
        if e == Jambo.texture && k == 1 {
            return { v in "\(Int(TextureMap.rate(v / 100).rounded())) /s" }
        }
        if e == Jambo.granular && k == 0 {
            return { v in
                let s: Double = sourceSeconds
                return s > 0 ? String(format: "%.2f s", v / 100 * s) : Fmt.pct(v)
            }
        }
        if e == Jambo.granular && k == 1 { return { v in Fmt.ms(grainSize(v / 100) * 1000) } }
        if e == Jambo.granular && k == 2 { return { v in "\(Int(grainRate(v / 100).rounded())) /s" } }
        return nil
    }
}
