import Foundation

// Пакеты голов (15.11, решение пользователя; Core/Monitor/HeadPack): IMPORT в меню HEAD — .zip с rooms.json и импульсами
// комнат; пакет — папка в Application Support/Heads (имя — имя файла), его комнаты добавляются к комнатам сборки;
// свайп влево по импортированной голове в меню — корзина (удалить голову). Итог — окно с OK (как у профилей коррекции).
extension AppModel {
    /// Папка пакетов голов (создаётся при первом импорте).
    static var headsDir: URL {
        let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Heads", isDirectory: true)
    }

    /// Комнаты из пакетов голов: у каждой — папка пакета (RoomInfo.dir).
    static func loadPackRooms() -> [RoomInfo] {
        let fm = FileManager.default
        let dirs: [URL] = (try? fm.contentsOfDirectory(at: AppModel.headsDir, includingPropertiesForKeys: nil)) ?? []
        var out: [RoomInfo] = []
        for d in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let list: [RoomInfo] = RoomInfo.list(try? Data(contentsOf: d.appendingPathComponent("rooms.json")))
            for r in list {
                r.dir = d.path
                out.append(r)
            }
        }
        return out
    }

    /// Голова из пакета (её можно удалить удержанием).
    func headImported(_ name: String) -> Bool {
        return rooms.contains { $0.headName == name && !$0.dir.isEmpty }
    }

    /// IMPORT в меню HEAD: выбор файлов пакетов (.zip).
    func chooseHeadFiles() {
        translationMenu = nil
        importingHeads = true
        importingPhones = false
        importingProject = false
        importingLibrary = false
        importing = true
    }

    /// Пакеты из файлов: каждый — в свою папку (то же имя — замена); комнаты перечитываются.
    func headsImport(_ urls: [URL]) {
        var lines: [String] = []
        let fm = FileManager.default
        for u in urls {
            let access: Bool = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let pack = (try? Data(contentsOf: u)).flatMap { HeadPack.unpack($0) }
            guard let p = pack else {
                lines.append(u.lastPathComponent + ": not a head pack (rooms.json and room WAV files expected).")
                continue
            }
            let dir: URL = AppModel.headsDir.appendingPathComponent(u.deletingPathExtension().lastPathComponent, isDirectory: true)
            try? fm.removeItem(at: dir)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in HeadPack.referenced(p.rooms) {
                if let d = p.files[f] { try? d.write(to: dir.appendingPathComponent(f)) }
            }
            lines.append("Imported: " + HeadPack.heads(p.rooms).joined(separator: ", ") + " (" + String(p.rooms.count) + " rooms).")
        }
        reloadRooms()
        headsNote = true
        phonesNote = lines.joined(separator: "\n")
    }

    /// Свайп влево по голове из пакета в меню HEAD (корзина): её комнаты и файлы убираются из пакетов (в пакете может
    /// быть несколько голов); пустой пакет — папка удаляется. Головы сборки (FABIAN) не удаляются.
    func deleteHead(_ name: String) {
        let fm = FileManager.default
        let dirs: Set<String> = Set(rooms.filter { $0.headName == name && !$0.dir.isEmpty }.map { $0.dir })
        for d in dirs {
            let url = URL(fileURLWithPath: d)
            let all: [RoomInfo] = RoomInfo.list(try? Data(contentsOf: url.appendingPathComponent("rooms.json")))
            let gone: [RoomInfo] = all.filter { $0.headName == name }
            let keep: [RoomInfo] = all.filter { $0.headName != name }
            if keep.isEmpty {
                try? fm.removeItem(at: url)
                continue
            }
            let used: [String] = HeadPack.referenced(keep)
            for f in HeadPack.referenced(gone) where !used.contains(f) { try? fm.removeItem(at: url.appendingPathComponent(f)) }
            HeadPack.rewrite(url.appendingPathComponent("rooms.json"), without: name)
        }
        reloadRooms()
    }

    /// Комнаты сборки и пакетов — заново; пространство пересобирается (выбранной головы нет — первая).
    func reloadRooms() {
        rooms = AppModel.loadRooms() + AppModel.loadPackRooms()
        roomSet = nil
        roomLoaded = nil
        // Поля HEAD и SPACE читают комнаты не напрямую (rooms вне наблюдения) — обновить строку монитора.
        let m: MonitorSettings = monitor
        monitor = m
        syncRoom()
    }
}
