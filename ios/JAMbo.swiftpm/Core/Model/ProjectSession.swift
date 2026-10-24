import Foundation

// Текущий проект (S9b, как project.ts веба): id и имя проекта, в который сохраняет SAVE; что записано кнопкой SAVE
// (для пометки «unsaved») и автосохранением. Автосохранение пишет не в проект, а в запись Autosave (с id и именем
// проекта); при запуске открывается она, но SAVE по-прежнему сохраняет в тот проект.

public struct ProjectSession: Sendable {
    public static let autosaveName = "Autosave"
    /// Пауза после изменений до автосохранения, с (AUTOSAVE_MS веба).
    public static let autosaveDelay: Double = 1.5

    public var id: String
    public var name: String
    /// Проект в том виде, в каком его записала кнопка SAVE (nil — ещё не сохраняли: новый).
    public var saved: Project?
    /// Что последним записало автосохранение (nil — ещё не писало).
    public var lastAuto: Project?

    public init(id: String, name: String, saved: Project? = nil, lastAuto: Project? = nil) {
        self.id = id
        self.name = name
        self.saved = saved
        self.lastAuto = lastAuto
    }

    /// Текущий проект отличается от сохранённого кнопкой SAVE.
    public func unsaved(_ p: Project) -> Bool {
        return saved != p
    }

    /// Автосохранению есть что писать.
    public func needsAutosave(_ p: Project) -> Bool {
        return lastAuto != p
    }

    /// Запись Autosave для текущего проекта.
    public func autosaveInfo(now: Double) -> ProjectInfo {
        return ProjectInfo(id: ProjectStore.autosaveId, name: ProjectSession.autosaveName, updated: now, projectId: id,
                           projectName: name)
    }

    /// Запись проекта (SAVE).
    public func info(now: Double) -> ProjectInfo {
        return ProjectInfo(id: id, name: name, updated: now)
    }

    /// Имя нового проекта: «Project N», первое свободное (nextName веба).
    public static func nextName(_ list: [ProjectInfo]) -> String {
        let names = Set(list.map { $0.name })
        var n = 1
        while names.contains("Project \(n)") { n += 1 }
        return "Project \(n)"
    }

    /// Случайное имя для первого SAVE: «Прилагательное Существительное», не занятое (иначе — с номером).
    public static func randomName(_ list: [ProjectInfo], seed: UInt64? = nil) -> String {
        var g = SplitMix(seed ?? UInt64.random(in: 0...UInt64.max))
        let names = Set(list.map { $0.name })
        var last = ""
        for _ in 0..<20 {
            let a: String = nameAdjectives[Int(g.next() % UInt64(nameAdjectives.count))]
            let n: String = nameNouns[Int(g.next() % UInt64(nameNouns.count))]
            last = "\(a) \(n)"
            if !names.contains(last) { return last }
        }
        var k = 2
        while names.contains("\(last) \(k)") { k += 1 }
        return "\(last) \(k)"
    }

    static let nameAdjectives: [String] = [
        "Velvet", "Neon", "Midnight", "Golden", "Electric", "Silent", "Cosmic", "Liquid", "Crystal", "Lazy", "Wild",
        "Hidden", "Broken", "Lunar", "Solar", "Dusty", "Frozen", "Burning", "Purple", "Deep", "Hazy", "Rusty",
        "Silver", "Analog", "Distant", "Funky", "Mellow", "Stormy", "Sleepy", "Magnetic",
    ]
    static let nameNouns: [String] = [
        "Groove", "Echo", "Pulse", "Orbit", "Tide", "Comet", "Mirage", "Signal", "Drift", "Loop", "Garden",
        "Engine", "Shadow", "Wave", "Circuit", "Horizon", "Ember", "Canyon", "Harbor", "Prism", "Rhythm", "Static",
        "Tape", "Voltage", "Bloom", "Desert", "River", "Ritual", "Machine", "Sunset",
    ]

    /// Новый проект (в список попадёт после SAVE).
    public static func fresh(_ store: ProjectStore) -> ProjectSession {
        return ProjectSession(id: ProjectStore.newId(), name: nextName(store.list()))
    }

    /// Открыть запись: проект — как есть (сразу становится автосохранением: lastAuto пуст), Autosave — в проект,
    /// из которого она сделана («сохранено» — то, что лежит в самом проекте).
    public static func open(_ f: ProjectFile, store: ProjectStore) -> ProjectSession {
        if f.info.id != ProjectStore.autosaveId {
            return ProjectSession(id: f.info.id, name: f.info.name, saved: f.doc)
        }
        let id: String = f.info.projectId ?? ProjectStore.newId()
        let name: String = f.info.projectName ?? nextName(store.list())
        return ProjectSession(id: id, name: name, saved: store.load(id)?.doc, lastAuto: f.doc)
    }

    /// При запуске: Autosave (последняя работа), иначе последний открытый проект, иначе новый.
    public static func start(_ store: ProjectStore, last: String?) -> (ProjectSession, Project) {
        if let f = store.load(ProjectStore.autosaveId) { return (open(f, store: store), f.doc) }
        if let id = last, let f = store.load(id) { return (open(f, store: store), f.doc) }
        var p = Project()
        p.repair()
        return (fresh(store), p)
    }
}

// Действия меню PROJECTS (S9c, как project.ts веба). Запись — сразу на диск; список перечитывает вызывающий.
extension ProjectSession {
    /// Длина имени проекта (CLAUDE.md: проекты — 24 знака).
    public static let nameLimit = 24

    /// Имя из поля ввода: без пробелов по краям, не длиннее 24.
    public static func clean(_ name: String) -> String {
        let t: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(t.prefix(nameLimit))
    }

    /// SAVE: записать в текущий проект.
    @discardableResult
    public mutating func save(_ p: Project, store: ProjectStore, now: Double) -> Bool {
        if !store.save(p, info: info(now: now)) { return false }
        saved = p
        return true
    }

    /// SAVE AS: копия под новым именем (дальше работа в копии); replace — проект с тем же именем, который
    /// перезаписывается после вопроса.
    @discardableResult
    public mutating func saveAs(_ p: Project, name: String, replace: ProjectInfo?, store: ProjectStore,
                                now: Double) -> Bool {
        let n: String = ProjectSession.clean(name)
        id = replace?.id ?? ProjectStore.newId()
        self.name = n.isEmpty ? ProjectSession.nextName(store.list()) : n
        saved = nil
        return save(p, store: store, now: now)
    }

    /// RENAME текущего: имя (у сохранённого — сразу и в списке).
    public mutating func rename(_ name: String, store: ProjectStore) {
        let n: String = ProjectSession.clean(name)
        if n.isEmpty { return }
        self.name = n
        store.rename(id, to: n)
    }

    /// Переименовать проект из списка (карандаш); текущий — как RENAME.
    public mutating func rename(id other: String, to name: String, store: ProjectStore) {
        if other == id {
            rename(name, store: store)
            return
        }
        let n: String = ProjectSession.clean(name)
        if !n.isEmpty { store.rename(other, to: n) }
    }

    /// Удалить запись из списка (корзина): работа на экране остаётся; удалили текущий — он снова не сохранён.
    public mutating func delete(id other: String, store: ProjectStore) {
        store.delete(other)
        if other == id { saved = nil }
    }

    /// Проект с таким именем, кроме текущего и Autosave (вопрос о перезаписи в SAVE AS).
    public func named(_ name: String, in list: [ProjectInfo]) -> ProjectInfo? {
        let n: String = ProjectSession.clean(name)
        return list.first { $0.name == n && $0.id != id && $0.id != ProjectStore.autosaveId }
    }

    /// Справа в строке списка: темп, корневая нота и гамма сокращённо («120 · C Min»).
    public static func meta(_ i: ProjectInfo) -> String {
        let scale: Int = Swift.min(Scales.all.count - 1, Swift.max(0, i.scale))
        let note: String = Params.noteNames[((i.root % 12) + 12) % 12]
        return "\(Int(i.bpm.rounded())) · \(note) \(Scales.all[scale].short)"
    }

    /// IMPORT (S11a, как importProject веба): имя занято — «имя (imported)»; длиннее 24 — можно (подставленное).
    public static func importedName(_ name: String, in list: [ProjectInfo]) -> String {
        let n: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String = n.isEmpty ? nextName(list) : n
        return list.contains { $0.name == base } ? "\(base) (imported)" : base
    }

    /// EXPORT: имя файла .jambo — буквы, цифры, «-», «_» и пробел, прочее — «_» (как exportProject веба).
    public static func exportFileName(_ name: String) -> String {
        var out: String = ""
        for ch in name {
            let ok: Bool = ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == " "
            out.append(ok ? ch : "_")
        }
        return (out.isEmpty ? "project" : out) + ".jambo"
    }
}

/// Простой генератор для случайного имени (с seed — повторяемый, для тестов).
struct SplitMix {
    var state: UInt64

    init(_ seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
