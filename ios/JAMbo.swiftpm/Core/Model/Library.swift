import Foundation

// Библиотека сэмплов, пресетов синта и таблиц WTABLE (S11b, как library.ts веба): дерево папок, общее для всех
// проектов. Дерево — Application Support/Library.json (LibraryStore), байты сэмплов — в хранилище сэмплов (Samples,
// по ключу). Системная папка RECORDINGS — для стемов (S11d): не удаляется и не переименовывается. Удаление узла
// сэмплы с диска не удаляет (на них могут ссылаться проекты; чистка — позже, решение пользователя).

public enum LibKind: String, Codable, Sendable {
    case folder
    case sample
    case preset
    case table
}

public struct LibNode: Codable, Equatable, Sendable {
    public var id: String
    /// Родительская папка (Library.root — корень).
    public var parent: String
    public var kind: LibKind
    public var name: String
    /// Сэмпл — ключ в хранилище сэмплов; таблица — ключ таблицы («wt:<ключ>:<кадр>»).
    public var key: String?
    public var preset: SynthPreset?
    public var system: Bool?
    /// Время изменения, с от 1970.
    public var updated: Double

    public init(id: String, parent: String, kind: LibKind, name: String, key: String? = nil, preset: SynthPreset? = nil,
                system: Bool? = nil, updated: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.parent = parent
        self.kind = kind
        self.name = name
        self.key = key
        self.preset = preset
        self.system = system
        self.updated = updated
    }

    public var isSystem: Bool { return system ?? false }
}

public struct Library: Codable, Equatable, Sendable {
    public static let root = "root"
    public static let recordings = "recordings"
    /// Длина имён в библиотеке (CLAUDE.md: 40 знаков).
    public static let nameLimit = 40

    public var nodes: [LibNode] = []

    public init(nodes: [LibNode] = []) {
        self.nodes = nodes
        ensureRecordings()
    }

    enum CodingKeys: String, CodingKey { case nodes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodes = c.value(.nodes, [LibNode]())
        ensureRecordings()
    }

    mutating func ensureRecordings() {
        if nodes.contains(where: { $0.id == Library.recordings }) { return }
        nodes.insert(LibNode(id: Library.recordings, parent: Library.root, kind: .folder, name: "RECORDINGS", system: true,
                             updated: 0),
                     at: 0)
    }

    public static func newId() -> String {
        let t: String = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r: String = String(Int.random(in: 0..<(36 * 36 * 36 * 36 * 36)), radix: 36)
        return "n" + t + r
    }

    public func node(_ id: String) -> LibNode? {
        return nodes.first { $0.id == id }
    }

    /// Содержимое папки: сначала системные (RECORDINGS), потом папки, потом остальное; по имени (числа — по значению).
    public func children(_ parent: String) -> [LibNode] {
        let list: [LibNode] = nodes.filter { $0.parent == parent }
        return list.sorted { a, b in
            let ra: Int = Library.rank(a)
            let rb: Int = Library.rank(b)
            if ra != rb { return ra < rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func rank(_ n: LibNode) -> Int {
        if n.isSystem { return 0 }
        return n.kind == .folder ? 1 : 2
    }

    /// Путь к папке: от корня до неё (корень не входит).
    public func path(_ id: String) -> [LibNode] {
        var out: [LibNode] = []
        var cur: LibNode? = node(id)
        var guardCount = 0
        while let n = cur, guardCount < 64 {
            out.insert(n, at: 0)
            cur = node(n.parent)
            guardCount += 1
        }
        return out
    }

    /// Имя из поля ввода: без пробелов по краям, не длиннее 40; пустое — Untitled.
    public static func clean(_ name: String) -> String {
        let t: String = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        return t.isEmpty ? "Untitled" : t
    }

    /// Имя без повтора в папке: «Name», «Name 2», …
    public func uniqueName(_ parent: String, _ name: String, except: String? = nil) -> String {
        let base: String = Library.clean(name)
        let taken = Set(nodes.filter { $0.parent == parent && $0.id != except }.map { $0.name })
        if !taken.contains(base) { return base }
        var k = 2
        while taken.contains("\(base) \(k)") { k += 1 }
        return "\(base) \(k)"
    }

    /// Сэмпл или пресет с таким же именем в папке (вопрос при сохранении: перезаписать или сохранить как).
    public func sameName(_ parent: String, _ name: String) -> LibNode? {
        let base: String = Library.clean(name)
        return nodes.first { $0.parent == parent && $0.kind != .folder && $0.name == base }
    }

    /// Сколько всего внутри папки (с вложенными).
    public func countInside(_ id: String) -> Int {
        var n = 0
        for x in nodes where x.parent == id {
            n += 1
            if x.kind == .folder { n += countInside(x.id) }
        }
        return n
    }

    // MARK: — правки

    @discardableResult
    public mutating func createFolder(_ parent: String, _ name: String) -> LibNode {
        let n = LibNode(id: Library.newId(), parent: parent, kind: .folder, name: uniqueName(parent, name))
        nodes.append(n)
        return n
    }

    /// Сэмпл в папку (тот же сэмпл в той же папке не повторяется).
    @discardableResult
    public mutating func addSample(_ parent: String, key: String, name: String) -> LibNode {
        if let same = nodes.first(where: { $0.parent == parent && $0.kind == .sample && $0.key == key }) { return same }
        let n = LibNode(id: Library.newId(), parent: parent, kind: .sample, name: uniqueName(parent, name), key: key)
        nodes.append(n)
        return n
    }

    /// Таблица WTABLE в папку (та же в той же папке не повторяется).
    @discardableResult
    public mutating func addTable(_ parent: String, key: String, name: String) -> LibNode {
        if let same = nodes.first(where: { $0.parent == parent && $0.kind == .table && $0.key == key }) { return same }
        let n = LibNode(id: Library.newId(), parent: parent, kind: .table, name: uniqueName(parent, name), key: key)
        nodes.append(n)
        return n
    }

    @discardableResult
    public mutating func addPreset(_ parent: String, _ preset: SynthPreset) -> LibNode {
        let name: String = uniqueName(parent, preset.name)
        var p = preset
        p.name = name
        let n = LibNode(id: Library.newId(), parent: parent, kind: .preset, name: name, preset: p)
        nodes.append(n)
        return n
    }

    /// Перезаписать сэмпл или пресет: имя и место те же, содержимое новое (сэмпл может стать пресетом и наоборот).
    public mutating func overwrite(_ id: String, with item: FolderItem) {
        guard let k = nodes.firstIndex(where: { $0.id == id }), nodes[k].kind != .folder else { return }
        if var p = item.preset {
            p.name = nodes[k].name
            nodes[k].kind = .preset
            nodes[k].preset = p
            nodes[k].key = nil
        } else {
            nodes[k].kind = .sample
            nodes[k].key = item.sample
            nodes[k].preset = nil
        }
        nodes[k].updated = Date().timeIntervalSince1970
    }

    public mutating func rename(_ id: String, to name: String) {
        guard let k = nodes.firstIndex(where: { $0.id == id }), !nodes[k].isSystem,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let n: String = uniqueName(nodes[k].parent, name, except: id)
        nodes[k].name = n
        nodes[k].preset?.name = n
        nodes[k].updated = Date().timeIntervalSince1970
    }

    /// Удалить узел (папку — со всем содержимым). Системные не удаляются.
    public mutating func remove(_ id: String) {
        guard let n = node(id), !n.isSystem else { return }
        var gone: Set<String> = [id]
        var grew = true
        while grew {
            grew = false
            for x in nodes where !gone.contains(x.id) && gone.contains(x.parent) {
                gone.insert(x.id)
                grew = true
            }
        }
        nodes.removeAll { gone.contains($0.id) }
    }
}

/// Библиотека на диске: один JSON, запись атомарная.
public struct LibraryStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Application Support/Library.json.
    public static func appFile() -> URL {
        let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Library.json")
    }

    /// Нет файла или он не читается — пустая библиотека (с RECORDINGS).
    public func load() -> Library {
        guard let data = try? Data(contentsOf: url), let lib = try? JSONDecoder().decode(Library.self, from: data) else {
            return Library()
        }
        return lib
    }

    @discardableResult
    public func save(_ lib: Library) -> Bool {
        guard let data = try? JSONEncoder().encode(lib) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// Виртуальная папка встроенных таблиц WTABLE (в LOAD TABLE, в корне; в файле библиотеки её нет).
public enum LibraryBuiltins {
    public static let folderId = "builtin-tables"
    public static let folder = LibNode(id: folderId, parent: Library.root, kind: .folder, name: "BUILT-IN TABLES",
                                       system: true, updated: 0)
    public static let tables: [LibNode] = WavetableKey.builtins.map { name in
        LibNode(id: "bt:" + name, parent: folderId, kind: .table, name: name, key: WavetableKey.builtin(name),
                system: true, updated: 0)
    }
}

// MARK: — записи (S11d)

extension Library {
    /// Папка записей проекта и дня в RECORDINGS: «проект дд.мм.гггг» (без имени — Project).
    public static func recordingFolderName(project: String, date: Date, calendar: Calendar = .current) -> String {
        let c: DateComponents = calendar.dateComponents([.day, .month, .year], from: date)
        let d: String = String(format: "%02d.%02d.%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2000)
        let p: String = project.trimmingCharacters(in: .whitespaces)
        return (p.isEmpty ? "Project" : p) + " " + d
    }

    /// Имя записи: «дорожка чч-мм-сс», «MASTER чч-мм-сс».
    public static func recordingName(_ base: String, date: Date, calendar: Calendar = .current) -> String {
        let c: DateComponents = calendar.dateComponents([.hour, .minute, .second], from: date)
        return base + " " + String(format: "%02d-%02d-%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Папка записей с этим именем в RECORDINGS (одна на проект и день; создаётся при первой записи) — id.
    public mutating func recordingsFolder(_ name: String) -> String {
        if let have = nodes.first(where: { $0.parent == Library.recordings && $0.kind == .folder && $0.name == name }) {
            return have.id
        }
        return createFolder(Library.recordings, name).id
    }
}
