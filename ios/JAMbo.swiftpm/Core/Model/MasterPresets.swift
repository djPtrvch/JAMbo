import Foundation

// Пресеты модулей мастера (кнопка PRESETS в окнах SAT, COMP, CLIP, LIM — по образцу пресетов EQ веба): общие для
// проектов, хранятся отдельно от проекта (UserDefaults, JSON), у каждого модуля свой список. Пресет — значения
// параметров модуля (MasterChain.ids с префиксом модуля), без BYPASS.

public struct MasterPreset: Codable, Equatable, Sendable {
    public var name: String
    public var values: [String: Double]

    public init(name: String, values: [String: Double]) {
        self.name = name
        self.values = values
    }
}

public struct MasterPresetBook: Codable, Equatable, Sendable {
    /// Модули по номерам MasterScope: SAT 0, COMP 1, CLIP 2, LIM 3.
    public static let prefixes: [String] = ["sat.", "cmp.", "clip.", "lim."]
    public static let titles: [String] = ["SAT", "COMP", "CLIP", "LIM"]
    /// Длина имени (библиотека — 40 знаков).
    public static let nameMax = 40

    public var lists: [[MasterPreset]] = [[], [], [], []]

    public init() {}

    /// Параметры модуля m (в порядке MasterChain.ids).
    public static func ids(_ m: Int) -> [String] {
        let pre: String = prefixes[Swift.max(0, Swift.min(3, m))]
        return MasterChain.ids.map { $0.id }.filter { $0.hasPrefix(pre) }
    }

    public func list(_ m: Int) -> [MasterPreset] {
        return m >= 0 && m < lists.count ? lists[m] : []
    }

    /// Имя нового пресета: «LIM 1», «LIM 2»… (не занятое).
    public func nextName(_ m: Int) -> String {
        let names: Set<String> = Set(list(m).map { $0.name })
        var k: Int = list(m).count + 1
        while names.contains("\(MasterPresetBook.titles[m]) \(k)") { k += 1 }
        return "\(MasterPresetBook.titles[m]) \(k)"
    }

    /// Имя после ввода: без пробелов по краям, не длиннее nameMax; пустое — nil.
    static func clean(_ name: String) -> String? {
        let t: String = String(name.trimmingCharacters(in: .whitespaces).prefix(MasterPresetBook.nameMax))
        return t.isEmpty ? nil : t
    }

    /// Пресет модуля m с тем же именем (без учёта регистра), кроме except; nil — имя свободно.
    public func index(_ m: Int, named name: String, except: Int = -1) -> Int? {
        guard let n = MasterPresetBook.clean(name)?.lowercased() else { return nil }
        let l: [MasterPreset] = list(m)
        return l.indices.first { $0 != except && l[$0].name.lowercased() == n }
    }

    /// Сохранить параметры модуля m из значений мастера проекта (пустое имя — nextName).
    /// over — заменить пресет с этим номером (OVERWRITE).
    public mutating func save(_ m: Int, name: String, master: [String: Double], over: Int? = nil) {
        guard m >= 0 && m < lists.count else { return }
        let defs: [String: Double] = MasterChain.defaultValues()
        var v: [String: Double] = [:]
        for id in MasterPresetBook.ids(m) { v[id] = master[id] ?? defs[id] ?? 0 }
        let n: String = MasterPresetBook.clean(name) ?? nextName(m)
        let p = MasterPreset(name: n, values: v)
        if let k = over, k >= 0 && k < lists[m].count {
            lists[m][k] = p
        } else {
            lists[m].append(p)
        }
    }

    public mutating func rename(_ m: Int, _ k: Int, to name: String) {
        guard m >= 0 && m < lists.count && k >= 0 && k < lists[m].count, let n = MasterPresetBook.clean(name) else { return }
        lists[m][k].name = n
    }

    public mutating func delete(_ m: Int, _ k: Int) {
        guard m >= 0 && m < lists.count && k >= 0 && k < lists[m].count else { return }
        lists[m].remove(at: k)
    }

    /// Загрузить пресет k модуля m в значения мастера: параметры модуля — из пресета (нет в пресете — по умолчанию),
    /// остальные не меняются.
    public func apply(_ m: Int, _ k: Int, to master: inout [String: Double]) {
        guard k >= 0 && k < list(m).count else { return }
        let p: MasterPreset = lists[m][k]
        let defs: [String: Double] = MasterChain.defaultValues()
        for id in MasterPresetBook.ids(m) {
            if let v = p.values[id] ?? defs[id] { master[id] = v }
        }
    }

    /// Чтение из JSON: повреждённое — пустые списки; недостающие модули — пустые.
    public static func decode(_ data: Data?) -> MasterPresetBook {
        guard let data = data, var b = try? JSONDecoder().decode(MasterPresetBook.self, from: data) else {
            return MasterPresetBook()
        }
        while b.lists.count < 4 { b.lists.append([]) }
        return b
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }
}
