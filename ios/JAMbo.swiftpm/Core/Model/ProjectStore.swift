import Foundation

// Файл проекта и хранилище проектов (S9a; как storage.ts веба, вместо IndexedDB — файлы):
// Application Support/Projects/<id>.json. Сэмплы — отдельно, по ключу (Samples/<ключ>.caf, SampleStore);
// проект ссылается на ключи. Autosave — отдельная запись (id autosave), основную запись меняют только SAVE,
// SAVE AS и RENAME.

/// Запись в списке проектов (без содержимого).
public struct ProjectInfo: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Время изменения, секунды от 1970.
    public var updated: Double
    /// У Autosave — проект, из которого она сделана (SAVE сохраняет в него).
    public var projectId: String?
    public var projectName: String?
    /// Темп, корневая нота и гамма — для строки списка.
    public var bpm: Double = 120
    public var root: Int = 0
    public var scale: Int = 0

    public init(id: String, name: String, updated: Double, projectId: String? = nil, projectName: String? = nil) {
        self.id = id
        self.name = name
        self.updated = updated
        self.projectId = projectId
        self.projectName = projectName
    }

    enum CodingKeys: String, CodingKey { case id, name, updated, projectId, projectName, bpm, root, scale }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        name = c.value(.name, "")
        updated = c.value(.updated, 0)
        projectId = c.optional(.projectId)
        projectName = c.optional(.projectName)
        bpm = c.value(.bpm, 120)
        root = c.value(.root, 0)
        scale = c.value(.scale, 0)
    }
}

/// Файл проекта: формат, версия формата Swift-версии, запись списка, содержимое.
public struct ProjectFile: Codable, Equatable, Sendable {
    public var format: String = ProjectFormat.name
    public var version: Int = ProjectFormat.version
    public var info: ProjectInfo
    public var doc: Project

    public init(info: ProjectInfo, doc: Project) {
        var i = info
        i.bpm = doc.bpm
        i.root = doc.root
        i.scale = doc.scale
        self.info = i
        self.doc = doc
    }
}

public enum ProjectFormat {
    public static let name = "jambo-swift"
    /// Версия формата файла. Новая версия — шаг миграции в migrate (как fromVersion в normalizeDoc веба);
    /// новые поля с значениями по умолчанию миграции не требуют (ProjectCoding).
    public static let version = 1

    /// −∞ (громкость OFF) и прочие нечисловые значения в JSON — строками.
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                 nan: "nan")
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                   nan: "nan")
        return d
    }

    public static func encode(_ file: ProjectFile) -> Data? {
        return try? encoder().encode(file)
    }

    /// Чтение: не файл проекта — nil; прежняя версия — миграция; затем repair.
    public static func decode(_ data: Data) -> ProjectFile? {
        guard let head = try? decoder().decode(Head.self, from: data), head.format == name else { return nil }
        var bytes = data
        if head.version < version {
            guard let m = migrate(data, from: head.version) else { return nil }
            bytes = m
        }
        guard var f = try? decoder().decode(ProjectFile.self, from: bytes) else { return nil }
        f.version = version
        f.doc.repair()
        return f
    }

    /// Шаги миграции по версиям (пока нет: версия 1 — первая).
    static func migrate(_ data: Data, from v: Int) -> Data? {
        return data
    }

    struct Head: Decodable {
        var format: String
        var version: Int
    }
}

/// Проекты на диске. Запись — атомарная (сбой посреди записи не портит прежний файл).
public struct ProjectStore: Sendable {
    public let dir: URL
    public static let autosaveId = "autosave"

    public init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Папка приложения: Application Support/Projects.
    public static func appDir() -> URL {
        let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Projects", isDirectory: true)
    }

    public static func newId() -> String {
        let t: String = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r: String = String(Int.random(in: 0..<(36 * 36 * 36 * 36)), radix: 36)
        return "p" + t + r
    }

    /// Имя файла — только из букв и цифр (id приложения), иначе nil.
    func url(_ id: String) -> URL? {
        if id.isEmpty || !id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return nil }
        return dir.appendingPathComponent(id + ".json")
    }

    /// Список: новые сверху. Нечитаемые файлы пропускаются.
    public func list() -> [ProjectInfo] {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var out: [ProjectInfo] = []
        for n in names where n.hasSuffix(".json") {
            let id = String(n.dropLast(5))
            guard let u = url(id), let data = try? Data(contentsOf: u),
                  let f = try? ProjectFormat.decoder().decode(ListHead.self, from: data),
                  f.format == ProjectFormat.name else { continue }
            var i = f.info
            i.id = id
            out.append(i)
        }
        return out.sorted { $0.updated > $1.updated }
    }

    public func load(_ id: String) -> ProjectFile? {
        guard let u = url(id), let data = try? Data(contentsOf: u), var f = ProjectFormat.decode(data) else { return nil }
        f.info.id = id
        return f
    }

    /// Сохранить (info.id — имя файла; bpm, нота, гамма — из doc).
    @discardableResult
    public func save(_ doc: Project, info: ProjectInfo) -> Bool {
        guard let u = url(info.id), let data = ProjectFormat.encode(ProjectFile(info: info, doc: doc)) else { return false }
        do {
            try data.write(to: u, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func delete(_ id: String) {
        guard let u = url(id) else { return }
        try? FileManager.default.removeItem(at: u)
    }

    /// Переименовать: меняется только имя (содержимое и время — прежние).
    @discardableResult
    public func rename(_ id: String, to name: String) -> Bool {
        guard var f = load(id) else { return false }
        f.info.name = name
        return save(f.doc, info: f.info)
    }

    /// Проект с таким именем (для вопроса о перезаписи в SAVE AS); Autosave не считается.
    public func find(name: String) -> ProjectInfo? {
        return list().first { $0.id != ProjectStore.autosaveId && $0.name == name }
    }

    struct ListHead: Decodable {
        var format: String
        var info: ProjectInfo
    }
}
