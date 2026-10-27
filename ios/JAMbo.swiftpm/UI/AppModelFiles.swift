import Foundation

// EXPORT / IMPORT проекта файлом .jambo (S11a, как exportProject / importProject веба; контейнер — ProjectPack).
// EXPORT: проект (без строки PREV — savedProject) и его сэмплы (свои .caf) — во временный файл, его переносит в
// «Файлы» системное окно (fileMover). IMPORT: файл веба (конвертер WebProject) или Swift-версии; сэмплы — в Samples,
// проект — новой записью в списке («имя (imported)», если имя занято), затем окно LOAD / MIX.

/// Итог IMPORT: новая запись в списке проектов или текст ошибки.
enum ProjectImport: Equatable {
    case done(ProjectInfo)
    case failed(String)
}

extension AppModel {
    /// EXPORT: временный файл .jambo (nil — не удалось записать).
    func exportProjectFile(_ done: @escaping @MainActor (URL?) -> Void) {
        let p: Project = savedProject
        let name: String = session.name
        let dir: URL = store.dir
        Task.detached(priority: .userInitiated) {
            let url: URL? = AppModel.writeExport(p, name: name, dir: dir)
            await MainActor.run { done(url) }
        }
    }

    static func writeExport(_ p: Project, name: String, dir: URL) -> URL? {
        var samples: [PackSample] = []
        for key in p.sampleKeys.sorted() {
            guard let bytes = SampleStore.packed(key: key, dir: dir) else { continue }
            samples.append(PackSample(key: key, name: "\(key).caf", bytes: bytes))
        }
        // Свои таблицы WTABLE — исходными WAV (S11b4).
        let tables: URL = WtWav.appDir()
        for key in p.tableKeys.sorted() {
            guard let bytes = try? Data(contentsOf: WtWav.url(key, in: tables)) else { continue }
            samples.append(PackSample(key: key, name: "\(key).wav", bytes: bytes))
        }
        guard let pack = ProjectPack.swift(name: name, doc: p, samples: samples), let data = pack.encoded() else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        // Прежний файл (окно закрыли без сохранения) — убрать.
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ProjectSession.exportFileName(name))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return url
    }

    /// IMPORT: системный выбор файла (тот же fileImporter, что у сэмплов, — режим проекта).
    func chooseProjectFile() {
        importingProject = true
        importingLibrary = false
        importingPhones = false
        importing = true
    }

    /// Выбранный файл .jambo: разбор и запись — в фоне; итог — projectImport.
    func importProjectFile(_ url: URL) {
        let dir: URL = store.dir
        let store: ProjectStore = projects
        let queue: DispatchQueue = saveQueue
        let list: [ProjectInfo] = projectList
        Task.detached(priority: .userInitiated) {
            let r: ProjectImport = AppModel.readImport(url, dir: dir, store: store, queue: queue, list: list)
            await MainActor.run {
                self.refreshProjects()
                self.projectImport = r
                trace("import \(r)")
            }
        }
    }

    static func readImport(_ url: URL, dir: URL, store: ProjectStore, queue: DispatchQueue,
                           list: [ProjectInfo]) -> ProjectImport {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .failed("Can’t read the file.") }
        guard let pack = ProjectPack.decode(data), let p = pack.project() else { return .failed("Not a JAMbo project.") }
        // Сэмпл, который не прочитался, — дорожка без звука (как сэмпл, которого нет на диске).
        for s in pack.samples(for: p) { _ = SampleStore.importPacked(s, dir: dir) }
        // Свои таблицы WTABLE — WAV как есть, в Tables (уже лежащий не трогается).
        let tables: URL = WtWav.appDir()
        for s in pack.tables(for: p) {
            let u: URL = WtWav.url(s.key, in: tables)
            if !FileManager.default.fileExists(atPath: u.path) { try? s.bytes.write(to: u, options: .atomic) }
        }
        let name: String = ProjectSession.importedName(pack.name, in: list)
        let info = ProjectInfo(id: ProjectStore.newId(), name: name, updated: Date().timeIntervalSince1970)
        let ok: Bool = queue.sync { store.save(p, info: info) }
        return ok ? .done(info) : .failed("Can’t save the project.")
    }
}
