import Foundation

// Пресет синта и звук папки дорожки (S11b). Пресет — движок (ключ звука
// «mi:<n>»), ручки звука (presetParams), у WTABLE — таблица, у GRANULAR — сэмпл. В папке дорожки — сэмплы и пресеты
// (копии).

/// Пресет синта: имя, движок, ручки; fmt — версия формата (2 — первая; 3 — S12, ручки 1.4 своих движков; 4 — ручки
/// GRANULAR по ТЗ «Granular»; 5 — Filter на всём ходу и тип фильтра, 9.11).
public struct SynthPreset: Codable, Equatable, Sendable {
    public var name: String
    public var sound: String
    public var params: [String: Double]
    public var fmt: Int?
    /// Таблица WTABLE ("" — BASIC, «builtin:…», своя — «wt:<ключ>:<кадр>»); nil — не WTABLE.
    public var table: String?
    /// Сэмпл GRANULAR (ключ хранилища); nil — не GRANULAR.
    public var grain: String?
    /// Модуляция (14.11, решение пользователя): ручки LFO1–3 и ENV (Params.modIds, LFO по темпу) и назначения LFO/ENV
    /// на ручки звука; nil — прежний пресет без модуляции: у дорожки она остаётся как была.
    public var mods: [String: Double]?
    public var assigns: [String: ModAssign]?

    public init(name: String, sound: String, params: [String: Double], fmt: Int? = 5, table: String? = nil,
                grain: String? = nil) {
        self.name = name
        self.sound = sound
        self.params = params
        self.fmt = fmt
        self.table = table
        self.grain = grain
    }

    /// Ручки звука, которые хранит пресет , тип фильтра (нет — LP); у ANALOG — ещё режим
    /// модуляции и октава B (AnalogMod; нет в пресете — выключены).
    public static let params: [String] = ["harm", "timbre", "morph", "p4", "level", "attack", "decay", "filter", "reso",
                                          Params.filterTypeId, AnalogMod.modId, AnalogMod.octId]

    /// Значение ручки id пресета: скрытые значения ANALOG, которых в пресете нет (старый пресет), — 0 (выключены);
    /// у других движков их нет (nil).
    public func value(_ id: String) -> Double? {
        if let v = params[id] { return v }
        // Тип фильтра: нет в пресете с ручкой Filter — LP.
        if id == Params.filterTypeId && params["filter"] != nil { return Double(FilterType.lp) }
        if AnalogMod.ids.contains(id) && SynthKey.engine(sound) == Jambo.analog { return 0 }
        return nil
    }


    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        name = c.value(CaseKey("name"), "")
        sound = c.value(CaseKey("sound"), "")
        params = c.value(CaseKey("params"), [String: Double]())
        fmt = c.optional(CaseKey("fmt"))
        // fmt < 3 — до S12: ручки своих движков по SynthMigration (1.4).
        if (fmt ?? 1) < 3 {
            SynthMigration.params(sound, &params)
            fmt = 3
        }
        // fmt < 4 — ручки GRANULAR по прежним формулам (GranularMigration).
        if (fmt ?? 1) < 4 {
            GranularMigration.params(sound, &params)
            fmt = 4
        }
        // fmt < 5 — прежняя двухполярная ручка Filter: тип и частота на всём ходу (FilterMigration, 9.11).
        if (fmt ?? 1) < 5 {
            FilterMigration.preset(&params)
            fmt = 5
        }
        table = c.optional(CaseKey("table"))
        grain = c.optional(CaseKey("grain"))
        mods = c.optional(CaseKey("mods"))
        assigns = c.optional(CaseKey("assigns"))
    }
}

/// Звук папки дорожки: сэмпл (ключ) или пресет синта. В файле: { sample } или { preset };
/// прежние файлы Swift-версии (S2–S11a) — строкой (ключ сэмпла или «mi:<n>»).
public struct FolderItem: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public var sample: String?
    /// Пресет «в коробке» (9.11, объём сборки): копия и сравнение папки не тянут пресет по значению.
    var presetBox: [SynthPreset] = []
    public var preset: SynthPreset? {
        get { return presetBox.first }
        set { presetBox = newValue.map { [$0] } ?? [] }
    }

    public init(sample: String) {
        self.sample = sample
    }

    public init(preset: SynthPreset) {
        sample = nil
        presetBox = [preset]
    }

    public init(stringLiteral value: String) {
        self.init(sample: value)
    }

    /// Ключ звука: сэмпл или движок пресета.
    public var key: String { return sample ?? preset?.sound ?? "" }


    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            self.init(sample: s)
            return
        }
        let c = try decoder.container(keyedBy: CaseKey.self)
        if let p: SynthPreset = c.optional(CaseKey("preset")) {
            self.init(preset: p)
        } else {
            self.init(sample: c.value(CaseKey("sample"), ""))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        if let p = preset { try c.encode(p, forKey: CaseKey("preset")) } else { try c.encode(sample ?? "", forKey: CaseKey("sample")) }
    }
}

extension SynthPreset {
    /// Запись — как прежняя синтезированная, по тем же ключам (общий CaseKey; объём сборки, 18.11).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(name, forKey: CaseKey("name"))
        try c.encode(sound, forKey: CaseKey("sound"))
        try c.encode(params, forKey: CaseKey("params"))
        try c.encodeIfPresent(fmt, forKey: CaseKey("fmt"))
        try c.encodeIfPresent(table, forKey: CaseKey("table"))
        try c.encodeIfPresent(grain, forKey: CaseKey("grain"))
        try c.encodeIfPresent(mods, forKey: CaseKey("mods"))
        try c.encodeIfPresent(assigns, forKey: CaseKey("assigns"))
    }
}
