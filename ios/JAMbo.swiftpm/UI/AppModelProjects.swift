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
    var unsaved: Bool { return session.unsaved(project) }

    /// Проект изменился: автосохранение — через ~1,5 с после первого изменения (как интервал веба).
    func projectChanged() {
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
        if !session.needsAutosave(project) { return nil }
        let snap = project
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
