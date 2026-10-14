import Foundation

// Настройки приложения (как settings.ts веба): хранятся отдельно от проектов (UserDefaults, JSON), общие для проектов.

public struct RecordSettings: Codable, Equatable, Sendable {
    /// ON — нота на ближайший шаг, OFF — на шаг, в котором нажали.
    public var quantize: Bool = true
    /// OFF — шаги, по которым проходит запись, очищаются; ON — ноты добавляются.
    public var overdub: Bool = false
    /// Запись автоматизации с REC (S8).
    public var autoRec: Bool = true

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

    public init() {}

    /// Чтение из JSON: неизвестные и недостающие поля — значения по умолчанию.
    public static func decode(_ data: Data?) -> AppSettings {
        guard let data = data, let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    private enum Keys: String, CodingKey { case appearance, pianoOctaves, velocity, record }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        appearance = (try? c.decode(String.self, forKey: .appearance)) ?? "SYSTEM"
        pianoOctaves = (try? c.decode(Int.self, forKey: .pianoOctaves)) ?? 2
        velocity = (try? c.decode(Bool.self, forKey: .velocity)) ?? false
        record = (try? c.decode(RecordSettings.self, forKey: .record)) ?? RecordSettings()
    }
}
