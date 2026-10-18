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
    /// Октав гаммы на клавишах пианоролла: 1 или 2.
    public var pianoOctaves: Int = 2
    /// Чувствительность клавиш к нажатию.
    public var velocity: Bool = false
    public var record = RecordSettings()
    /// SETTINGS → SAMPLER → SLICE NOTES: ноты маркеров нарезки по порядку.
    public var sliceMap: SliceMap = .chromatic
    /// SETTINGS → SIDECHAIN: посылы Reverb, Delay, Drive приглушаются огибающей.
    public var scSends = SidechainSends()
    /// MUTE TAILS: заглушили единственный источник посыла Delay — его повторы гасятся.
    public var muteTails: Bool = false
    /// FX и MOD в режиме toggle (SHIFT + двойной тап по кнопке): тап включает страницу, следующий — выключает.
    public var latchFx: Bool = false
    public var latchMod: Bool = false
    /// Пианоролл (S8): GRID — шагов в клетке (1, 2, 4); звук ноты при нажатии.
    public var rollGrid: Int = Roll.gridDef
    public var rollSound: Bool = true

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
                                         rollSound }

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
    }
}
