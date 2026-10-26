import Foundation

// Проекты (S9b): открытие при запуске, автосохранение в запись Autosave, сэмплы проекта с диска.
// Меню PROJECTS (NEW, SAVE, SAVE AS, RENAME, список) — S9c.

extension AppModel {
    /// Ключ UserDefaults: последний открытый проект (если Autosave удалили).
    static let currentKey = "currentProject"

    /// При запуске: Autosave, иначе последний проект, иначе новый (проект ставит init).
    func startProject() -> Project {
        let last: String? = UserDefaults.standard.string(forKey: AppModel.currentKey)
        let opened: (ProjectSession, Project) = ProjectSession.start(projects, last: last)
        session = opened.0
        UserDefaults.standard.set(opened.0.id, forKey: AppModel.currentKey)
        loadSamples(opened.1.sampleKeys)
        // Открытый проект сразу становится автосохранением (Autosave само себя не перезаписывает).
        projectChanged()
        trace("project \(opened.0.name)")
        return opened.1
    }

    /// Есть изменения, не сохранённые кнопкой SAVE (пометка «unsaved»).
    var unsaved: Bool { return session.unsaved(savedProject) }

    /// Сообщение при открытии проекта прочитано: убрать (без UNDO; автосохранение запомнит).
    func clearNotice() {
        if project.notice == nil { return }
        mutatePlay({ p in p.notice = nil }, publish: false)
        projectChanged()
    }

    /// Проект изменился: автосохранение — через ~1,5 с после первого изменения (как интервал веба).
    func projectChanged() {
        updateGrainSeconds()
        if autosaveDue == 0 { autosaveDue = Date.timeIntervalSinceReferenceDate + ProjectSession.autosaveDelay }
    }

    /// Записать Autosave (в своей очереди; снимок проекта — значение).
    func autosave() {
        autosaveDue = 0
        guard let snap = autosaveSnapshot() else { return }
        let store = projects
        saveQueue.async { _ = store.save(snap.0, info: snap.1) }
    }

    /// Уход в фон: записать сразу и дождаться записи (приложение могут выгрузить).
    func flushAutosave() {
        autosaveDue = 0
        let snap = autosaveSnapshot()
        let store = projects
        saveQueue.sync {
            if let s = snap { _ = store.save(s.0, info: s.1) }
        }
    }

    private func autosaveSnapshot() -> (Project, ProjectInfo)? {
        // Во время перехода MIX — новый проект без строки PREV (forSave).
        let snap = autosavedProject
        if !session.needsAutosave(snap) { return nil }
        session.lastAuto = snap
        return (snap, session.autosaveInfo(now: Date().timeIntervalSince1970))
    }

    /// Сэмплы проекта с диска (в фоне): каких нет в памяти; файла нет — дорожка без звука.
    func loadSamples(_ keys: Set<String>) {
        let need: [String] = Array(keys.filter { store.data($0) == nil })
        if need.isEmpty { return }
        let dir = store.dir
        Task.detached(priority: .userInitiated) {
            var found: [(String, SampleData)] = []
            for k in need {
                if let d = SampleStore.read(key: k, dir: dir) { found.append((k, d)) }
            }
            let result = found
            await MainActor.run { self.addSamples(result) }
        }
    }

    private func addSamples(_ found: [(String, SampleData)]) {
        if found.isEmpty { return }
        for (k, d) in found { store.add(k, d) }
        samplesVersion += 1
        publishAudio()
    }
}

// MARK: — меню PROJECTS (S9c)

extension AppModel {
    func refreshProjects() {
        let store = projects
        projectList = saveQueue.sync { store.list() }
    }

    private var now: Double { return Date().timeIntervalSince1970 }

    /// Записи на диск — в очереди автосохранения (по порядку), с ожиданием. Затем Autosave пишется заново: в нём
    /// id и имя проекта (иначе после RENAME или SAVE AS при запуске открылось бы прежнее имя).
    /// Удаление Autosave не пересоздаёт (rewrite false): он появится при следующем изменении, как в вебе.
    private func write(rewrite: Bool = true, _ f: (inout ProjectSession) -> Void) {
        var s = session
        saveQueue.sync { f(&s) }
        if rewrite { s.lastAuto = nil }
        session = s
        UserDefaults.standard.set(s.id, forKey: AppModel.currentKey)
        if rewrite { projectChanged() }
        refreshProjects()
    }

    /// NEW: новый пустой проект (в список попадёт после SAVE).
    func newProject() {
        session = ProjectSession.fresh(projects)
        UserDefaults.standard.set(session.id, forKey: AppModel.currentKey)
        var p = Project()
        knobDefaults.apply(to: &p)
        loadProject(p)
        projectChanged()
    }

    /// Проект ещё не сохраняли кнопкой SAVE (его нет в списке): SAVE спрашивает имя.
    var isNewProject: Bool {
        let id: String = session.id
        return session.saved == nil && !projectList.contains { $0.id == id }
    }

    func saveProject() {
        let p = savedProject
        let store = projects
        let t = now
        write { s in _ = s.save(p, store: store, now: t) }
    }

    /// SAVE AS: replace — проект с тем же именем (после вопроса о перезаписи).
    func saveProjectAs(_ name: String, replace: ProjectInfo?) {
        let p = savedProject
        let store = projects
        let t = now
        write { s in _ = s.saveAs(p, name: name, replace: replace, store: store, now: t) }
    }

    /// Проект с таким именем (кроме текущего и Autosave).
    func projectNamed(_ name: String) -> ProjectInfo? {
        return session.named(name, in: projectList)
    }

    func renameProject(id: String, to name: String) {
        let store = projects
        write { s in s.rename(id: id, to: name, store: store) }
    }

    func deleteProject(id: String) {
        let store = projects
        write(rewrite: false) { s in s.delete(id: id, store: store) }
    }

    /// Открыть из списка (LOAD): проект — в том виде, в каком он сохранён SAVE; Autosave — в проект, из которого он.
    func openProject(id: String) {
        let store = projects
        guard let f = saveQueue.sync(execute: { store.load(id) }) else {
            refreshProjects()
            return
        }
        session = ProjectSession.open(f, store: store)
        UserDefaults.standard.set(session.id, forKey: AppModel.currentKey)
        loadProject(f.doc)
        projectChanged()
        refreshProjects()
    }

    /// IMPORT строк (решение пользователя): строки проекта id с тригами — в свободные строки текущего (UNDO), звук —
    /// у клипов; игра не останавливается. Возвращает, сколько строк встало (0 — некуда или нечего).
    func importProjectRows(id: String) -> Int {
        let store = projects
        guard let f = saveQueue.sync(execute: { store.load(id) }) else {
            refreshProjects()
            return 0
        }
        var n = 0
        edit { p in n = p.importRows(from: f.doc, name: f.info.name) }
        if n > 0 { loadSamples(project.sampleKeys) }
        trace("import rows ← \(f.info.name): \(n)")
        return n
    }
}
