// Движки синта (как SYNTH_ENGINES, synthKey, synthEngine в src/params.ts веба): звук дорожки или шага «mi:<n>».
// Свои движки DRUM, ANALOG, FM, WTABLE (16–19); движков Mutable Instruments (0–15) нет.

/// Движок: номер (ключ звука mi:<n>), короткое имя (меню), полное (окно синта), подписи ручек 1.1–1.3 и пункты
/// ступенчатой 1.1. decay — затухает сам (DRUM): огибающая дорожки только с атакой.
public struct SynthEngine: Sendable {
    public let id: Int
    public let name: String
    public let full: String
    public let harm: String
    public let timbre: String
    public let morph: String
    public let options: [String]
    public var decay = false
    /// Свой предел ручки Decay, мс (у DRUM — 1000).
    public var decayMax: Double? = nil
    /// Ручки 1.1–1.3 (harm, timbre, morph), которые ставятся при выборе движка на дорожку с другого звука.
    public var initKnobs: [Double] = []
}

public enum SynthEngines {
    /// Свои движки JAMbo (Core/Jambo). Номера 0–15 (движки Mutable Instruments) не заняты: такие звуки — пустые.
    public static let all: [SynthEngine] = [
        // DRUM — бочка (высота — ручкой PITCH, монофонична), ANALOG — по умолчанию чистый синус.
        SynthEngine(id: 16, name: "DRUM", full: "Drum", harm: "pitch", timbre: "sweep", morph: "drive", options: [],
                    decay: true, decayMax: 1000),
        SynthEngine(id: 17, name: "ANALOG", full: "Analog", harm: "wave", timbre: "detune", morph: "sub",
                    options: ["Sine", "Triangle", "Saw", "Square"], initKnobs: [12.5, 0, 0]),
        SynthEngine(id: 18, name: "FM", full: "FM", harm: "ratio", timbre: "index", morph: "contour", options: []),
        // WTABLE: таблица — у дорожки (Track.table), в окне синта вместо иконки — кадр таблицы.
        SynthEngine(id: 19, name: "WTABLE", full: "Wavetable", harm: "position", timbre: "warp", morph: "unison",
                    options: []),
    ]

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
    /// Синт на дорожку (setTrackSynth веба): звук дорожки — «mi:<n>»; ручки Harmonics, Timbre, Morph остаются,
    /// кроме своих начальных у движка (ANALOG — синус без DETUNE и SUB) при переходе с другого звука; Decay больше
    /// предела движка (DRUM — 1000 мс) — к пределу.
    public mutating func setSynth(_ engine: Int) {
        let key = SynthKey.key(engine)
        let was = sample
        sample = key
        guard let e = SynthEngines.engine(engine) else { return }
        if e.initKnobs.count == 3 && was != key {
            params["harm"] = e.initKnobs[0]
            params["timbre"] = e.initKnobs[1]
            params["morph"] = e.initKnobs[2]
        }
        if let max = e.decayMax, let d = params["decay"], d > max { params["decay"] = max }
    }
}
