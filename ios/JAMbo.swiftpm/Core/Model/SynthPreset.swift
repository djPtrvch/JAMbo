import Foundation

// Пресет синта и звук папки дорожки (S11b, как Preset и FolderItem в state.ts веба). Пресет — движок (ключ звука
// «mi:<n>»), ручки звука (presetParams) и у WTABLE — таблица. В папке дорожки — сэмплы и пресеты (копии).

/// Пресет синта: имя, движок, ручки; fmt — версия формата веба.
public struct SynthPreset: Codable, Equatable, Sendable {
    public var name: String
    public var sound: String
    public var params: [String: Double]
    public var fmt: Int?
    /// Таблица WTABLE ("" — BASIC, «builtin:…», своя — «wt:<ключ>:<кадр>»); nil — не WTABLE.
    public var table: String?

    public init(name: String, sound: String, params: [String: Double], fmt: Int? = 2, table: String? = nil) {
        self.name = name
        self.sound = sound
        self.params = params
        self.fmt = fmt
        self.table = table
    }

    /// Ручки звука, которые хранит пресет (PRESET_PARAMS веба).
    public static let params: [String] = ["harm", "timbre", "morph", "level", "attack", "decay", "filter", "reso"]

    enum CodingKeys: String, CodingKey, CaseIterable { case name, sound, params, fmt, table }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "")
        // Пресет движка, которого нет (Mutable Instruments, mi:0…mi:15), — пустой (S12).
        let snd: String = c.value(.sound, "")
        sound = SynthKey.isRemoved(snd) ? "" : snd
        params = c.value(.params, [String: Double]())
        fmt = c.optional(.fmt)
        table = c.optional(.table)
    }
}

/// Звук папки дорожки: сэмпл (ключ) или пресет синта. В файле — как в вебе: { sample } или { preset };
/// прежние файлы Swift-версии (S2–S11a) — строкой (ключ сэмпла или «mi:<n>»).
public struct FolderItem: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public var sample: String?
    public var preset: SynthPreset?

    public init(sample: String) {
        self.sample = sample
        preset = nil
    }

    public init(preset: SynthPreset) {
        sample = nil
        self.preset = preset
    }

    public init(stringLiteral value: String) {
        self.init(sample: value)
    }

    /// Ключ звука: сэмпл или движок пресета.
    public var key: String { return sample ?? preset?.sound ?? "" }

    enum CodingKeys: String, CodingKey { case sample, preset }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            self.init(sample: s)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let p: SynthPreset = c.optional(.preset) {
            self.init(preset: p)
        } else {
            self.init(sample: c.value(.sample, ""))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let p = preset { try c.encode(p, forKey: .preset) } else { try c.encode(sample ?? "", forKey: .sample) }
    }
}
