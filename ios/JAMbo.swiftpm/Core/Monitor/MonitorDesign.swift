import Foundation

// Headphone Monitor (ТЗ «Headphone Monitor», фаза 1): монитор-цепочка в конце выхода — только для прослушивания, в
// экспорт, стемы и запись не попадает. Здесь — настройки, пресеты Translation (данные — Resources/TranslationPresets.json)
// и расчёт параметров для колбэка (MonitorChain) в основном потоке.
// Порядок по ТЗ: Mono → Translation EQ (и Sub-check) → Crossfeed → Headphone Correction → Trim → Level compensation →
// Safety limiter. Биквады одинаковы в обоих каналах и линейны, Mono и Crossfeed — линейное смешение каналов, поэтому
// в колбэке все биквады идут одним каскадом после Crossfeed (результат тот же).

/// Настройки монитор-цепочки (одни на приложение, UserDefaults). Bypass — выключенная коррекция (Eq.on).
public struct MonitorSettings: Codable, Equatable, Sendable {
    /// Strength коррекции, 0…1.
    public var strength: Double = 1
    /// Crossfeed: угол колонок, градусы (10…60), и Amount, 0…1.
    public var angle: Double = MonitorSpec.angleDef
    public var amount: Double = MonitorSpec.amountDef
    /// Имя пресета Translation (пусто — первый, Studio).
    public var translation: String = ""
    public var mono: Bool = false
    public var sub: Bool = false
    /// Вкладка окна коррекции: 0 — PHONES (CORRECTION, TRIM), 1 — ROOM (TRANSLATION, Crossfeed), 2 — CHECK (MONO, SUB, LEVEL).
    public var tab: Int = 0
    /// Референс через мастер-цепочку (по умолчанию нет — как прежде: мимо мастера) и через монитор-цепочку (да).
    public var refMaster: Bool = false
    public var refMonitor: Bool = true
    /// Подгонка громкости референса к миксу и ручная подстройка (±12 dB).
    public var refMatch: Bool = true
    public var refTrim: Double = 0

    public init() {}

    public static func decode(_ data: Data?) -> MonitorSettings {
        guard let data = data, let s = try? JSONDecoder().decode(MonitorSettings.self, from: data) else { return MonitorSettings() }
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case strength, angle, amount, translation, mono, sub, tab, refMaster, refMonitor, refMatch, refTrim
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strength = Swift.min(1, Swift.max(0, c.value(.strength, 1.0)))
        angle = Swift.min(MonitorSpec.angleMax, Swift.max(MonitorSpec.angleMin, c.value(.angle, MonitorSpec.angleDef)))
        amount = Swift.min(1, Swift.max(0, c.value(.amount, MonitorSpec.amountDef)))
        translation = c.value(.translation, "")
        mono = c.value(.mono, false)
        sub = c.value(.sub, false)
        let t: Int = c.value(.tab, 0)
        tab = t >= 0 && t < 3 ? t : 0
        refMaster = c.value(.refMaster, false)
        refMonitor = c.value(.refMonitor, true)
        refMatch = c.value(.refMatch, true)
        refTrim = Swift.min(12, Swift.max(-12, c.value(.refTrim, 0.0)))
    }
}

/// Константы цепочки (стартовые значения ТЗ, подстраиваются на слух).
public enum MonitorSpec {
    /// Crossfeed: радиус головы, м, скорость звука, м/с (ITD по Вудворду: r/c·(θ + sin θ)).
    public static let headRadius: Double = 0.0875
    public static let soundSpeed: Double = 343
    public static let angleMin: Double = 10
    public static let angleMax: Double = 60
    public static let angleDef: Double = 30
    public static let amountDef: Double = 0.5
    /// Наибольшее g при Amount 100 %.
    public static let gainMax: Double = 0.7
    /// ФНЧ ветки Crossfeed, Гц.
    public static let crossLp: Double = 800
    /// Наибольшее усиление одного фильтра коррекции и предел Level compensation, dB.
    public static let filterMax: Double = 12
    public static let compMax: Double = 12
    /// Trim: частоты полос, Q, предел, dB.
    public static let trimHz: [Double] = [100, 400, 1500, 4000, 8000]
    public static let trimQ: Double = 1
    public static let trimMax: Double = 3
    /// Sub-check: ФНЧ 4-го порядка, Гц.
    public static let subHz: Double = 120
    /// Потолок лимитера, dBFS, и его отпускание, с.
    public static let ceilingDb: Double = -0.5
    public static let release: Double = 0.05
    /// Плавность: переходы вкл./выкл. (Bypass, Mono, референс мимо цепочки), с; параметры и коэффициенты, с.
    public static let fade: Double = 0.025
    public static let glide: Double = 0.025

    /// Места биквадов: Translation, Sub-check, коррекция (полосы со срезами — по ступеням), Trim.
    public static let transSlots = 8
    public static let subSlots = 2
    public static let corrSlots = 20
    public static let sections = transSlots + subSlots + corrSlots + 5
    /// Параметры для колбэка: коэффициенты (5 на биквад), затем усиление компенсации, g и задержка Crossfeed (отсчёты),
    /// ФНЧ Crossfeed (5), Mono (0/1), цепочка включена (0/1).
    public static let compAt = sections * 5
    public static let crossGAt = compAt + 1
    public static let crossDelayAt = compAt + 2
    public static let crossLpAt = compAt + 3
    public static let monoAt = compAt + 8
    public static let onAt = compAt + 9
    public static let size = compAt + 10

    /// ITD для угла (градусы), с.
    public static func itd(_ degrees: Double) -> Double {
        let t: Double = degrees * Double.pi / 180
        return headRadius / soundSpeed * (t + sin(t))
    }

    /// Q ступеней Баттерворта 4-го порядка.
    public static let butter4: [Double] = [0.5411961001461969, 1.3065629648763766]
}

/// Пресет Translation (Resources/TranslationPresets.json): список биквадов и Mono.
public struct TranslationPreset: Codable, Equatable, Sendable {
    public struct Filter: Codable, Equatable, Sendable {
        /// HP, LP, PK, LS, HS.
        public var type: String
        public var freq: Double
        public var gain: Double?
        public var q: Double?
        /// Порядок HP и LP: 2 (по умолчанию) или 4.
        public var order: Int?
    }
    public var name: String
    public var mono: Bool?
    public var filters: [Filter]

    /// Список пресетов из JSON ({"presets": […]}); ошибка — пусто.
    public static func list(_ data: Data?) -> [TranslationPreset] {
        struct Book: Codable { var presets: [TranslationPreset] }
        guard let d = data, let b = try? JSONDecoder().decode(Book.self, from: d) else { return [] }
        return b.presets
    }
}

/// Один биквад: тип EqSpec, частота, усиление, Q (линейный).
struct MonitorBiquad {
    var type: Int
    var freq: Double
    var gain: Double
    var q: Double
}

/// Расчёт параметров цепочки (основной поток).
public enum MonitorDesign {
    /// Биквады пресета по порядку.
    static func biquads(_ p: TranslationPreset?) -> [MonitorBiquad] {
        guard let p = p else { return [] }
        var out: [MonitorBiquad] = []
        for f in p.filters {
            let code: String = f.type.uppercased()
            let q: Double = f.q ?? 0.7071067811865476
            let g: Double = f.gain ?? 0
            if code == "HP" || code == "LP" {
                let t: Int = code == "HP" ? EqSpec.lowCut : EqSpec.highCut
                if (f.order ?? 2) >= 4 {
                    for bq in MonitorSpec.butter4 { out.append(MonitorBiquad(type: t, freq: f.freq, gain: 0, q: bq)) }
                } else {
                    out.append(MonitorBiquad(type: t, freq: f.freq, gain: 0, q: q))
                }
            } else if code == "PK" {
                out.append(MonitorBiquad(type: EqSpec.bell, freq: f.freq, gain: g, q: q))
            } else if code == "LS" || code == "LSC" {
                out.append(MonitorBiquad(type: EqSpec.lowShelf, freq: f.freq, gain: g, q: q))
            } else if code == "HS" || code == "HSC" {
                out.append(MonitorBiquad(type: EqSpec.highShelf, freq: f.freq, gain: g, q: q))
            }
        }
        return out
    }

    /// Биквады коррекции: полосы Eq с Strength s (усиление ±12 dB · s, линейно в dB); срезы и notch — при s > 0.
    static func correction(_ eq: Eq?, strength s: Double) -> [MonitorBiquad] {
        guard let eq = eq, s > 0 else { return [] }
        var out: [MonitorBiquad] = []
        for case let b? in eq.bands where b.on {
            if EqSpec.hasGain(b.type) {
                let g: Double = Swift.max(-MonitorSpec.filterMax, Swift.min(MonitorSpec.filterMax, b.gain)) * s
                if g == 0 { continue }
                let q: Double = b.type == EqSpec.bell ? b.q : 0.7071067811865476
                out.append(MonitorBiquad(type: b.type, freq: b.freq, gain: g, q: q))
            } else {
                let q: Double = b.q
                for _ in 0..<EqSpec.stages(b) { out.append(MonitorBiquad(type: b.type, freq: b.freq, gain: 0, q: q)) }
            }
        }
        return out
    }

    /// Коэффициенты биквада (нормированные b0, b1, b2, a1, a2); без действия — ровно 1, 0, 0, 0, 0.
    static func coeffs(_ b: MonitorBiquad, _ sr: Double, _ out: UnsafeMutablePointer<Double>) {
        if EqSpec.hasGain(b.type) && b.gain == 0 {
            identity(out)
            return
        }
        // У EqCoeffs Q срезов — в dB (как у Web Audio).
        let q: Double = EqSpec.isCut(b.type) ? 20 * log10(b.q) : b.q
        EqCoeffs.coeffs(b.type, b.freq, b.gain, q, sr, out)
    }

    static func identity(_ out: UnsafeMutablePointer<Double>) {
        out[0] = 1; out[1] = 0; out[2] = 0; out[3] = 0; out[4] = 0
    }

    /// Параметры для колбэка (MonitorSpec.size значений): eq — профиль коррекции (nil — нет; Eq.on false — Bypass).
    public static func make(eq: Eq?, settings m: MonitorSettings, trim: [Double], preset: TranslationPreset?,
                            sampleRate sr: Double) -> [Double] {
        var out = [Double](repeating: 0, count: MonitorSpec.size)
        out.withUnsafeMutableBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for k in 0..<MonitorSpec.sections { identity(base + k * 5) }
            let trans: [MonitorBiquad] = biquads(preset)
            for (k, b) in trans.prefix(MonitorSpec.transSlots).enumerated() { coeffs(b, sr, base + k * 5) }
            if m.sub {
                for (k, q) in MonitorSpec.butter4.enumerated() {
                    let b = MonitorBiquad(type: EqSpec.highCut, freq: MonitorSpec.subHz, gain: 0, q: q)
                    coeffs(b, sr, base + (MonitorSpec.transSlots + k) * 5)
                }
            }
            let c0: Int = MonitorSpec.transSlots + MonitorSpec.subSlots
            let corr: [MonitorBiquad] = correction(eq, strength: m.strength)
            for (k, b) in corr.prefix(MonitorSpec.corrSlots).enumerated() { coeffs(b, sr, base + (c0 + k) * 5) }
            let t0: Int = c0 + MonitorSpec.corrSlots
            for k in 0..<MonitorSpec.trimHz.count {
                let g: Double = k < trim.count ? Swift.max(-MonitorSpec.trimMax, Swift.min(MonitorSpec.trimMax, trim[k])) : 0
                let b = MonitorBiquad(type: EqSpec.bell, freq: MonitorSpec.trimHz[k], gain: g, q: MonitorSpec.trimQ)
                coeffs(b, sr, base + (t0 + k) * 5)
            }
            let g: Double = m.amount * MonitorSpec.gainMax
            base[MonitorSpec.crossGAt] = g
            base[MonitorSpec.crossDelayAt] = MonitorSpec.itd(m.angle) * sr
            let lp = MonitorBiquad(type: EqSpec.highCut, freq: MonitorSpec.crossLp, gain: 0, q: 0.7071067811865476)
            coeffs(lp, sr, base + MonitorSpec.crossLpAt)
            base[MonitorSpec.monoAt] = (m.mono || (preset?.mono ?? false)) ? 1 : 0
            base[MonitorSpec.onAt] = (eq?.on ?? true) ? 1 : 0
            let db: Double = compensation(base, sr)
            base[MonitorSpec.compAt] = db == 0 ? 1 : pow(10, db / 20)
        }
        return out
    }

    /// Level compensation, dB: минус средняя мощность АЧХ цепочки (биквады и Crossfeed для сигнала в центре) с розовым
    /// весом — точки через 1/12 октавы в 20 Гц…20 кГц (равный вес октав), с пределом ±12 dB; 0 — без изменения.
    static func compensation(_ p: UnsafePointer<Double>, _ sr: Double) -> Double {
        var active: [Int] = []
        for k in 0..<MonitorSpec.sections where !isIdentity(p + k * 5) { active.append(k) }
        let g: Double = p[MonitorSpec.crossGAt]
        if active.isEmpty && g == 0 { return 0 }
        let points: Int = 120
        var sum: Double = 0
        for i in 0..<points {
            let hz: Double = 20 * pow(1000, (Double(i) + 0.5) / Double(points))
            let w: Double = 2 * Double.pi * hz / sr
            var pw: Double = 1
            for k in active { pw *= power(p + k * 5, w) }
            if g > 0 { pw *= crossPower(p, w, g) }
            sum += pw
        }
        let mean: Double = sum / Double(points)
        if mean <= 0 { return MonitorSpec.compMax }
        let db: Double = -10 * log10(mean)
        if abs(db) < 0.005 { return 0 }
        return Swift.max(-MonitorSpec.compMax, Swift.min(MonitorSpec.compMax, db))
    }

    static func isIdentity(_ c: UnsafePointer<Double>) -> Bool {
        return c[0] == 1 && c[1] == 0 && c[2] == 0 && c[3] == 0 && c[4] == 0
    }

    /// |H|² биквада на круговой частоте w.
    static func power(_ c: UnsafePointer<Double>, _ w: Double) -> Double {
        let c1: Double = cos(w), s1: Double = sin(w), c2: Double = cos(2 * w), s2: Double = sin(2 * w)
        let nr: Double = c[0] + c[1] * c1 + c[2] * c2
        let ni: Double = -(c[1] * s1 + c[2] * s2)
        let dr: Double = 1 + c[3] * c1 + c[4] * c2
        let di: Double = -(c[3] * s1 + c[4] * s2)
        return (nr * nr + ni * ni) / Swift.max(1e-30, dr * dr + di * di)
    }

    /// |H|² Crossfeed для одинаковых каналов: (1 + g·LP·e^(−jwD)) / (1 + g).
    static func crossPower(_ p: UnsafePointer<Double>, _ w: Double, _ g: Double) -> Double {
        let c: UnsafePointer<Double> = p + MonitorSpec.crossLpAt
        let c1: Double = cos(w), s1: Double = sin(w), c2: Double = cos(2 * w), s2: Double = sin(2 * w)
        let nr: Double = c[0] + c[1] * c1 + c[2] * c2
        let ni: Double = -(c[1] * s1 + c[2] * s2)
        let dr: Double = 1 + c[3] * c1 + c[4] * c2
        let di: Double = -(c[3] * s1 + c[4] * s2)
        let den: Double = Swift.max(1e-30, dr * dr + di * di)
        // LP = (nr + j ni) / (dr + j di).
        let lr: Double = (nr * dr + ni * di) / den
        let li: Double = (ni * dr - nr * di) / den
        let d: Double = p[MonitorSpec.crossDelayAt] * w
        let er: Double = cos(d), ei: Double = -sin(d)
        let xr: Double = 1 + g * (lr * er - li * ei)
        let xi: Double = g * (lr * ei + li * er)
        return (xr * xr + xi * xi) / ((1 + g) * (1 + g))
    }

    /// АЧХ всей цепочки (без компенсации и лимитера) на частоте hz для сигнала в центре, dB — для тестов и экрана.
    public static func response(_ p: [Double], hz: Double, sampleRate sr: Double) -> Double {
        return p.withUnsafeBufferPointer { b -> Double in
            guard let base = b.baseAddress else { return 0 }
            let w: Double = 2 * Double.pi * hz / sr
            var pw: Double = 1
            for k in 0..<MonitorSpec.sections { pw *= power(base + k * 5, w) }
            let g: Double = base[MonitorSpec.crossGAt]
            if g > 0 { pw *= crossPower(base, w, g) }
            return 10 * log10(Swift.max(1e-30, pw))
        }
    }
}
