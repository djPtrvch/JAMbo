import Foundation

// Пресеты EQ (S7d; кнопка PRESETS строки EQ — как пресеты EQ веба и модулей мастера): один список, общий для
// дорожек, мастера и проектов, хранится отдельно от проекта (UserDefaults, JSON). Пресет — полосы канала со всеми
// полями (тип, частота, усиление, Q, крутизна, M/S, DYN, THRESHOLD, RANGE), без BYPASS (решение пользователя).

public struct EqPreset: Codable, Equatable, Sendable {
    public var name: String
    public var bands: [EqBand?]

    public init(name: String, bands: [EqBand?]) {
        self.name = name
        self.bands = bands
    }

    /// Число полос (в списке — рядом с именем).
    public var count: Int { return bands.filter { $0 != nil }.count }
}

public struct EqPresetBook: Codable, Equatable, Sendable {
    public var list: [EqPreset] = []

    public init() {}

    /// Имя нового пресета: «EQ 1», «EQ 2»… (не занятое).
    public func nextName() -> String {
        let names: Set<String> = Set(list.map { $0.name })
        var k: Int = list.count + 1
        while names.contains("EQ \(k)") { k += 1 }
        return "EQ \(k)"
    }

    /// Сохранить полосы EQ (пустое имя — nextName; длина — как у пресетов мастера, 40 знаков).
    public mutating func save(name: String, eq: Eq) {
        let n: String = MasterPresetBook.clean(name) ?? nextName()
        var bands: [EqBand?] = eq.bands
        while bands.count < EqSpec.bands { bands.append(nil) }
        list.append(EqPreset(name: n, bands: Array(bands.prefix(EqSpec.bands))))
    }

    public mutating func rename(_ k: Int, to name: String) {
        guard k >= 0 && k < list.count, let n = MasterPresetBook.clean(name) else { return }
        list[k].name = n
    }

    public mutating func delete(_ k: Int) {
        guard k >= 0 && k < list.count else { return }
        list.remove(at: k)
    }

    /// Чтение из JSON: повреждённое — пустой список.
    public static func decode(_ data: Data?) -> EqPresetBook {
        guard let data = data, let b = try? JSONDecoder().decode(EqPresetBook.self, from: data) else { return EqPresetBook() }
        return b
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }
}

extension Project {
    /// Загрузить полосы пресета в EQ канала ch (BYPASS не меняется). Источник DYN — дорожка, которой в проекте нет, —
    /// OFF (решение пользователя).
    public mutating func applyEqPreset(_ ch: Int, _ p: EqPreset) {
        let n: Int = tracks.count
        withEq(ch) { e in
            for k in 0..<EqSpec.bands {
                guard var b = k < p.bands.count ? p.bands[k] : nil else {
                    e.bands[k] = nil
                    continue
                }
                if b.dyn > n { b.dyn = -1 }
                e.bands[k] = b
            }
        }
    }
}
