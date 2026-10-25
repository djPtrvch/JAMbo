// Движки синта (как SYNTH_ENGINES, synthKey, synthEngine в src/params.ts веба): звук дорожки или шага «mi:<n>».
// Свои движки KICK, ANALOG, FM, WTABLE (16–19); движков Mutable Instruments (0–15) нет.

/// Движок: номер (ключ звука mi:<n>), короткое имя (меню), полное (окно синта), подписи ручек 1.1–1.4 и пункты
/// ступенчатых ручек (пустой список — плавная). decay — затухает сам (KICK): огибающая дорожки только с атакой.
public struct SynthEngine: Sendable {
    public let id: Int
    public let name: String
    public let full: String
    /// Подписи ручек 1.1–1.4 (harm, timbre, morph, p4).
    public let knobs: [String]
    /// Пункты ступенчатых ручек 1.1–1.4.
    public let options: [[String]]
    public var decay = false
    /// Свой предел ручки Decay, мс (у KICK — 1000).
    public var decayMax: Double? = nil
    /// Ручки 1.1–1.4, которые ставятся при выборе движка на дорожку с другого звука.
    public var initKnobs: [Double] = []
}

public enum SynthEngines {
    /// Ручки 1.1–1.4 синта в проекте.
    public static let knobIds: [String] = ["harm", "timbre", "morph", "p4"]
    static let waves: [String] = ["Sine", "Triangle", "Saw", "Square"]

    /// Свои движки JAMbo (Core/Jambo). Номера 0–15 (движки Mutable Instruments) не заняты: такие звуки — пустые.
    public static let all: [SynthEngine] = [
        // KICK — бочка (ключ звука прежний, mi:16; высота — ручкой PITCH, монофонична).
        SynthEngine(id: 16, name: "KICK", full: "Kick", knobs: ["pitch", "sweep", "drive", "click"],
                    options: [[], [], [], []], decay: true, decayMax: 1000),
        // ANALOG: два осциллятора A и B; при выборе — синусы без DETUNE, MIX 50 %.
        SynthEngine(id: 17, name: "ANALOG", full: "Analog", knobs: ["wave A", "wave B", "detune", "mix"],
                    options: [waves, waves, [], []], initKnobs: [12.5, 12.5, 0, 50]),
        SynthEngine(id: 18, name: "FM", full: "FM", knobs: ["ratio", "index", "contour", "feedback"],
                    options: [[], [], [], []]),
        // WTABLE: таблица — у дорожки (Track.table), в окне синта вместо иконки — кадр таблицы.
        SynthEngine(id: 19, name: "WTABLE", full: "Wavetable", knobs: ["position", "warp", "unison", "detune"],
                    options: [[], [], ["1", "3", "5"], []]),
        // Ударные (этап 3): затухают сами, монофоничны; Decay — длина звука, своя шкала (предел — decayMax).
        SynthEngine(id: 20, name: "SNARE", full: "Snare", knobs: ["tune", "snappy", "tone", "punch"],
                    options: [[], [], [], []], decay: true, decayMax: 800),
        SynthEngine(id: 21, name: "HAT", full: "Hi-hat", knobs: ["tune", "spread", "tone", "noise"],
                    options: [[], [], [], []], decay: true, decayMax: 1500),
        SynthEngine(id: 22, name: "CLAP", full: "Clap", knobs: ["tone", "bursts", "spread", "tail"],
                    options: [[], ["1", "2", "3", "4", "5", "6"], [], []], decay: true, decayMax: 1200),
        SynthEngine(id: 23, name: "PERC", full: "Percussion", knobs: ["tune", "material", "bend", "hit"],
                    options: [[], [], [], []], decay: true, decayMax: 2000),
        // SUB (этап 4): моно-бас, OSC2 — октавой ниже; при выборе — треугольник, SUB 40 %, без FAT и GRIT.
        SynthEngine(id: 24, name: "SUB", full: "Sub bass", knobs: ["wave", "sub", "fat", "grit"],
                    options: [["Triangle", "Saw", "Square"], [], [], []], initKnobs: [100.0 / 6, 40, 0, 0]),
    ]

    /// Колонки меню звука: DRUMS и SYNTH (номера движков).
    public static let drums: [Int] = [16, 20, 21, 22, 23]
    public static let synths: [Int] = [17, 24, 18, 19]

    /// Размер таблиц по номеру движка (наибольший номер + 1).
    public static let count: Int = (all.map { $0.id }.max() ?? -1) + 1

    /// Движок по номеру (по таблице count); nil — номер не занят.
    public static let byId: [SynthEngine?] = (0..<count).map { id in all.first { $0.id == id } }

    public static func engine(_ id: Int) -> SynthEngine? {
        return id >= 0 && id < count ? byId[id] : nil
    }

    static func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return String(f).uppercased() + s.dropFirst()
    }
}

/// Ключ звука синта: «mi:<n>» — движок n (как synthKey / synthEngine веба).
public enum SynthKey {
    public static func key(_ engine: Int) -> String { return "mi:\(engine)" }

    /// Номер движка из ключа звука; не синт или неизвестный номер — nil.
    public static func engine(_ key: String) -> Int? {
        guard key.hasPrefix("mi:"), let n = Int(key.dropFirst(3)), SynthEngines.engine(n) != nil else { return nil }
        return n
    }

    /// Звук синта, движка которого нет (mi:0…mi:15 — Mutable Instruments): загружается пустым.
    public static func isRemoved(_ key: String) -> Bool {
        return key.hasPrefix("mi:") && engine(key) == nil
    }
}

extension Track {
    /// Синт на дорожку (setTrackSynth веба): звук дорожки — «mi:<n>»; ручки 1.1–1.4 остаются, кроме своих начальных
    /// у движка (ANALOG — синусы без DETUNE, MIX 50 %) при переходе с другого звука; Decay больше предела движка
    /// (KICK — 1000 мс) — к пределу.
    /// defaults — свои значения ручек по умолчанию: при смене звука ручки движка встают на них (поверх initKnobs).
    public mutating func setSynth(_ engine: Int, defaults: KnobDefaults? = nil) {
        let key = SynthKey.key(engine)
        let was = sample
        sample = key
        guard let e = SynthEngines.engine(engine) else { return }
        if e.initKnobs.count == 4 && was != key {
            for k in 0..<4 { params[SynthEngines.knobIds[k]] = e.initKnobs[k] }
        }
        if was != key { defaults?.applySound(to: &self) }
        if let max = e.decayMax, let d = params["decay"], d > max { params["decay"] = max }
    }
}
