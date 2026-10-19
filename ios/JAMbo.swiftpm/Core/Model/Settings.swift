import Foundation

// Настройки приложения (как settings.ts веба): хранятся отдельно от проектов (UserDefaults, JSON), общие для проектов.

public struct RecordSettings: Codable, Equatable, Sendable {
    /// ON — нота на ближайший шаг, OFF — на шаг, в котором нажали.
    public var quantize: Bool = true
    /// OFF — шаги, по которым проходит запись, очищаются; ON — ноты добавляются.
    public var overdub: Bool = false
    /// Запись автоматизации с REC (S13).
    public var autoRec: Bool = true

    public init() {}
}

/// SETTINGS → SIDECHAIN: какие посылы приглушаются вместе с дорожкой (по умолчанию только Drive).
public struct SidechainSends: Codable, Equatable, Sendable {
    public var rev: Bool = false
    public var dly: Bool = false
    public var drv: Bool = true

    public init() {}
}

public struct AppSettings: Codable, Equatable, Sendable {
    /// SYSTEM, LIGHT или DARK.
    public var appearance: String = "SYSTEM"
    /// Октав гаммы на клавишах клавиатуры: 1 или 2.
    public var pianoOctaves: Int = 2
    /// Чувствительность клавиш к нажатию.
    public var velocity: Bool = false
    public var record = RecordSettings()
    /// SETTINGS → SAMPLER → SLICE NOTES: ноты маркеров нарезки по порядку.
    public var sliceMap: SliceMap = .chromatic
    /// SETTINGS → SIDECHAIN: посылы Reverb, Delay, Drive приглушаются огибающей.
    public var scSends = SidechainSends()
    /// SETTINGS → SIDECHAIN → MUTE TAILS (в вебе — AUDIO ENGINE): заглушили единственный источник посыла Delay —
    /// его повторы гасятся.
    public var muteTails: Bool = false
    /// FX и MOD в режиме toggle (SHIFT + двойной тап по кнопке): тап включает страницу, следующий — выключает.
    public var latchFx: Bool = false
    public var latchMod: Bool = false
    /// Пианоролл (S8): GRID — шагов в клетке (1, 2, 4); звук ноты при нажатии.
    public var rollGrid: Int = Roll.gridDef
    public var rollSound: Bool = true
    /// SETTINGS → LEVEL (S9): регулятор справа у дорожки — ABSOLUTE (громкость MIX) или RELATIVE (подстройка
    /// Track.trim вниз от громкости MIX).
    public var levelRelative: Bool = false
    /// SETTINGS → MORPH (S9): ручки в режиме MORPH — на все дорожки (сдвиг на ту же величину) или на выбранную;
    /// возврат после выключения — MorphReturn.beats[morphReturn] долей (0 — сразу).
    public var morphAll: Bool = false
    public var morphReturn: Int = 0
    /// SETTINGS → MIX (S9, действуют с переходами S10): гамма и нота нового проекта при переходе; кроссфейдер
    /// (ON — темп по кроссфейдеру, OFF — темп старого паттерна).
    public var mixKey: Bool = true
    public var mixCrossfader: Bool = true
    /// SETTINGS → SAMPLER (S11b): загрузка звуков из библиотеки на дорожку снимает её сэмпл-локи (шаги со своим
    /// сэмплом играют звук дорожки своей нотой); пресет-локи остаются.
    public var clearSampleLocks: Bool = true
    /// SETTINGS → SAMPLER → PITCH (S12): ручка Pitch сэмпла и её p-lock — по полутонам (по умолчанию) или плавно.
    public var pitchSemitones: Bool = true
    /// Бутерброд → MIDI (S13): вход, обратная связь, ноты.
    public var midi = MidiSettings()

    public init() {}

    /// Чтение из JSON: неизвестные и недостающие поля — значения по умолчанию.
    public static func decode(_ data: Data?) -> AppSettings {
        guard let data = data, let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    private enum Keys: String, CodingKey { case appearance, pianoOctaves, velocity, record, sliceMap, scSends, muteTails, latchFx, latchMod, rollGrid,
                                         rollSound, levelRelative, morphAll, morphReturn, mixKey, mixCrossfader,
                                         clearSampleLocks, pitchSemitones, midi }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        appearance = (try? c.decode(String.self, forKey: .appearance)) ?? "SYSTEM"
        pianoOctaves = (try? c.decode(Int.self, forKey: .pianoOctaves)) ?? 2
        velocity = (try? c.decode(Bool.self, forKey: .velocity)) ?? false
        record = (try? c.decode(RecordSettings.self, forKey: .record)) ?? RecordSettings()
        sliceMap = (try? c.decode(SliceMap.self, forKey: .sliceMap)) ?? .chromatic
        scSends = (try? c.decode(SidechainSends.self, forKey: .scSends)) ?? SidechainSends()
        muteTails = (try? c.decode(Bool.self, forKey: .muteTails)) ?? false
        latchFx = (try? c.decode(Bool.self, forKey: .latchFx)) ?? false
        latchMod = (try? c.decode(Bool.self, forKey: .latchMod)) ?? false
        let g: Int = (try? c.decode(Int.self, forKey: .rollGrid)) ?? Roll.gridDef
        rollGrid = Roll.grids.contains(g) ? g : Roll.gridDef
        rollSound = (try? c.decode(Bool.self, forKey: .rollSound)) ?? true
        levelRelative = (try? c.decode(Bool.self, forKey: .levelRelative)) ?? false
        morphAll = (try? c.decode(Bool.self, forKey: .morphAll)) ?? false
        let mr: Int = (try? c.decode(Int.self, forKey: .morphReturn)) ?? 0
        morphReturn = mr >= 0 && mr < MorphReturn.beats.count ? mr : 0
        mixKey = (try? c.decode(Bool.self, forKey: .mixKey)) ?? true
        mixCrossfader = (try? c.decode(Bool.self, forKey: .mixCrossfader)) ?? true
        clearSampleLocks = (try? c.decode(Bool.self, forKey: .clearSampleLocks)) ?? true
        pitchSemitones = (try? c.decode(Bool.self, forKey: .pitchSemitones)) ?? true
        midi = (try? c.decode(MidiSettings.self, forKey: .midi)) ?? MidiSettings()
    }
}
