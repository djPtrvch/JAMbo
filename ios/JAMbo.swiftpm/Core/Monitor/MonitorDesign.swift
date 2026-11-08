import Foundation

// Headphone Monitor (ТЗ «Headphone Monitor», фаза 1): монитор-цепочка в конце выхода — только для прослушивания, в
// экспорт, стемы и запись не попадает. Здесь — настройки, пресеты Translation (данные — Resources/TranslationPresets.json)
// и расчёт параметров для колбэка (MonitorChain) в основном потоке.
// Порядок: Mono → Room (пространство пункта TRANSLATION) → Translation EQ (тембр пункта) и Sub-check → Headphone
// Correction (PHONE CURVE) → CORRECT CURVE → Level compensation → Safety limiter. Биквады одинаковы в обоих каналах и
// линейны, поэтому в колбэке идут одним каскадом после комнаты (результат тот же). Crossfeed убран (8.11, решение
// пользователя): колонки без комнаты — пространство с головой FABIAN (Room).

/// Настройки монитор-цепочки (одни на приложение, UserDefaults — словарём, без Codable: объём сборки). Bypass —
/// выключенная коррекция (Eq.on).
public struct MonitorSettings {
    /// CORRECTION (сила коррекции профилем), 0…1.
    public var strength: Double = 1
    /// Пункт TRANSLATION (тембр и пространство; по умолчанию Studio).
    public var translation: String = "Studio"
    public var mono: Bool = false
    public var sub: Bool = false
    /// Ambience — громкость пространства (отражений и хвоста), dB (−60 и ниже — −∞; по умолчанию −6).
    public var ambienceDb: Double = -6
    /// Правится CORRECT CURVE (иначе PHONE CURVE — профиль наушников).
    public var editCorrect: Bool = false
    /// Референс через мастер-цепочку (по умолчанию нет — как прежде: мимо мастера) и через монитор-цепочку (да).
    public var refMaster: Bool = false
    public var refMonitor: Bool = true
    /// Подгонка громкости референса к миксу и ручная подстройка (±12 dB).
    public var refMatch: Bool = true
    public var refTrim: Double = 0

    public init() {}

    /// Из словаря UserDefaults; недостающие и неверные значения — по умолчанию.
    public init(plist d: [String: Any]?) {
        let g: [String: Any] = d ?? [:]
        func num(_ k: String, _ def: Double, _ lo: Double, _ hi: Double) -> Double {
            let v: Double = (g[k] as? NSNumber)?.doubleValue ?? def
            return v.isFinite ? Swift.min(hi, Swift.max(lo, v)) : def
        }
        func flag(_ k: String, _ def: Bool) -> Bool { return (g[k] as? NSNumber)?.boolValue ?? def }
        strength = num("strength", 1, 0, 1)
        translation = g["translation"] as? String ?? "Studio"
        mono = flag("mono", false)
        sub = flag("sub", false)
        editCorrect = flag("editCorrect", false)
        ambienceDb = num("ambienceDb", -6, MonitorSpec.ambienceMin, 0)
        refMaster = flag("refMaster", false)
        refMonitor = flag("refMonitor", true)
        refMatch = flag("refMatch", true)
        refTrim = num("refTrim", 0, -12, 12)
    }

    /// Словарь для UserDefaults.
    public var plist: [String: Any] {
        return ["strength": strength, "translation": translation, "mono": mono,
                "sub": sub, "editCorrect": editCorrect, "ambienceDb": ambienceDb, "refMaster": refMaster, "refMonitor": refMonitor, "refMatch": refMatch,
                "refTrim": refTrim]
    }
}

/// Константы цепочки (стартовые значения ТЗ, подстраиваются на слух).
public enum MonitorSpec {
    /// Ambience на этом и ниже — −∞ (только прямой звук).
    public static let ambienceMin: Double = -60
    /// Ambience, dB → множитель хвоста.
    public static func ambience(_ db: Double) -> Double { return db <= ambienceMin ? 0 : pow(10, db / 20) }
    /// Наибольшее усиление одного фильтра коррекции и предел Level compensation, dB.
    public static let filterMax: Double = 12
    public static let compMax: Double = 12
    /// Sub-check: ФНЧ 4-го порядка, Гц.
    public static let subHz: Double = 120
    /// Потолок лимитера, dBFS, и его отпускание, с.
    public static let ceilingDb: Double = -0.5
    public static let release: Double = 0.05
    /// Плавность: переходы вкл./выкл. (Bypass, Mono, референс мимо цепочки), с; параметры и коэффициенты, с.
    public static let fade: Double = 0.025
    public static let glide: Double = 0.025

    /// Места биквадов: Translation, Sub-check, PHONE CURVE и CORRECT CURVE (полосы со срезами — по ступеням).
    public static let transSlots = 8
    public static let subSlots = 2
    public static let corrSlots = 20
    /// CORRECT CURVE: полос сколько угодно, в звук — первые 32 ступени.
    public static let userSlots = 32
    public static let sections = transSlots + subSlots + corrSlots + userSlots
    /// Параметры для колбэка: коэффициенты (5 на биквад), затем усиление компенсации, Mono (0/1), цепочка включена (0/1).
    public static let compAt = sections * 5
    public static let monoAt = compAt + 1
    public static let onAt = compAt + 2
    public static let size = compAt + 3

    /// Q ступеней Баттерворта 4-го порядка.
    public static let butter4: [Double] = [0.5411961001461969, 1.3065629648763766]
}

/// Пункт TRANSLATION (Resources/TranslationPresets.json): тембр (биквады), Mono и пространство (room — имя комнаты
/// из rooms.json; нет — без пространства). Разбор — JSONSerialization (без
/// Codable: объём сборки).
public struct TranslationPreset {
    public struct Filter {
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
    public var room: String? = nil

    /// Список пресетов из JSON ({"presets": […]}); ошибка — пусто, пресет без имени или фильтр без частоты — пропуск.
    public static func list(_ data: Data?) -> [TranslationPreset] {
        guard let d = data, let root = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let arr = root["presets"] as? [[String: Any]] else { return [] }
        var out: [TranslationPreset] = []
        for p in arr {
            guard let name = p["name"] as? String else { continue }
            var fs: [Filter] = []
            for f in (p["filters"] as? [[String: Any]]) ?? [] {
                guard let type = f["type"] as? String, let hz = (f["freq"] as? NSNumber)?.doubleValue else { continue }
                let g: Double? = (f["gain"] as? NSNumber)?.doubleValue
                let q: Double? = (f["q"] as? NSNumber)?.doubleValue
                let o: Int? = (f["order"] as? NSNumber)?.intValue
                fs.append(Filter(type: type, freq: hz, gain: g, q: q, order: o))
            }
            out.append(TranslationPreset(name: name, mono: (p["mono"] as? NSNumber)?.boolValue, filters: fs,
                                         room: p["room"] as? String))
        }
        return out
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

    /// Параметры для колбэка (MonitorSpec.size значений): eq — профиль наушников, PHONE CURVE (nil — нет; Eq.on false —
    /// Bypass всей цепочки); correct — CORRECT CURVE (своя правка поверх профиля, без CORRECTION).
    /// room — отклик комнаты (Room; nil — без пространства), в компенсации; ambience — громкость хвоста (множитель).
    public static func make(eq: Eq?, settings m: MonitorSettings, correct: Eq?, preset: TranslationPreset?,
                            room: RoomResponse? = nil, ambience: Double = 0, sampleRate sr: Double) -> [Double] {
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
            let u0: Int = c0 + MonitorSpec.corrSlots
            let user: [MonitorBiquad] = MonitorDesign.correction(correct, strength: 1)
            for (k, b) in user.prefix(MonitorSpec.userSlots).enumerated() { coeffs(b, sr, base + (u0 + k) * 5) }
            base[MonitorSpec.monoAt] = (m.mono || (preset?.mono ?? false)) ? 1 : 0
            base[MonitorSpec.onAt] = (eq?.on ?? true) ? 1 : 0
            let db: Double = compensation(base, sr, room, ambience)
            base[MonitorSpec.compAt] = db == 0 ? 1 : pow(10, db / 20)
        }
        return out
    }

    /// Level compensation, dB: минус средняя мощность АЧХ цепочки (биквады для сигнала в центре) с розовым
    /// весом — точки через 1/12 октавы в 20 Гц…20 кГц (равный вес октав), с пределом ±12 dB; 0 — без изменения.
    /// Комната (Room) — мощность её отклика для сигнала в центре (прямая часть + Ambience · хвост).
    static func compensation(_ p: UnsafePointer<Double>, _ sr: Double, _ room: RoomResponse?, _ amb: Double) -> Double {
        var active: [Int] = []
        for k in 0..<MonitorSpec.sections where !isIdentity(p + k * 5) { active.append(k) }
        if active.isEmpty && room == nil { return 0 }
        let points: Int = MonitorDesign.points
        var sum: Double = 0
        for i in 0..<points {
            let w: Double = 2 * Double.pi * MonitorDesign.pointHz(i) / sr
            var pw: Double = 1
            for k in active { pw *= power(p + k * 5, w) }
            if let r = room { pw *= r.power(i, amb) }
            sum += pw
        }
        let mean: Double = sum / Double(points)
        if mean <= 0 { return MonitorSpec.compMax }
        let db: Double = -10 * log10(mean)
        if abs(db) < 0.005 { return 0 }
        return Swift.max(-MonitorSpec.compMax, Swift.min(MonitorSpec.compMax, db))
    }

    /// Точки усреднения: через 1/12 октавы, 20 Гц…20 кГц.
    public static let points = 120

    public static func pointHz(_ i: Int) -> Double {
        return 20 * pow(1000, (Double(i) + 0.5) / Double(MonitorDesign.points))
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

    /// АЧХ всей цепочки (без компенсации и лимитера) на частоте hz для сигнала в центре, dB — для тестов и экрана.
    public static func response(_ p: [Double], hz: Double, sampleRate sr: Double) -> Double {
        return p.withUnsafeBufferPointer { b -> Double in
            guard let base = b.baseAddress else { return 0 }
            let w: Double = 2 * Double.pi * hz / sr
            var pw: Double = 1
            for k in 0..<MonitorSpec.sections { pw *= power(base + k * 5, w) }
            return 10 * log10(Swift.max(1e-30, pw))
        }
    }
}
