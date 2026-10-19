import Foundation

// Пресеты маппингов (S13c, строка Preset окна MIDI MAP, как midiPresets веба): набор маппингов под контроллер.
// Хранятся отдельно от настроек (UserDefaults), общие для проектов. Встроенного пресета нет (решение пользователя).

public struct MidiPreset: Codable, Equatable, Sendable {
    public var name: String
    public var mappings: [MidiMapping]

    public init(name: String, mappings: [MidiMapping]) {
        self.name = name
        self.mappings = mappings
    }

    private enum Keys: String, CodingKey { case name, mappings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decode(String.self, forKey: .name)
        let maps: [LossyMapping] = (try? c.decode([LossyMapping].self, forKey: .mappings)) ?? []
        mappings = maps.compactMap { $0.value }
    }
}

public struct MidiPresetBook: Codable, Equatable, Sendable {
    /// Длина имени (библиотека — 40 знаков).
    public static let nameMax = 40

    public var list: [MidiPreset] = []

    public init() {}

    public static func decode(_ data: Data?) -> MidiPresetBook {
        guard let d = data, let b = try? JSONDecoder().decode(MidiPresetBook.self, from: d) else { return MidiPresetBook() }
        return b
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    /// Имя после ввода: без пробелов по краям, не длиннее nameMax; пустое — nil.
    static func clean(_ name: String) -> String? {
        let n: String = String(name.trimmingCharacters(in: .whitespaces).prefix(nameMax))
        return n.isEmpty ? nil : n
    }

    /// Имя нового пресета: «Controller 1», «Controller 2»… (не занятое).
    public var nextName: String {
        let names: Set<String> = Set(list.map { $0.name })
        var k: Int = list.count + 1
        while names.contains("Controller \(k)") { k += 1 }
        return "Controller \(k)"
    }

    public func preset(_ name: String) -> MidiPreset? {
        return list.first { $0.name == name }
    }

    /// Сохранить маппинги под именем (то же имя — перезаписать). Возвращает имя или nil.
    @discardableResult
    public mutating func save(_ name: String, _ mappings: [MidiMapping]) -> String? {
        guard let n = MidiPresetBook.clean(name) else { return nil }
        let p = MidiPreset(name: n, mappings: mappings)
        if let k = list.firstIndex(where: { $0.name == n }) {
            list[k] = p
        } else {
            list.append(p)
        }
        return n
    }

    /// Переименовать (имя занято другим — нет). Возвращает новое имя или nil.
    @discardableResult
    public mutating func rename(_ from: String, to: String) -> String? {
        guard let n = MidiPresetBook.clean(to), let k = list.firstIndex(where: { $0.name == from }) else { return nil }
        if list.contains(where: { $0.name == n }) && n != from { return nil }
        list[k].name = n
        return n
    }

    public mutating func delete(_ name: String) {
        list.removeAll { $0.name == name }
    }
}
