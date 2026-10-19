import Foundation

// KEY VELOCITY (S12): сила нажатия клавиши — по толчку iPad в момент касания (акселерометр). Здесь — расчёт по
// отсчётам датчика (время — секунды с запуска системы, как у касаний; ускорение без гравитации, в g).

public enum TapVelocity {
    /// Окно вокруг касания: 40 мс до и 15 мс после (нота звучит через 15 мс после касания).
    public static let before = 0.040
    public static let after = 0.015
    /// Толчок слабее gMin — самая тихая нота (0.2), сильнее gMax — самая громкая (1); между — логарифмически.
    public static let gMin = 0.02
    public static let gMax = 0.6

    /// Сила 0.2…1 по наибольшему толчку.
    public static func velocity(peak g: Double) -> Double {
        if !(g > gMin) { return 0.2 }
        let u: Double = log(g / gMin) / log(gMax / gMin)
        return 0.2 + 0.8 * Swift.min(1, Swift.max(0, u))
    }

    /// Наибольший толчок в окне касания at; nil — отсчётов датчика в окне нет (датчика нет или он не работает).
    public static func peak(_ samples: [(t: Double, g: Double)], at: Double) -> Double? {
        var best: Double? = nil
        for s in samples where s.t >= at - before && s.t <= at + after {
            best = Swift.max(best ?? 0, s.g)
        }
        return best
    }
}
