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
