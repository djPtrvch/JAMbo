import Foundation

// Библиотека (S11b, как ui/browser.ts веба): браузер на месте центра — из меню звука (LOAD, SAVE пресета, TABLE)
// и редактора сэмпла (LOAD, SAVE сэмпла). Тап по сэмплу или пресету — звук дорожки (в её папке остаётся только он),
// удержание — выбор нескольких (LOAD — все в папку дорожки), для зажатых шагов — их звук. IMPORT — аудио из «Файлов»
// в открытую папку. SAVE HERE — пресет синта или сэмпл в открытую папку (имя занято — OVERWRITE / SAVE AS).
// Дерево — Library.json (запись в очереди сохранения), сэмплы — в Samples.

/// Таблица WAV, для которой спрашивают размер кадра.
struct TableImport: Equatable {
    let name: String
    let folder: String
    let data: Data
    let wav: WavTable
}

/// Что делает браузер.
enum BrowserMode: Equatable {
    /// Загрузка на дорожку или на зажатые шаги.
    case load(steps: [Int])
    /// LOAD TABLE (у дорожки с WTABLE): папки и таблицы (S11b4).
    case loadTable
    case savePreset
    case saveSample(String)
}

extension AppModel {
    // MARK: — окно

    func openBrowser(_ m: BrowserMode) {
        if !libraryLoaded {
            library = libraryStore.load()
            libraryLoaded = true
        }
        browser = m
        libPicked = nil
        libNote = ""
        if !library.isFolder(libFolder) { libFolder = Library.root }
        patternView = false
        editorOpen = false
        eqView = false
        closeRoll()
        closeMasterWindow()
        soundMenu = nil
    }

    func closeBrowser() {
        browser = nil
        libPicked = nil
        stopLibraryPreview()
    }

    var tableMode: Bool { return browser == .loadTable }

    var saveMode: Bool {
        guard let b = browser else { return false }
        switch b {
        case .savePreset, .saveSample: return true
        default: return false
        }
    }

    /// Шаги, на которые загружается звук (меню звука шагов).
    var browserSteps: [Int] {
        if case .load(let s) = browser { return s }
        return []
    }

    /// Строки открытой папки: в LOAD TABLE — папки и таблицы (в корне — BUILT-IN TABLES), иначе — всё, кроме таблиц.
    var libItems: [LibNode] {
        if tableMode {
            if libFolder == LibraryBuiltins.folderId { return LibraryBuiltins.tables }
            let list: [LibNode] = library.children(libFolder).filter { $0.kind == .folder || $0.kind == .table }
            return libFolder == Library.root ? [LibraryBuiltins.folder] + list : list
        }
        return library.children(libFolder).filter { $0.kind != .table }
    }

    /// Путь: LIBRARY (TABLES) / папка / …
    var libPath: String {
        let head: String = tableMode ? "TABLES" : "LIBRARY"
        if libFolder == LibraryBuiltins.folderId { return head + "  /  " + LibraryBuiltins.folder.name }
        let names: [String] = library.path(libFolder).map { $0.name }
        return ([head] + names).joined(separator: "  /  ")
    }

    func libEnter(_ id: String) {
        if libPicked != nil { return }
        libFolder = id
    }

    func libUp() {
        if libFolder == LibraryBuiltins.folderId {
            libFolder = Library.root
        } else if let n = library.node(libFolder) {
            libFolder = n.parent
        }
        libPicked = nil
    }

    /// Правка дерева: сразу на экране, запись файла — в очереди сохранения.
    func libEdit(_ change: (inout Library) -> Void) {
        change(&library)
        let lib: Library = library
        let store: LibraryStore = libraryStore
        saveQueue.async { _ = store.save(lib) }
    }

    func libNewFolder(_ name: String) {
        let into: String = libFolder == LibraryBuiltins.folderId ? Library.root : libFolder
        libEdit { $0.createFolder(into, name) }
    }

    func libRename(_ id: String, _ name: String) {
        libEdit { $0.rename(id, to: name) }
    }

    func libDelete(_ id: String) {
        libEdit { $0.remove(id) }
        libPicked?.remove(id)
    }

    // MARK: — загрузка

    /// Звук дорожки сейчас — этот узел (подсветка).
    func libIsCurrent(_ n: LibNode) -> Bool {
        guard channel == .track, libPicked == nil, !saveMode else { return false }
        let t: Track = track
        switch n.kind {
        case .table: return tableMode && t.table == (n.key ?? "")
        case .sample: return !tableMode && n.key != nil && t.sample == n.key
        case .preset: return !tableMode && t.sample == n.preset?.sound && t.presetName == n.name
        case .folder: return false
        }
    }

    /// Тап по строке: папка — войти; в выборе — отметить; иначе — загрузить.
    func libTap(_ n: LibNode) {
        if n.kind == .folder {
            libEnter(n.id)
            return
        }
        if tableMode {
            if n.kind == .table, let key = n.key { libUseTable(key, name: n.name) }
            return
        }
        guard case .load(let steps) = browser, channel == .track else { return }
        if libPicked != nil {
            if libPicked!.contains(n.id) { libPicked!.remove(n.id) } else { libPicked!.insert(n.id) }
            return
        }
        let i: Int = selectedTrack
        if n.kind == .sample, let key = n.key {
            libUseSamples([(key, n.name)]) { [weak self] ok in
                guard let self = self, ok, i < self.project.tracks.count else { return }
                self.edit { p in
                    if steps.isEmpty {
                        p.tracks[i].setFolder([FolderItem(sample: key)])
                    } else {
                        p.tracks[i].addSamplesQuiet([key])
                        p.tracks[i].setStepSound(steps, key)
                    }
                }
                self.libNote = (steps.isEmpty ? self.trackLabel(i) : AppModel.stepsLabel(steps)) + ": " + n.name
            }
        } else if n.kind == .preset, let p = n.preset, steps.isEmpty {
            edit { pr in pr.tracks[i].setFolder([FolderItem(preset: p)]) }
            libNote = trackLabel(i) + ": " + n.name
        }
    }

    /// Удержание сэмпла или пресета — выбор нескольких (в загрузке на дорожку).
    func libHold(_ n: LibNode) {
        guard n.kind == .sample || n.kind == .preset, browser == .load(steps: []), libPicked == nil else { return }
        libPicked = [n.id]
    }

    /// LOAD выбора: в папке дорожки — только отмеченные (по порядку списка), первый звучит.
    func libLoadPicked() {
        trace("library LOAD picked \(libPicked?.count ?? -1)")
        guard let picked = libPicked else { return }
        let list: [LibNode] = library.children(libFolder).filter { $0.kind != .folder && picked.contains($0.id) }
        let i: Int = selectedTrack
        var samples: [(String, String)] = []
        for n in list where n.kind == .sample {
            if let k = n.key { samples.append((k, n.name)) }
        }
        libUseSamples(samples) { [weak self] _ in
            guard let self = self, i < self.project.tracks.count else { return }
            var items: [FolderItem] = []
            for n in list {
                if n.kind == .sample, let k = n.key, self.store.data(k) != nil { items.append(FolderItem(sample: k)) }
                if n.kind == .preset, let p = n.preset { items.append(FolderItem(preset: p)) }
            }
            if items.isEmpty { return }
            self.edit { p in p.tracks[i].setFolder(items) }
            self.libNote = self.trackLabel(i) + ": \(items.count) sound\(items.count == 1 ? "" : "s") in the track folder"
            self.libPicked = nil
        }
    }

    /// Сэмплы библиотеки — в память (с диска, в фоне) и в проект (имя, высота); done(true) — все есть.
    func libUseSamples(_ list: [(String, String)], done: @escaping @MainActor (Bool) -> Void) {
        let need: [String] = list.map { $0.0 }.filter { store.data($0) == nil }
        let dir: URL = store.dir
        Task.detached(priority: .userInitiated) {
            var found: [(String, SampleData, Int?)] = []
            for k in need {
                if let d = SampleStore.read(key: k, dir: dir) { found.append((k, d, PitchDetect.root(d))) }
            }
            let result = found
            await MainActor.run {
                for (k, d, _) in result { self.store.add(k, d) }
                if !result.isEmpty { self.samplesVersion += 1 }
                let ok: Bool = list.allSatisfy { self.store.data($0.0) != nil }
                if !ok { self.libNote = "This sample is no longer stored on this iPad" }
                let present: [(String, String)] = list.filter { self.store.data($0.0) != nil }
                if !present.isEmpty {
                    // Имя и высота — в проект (без записи в UNDO: проекту они нужны, пока звук на дорожке).
                    self.mutatePlay({ p in
                        for (k, name) in present where p.files[k] == nil { p.files[k] = name }
                        for (k, _, r) in result { if let r = r, p.roots[k] == nil { p.roots[k] = r } }
                    }, publish: true)
                }
                done(ok)
            }
        }
    }

    func trackLabel(_ i: Int) -> String {
        let name: String = i < project.tracks.count ? project.tracks[i].name : "\(i + 1)"
        return "Track " + name
    }

    static func stepsLabel(_ steps: [Int]) -> String {
        return "Step " + steps.map { String($0 + 1) }.joined(separator: ", ")
    }

    // MARK: — IMPORT

    /// IMPORT: выбор файлов (тот же fileImporter; в LOAD TABLE — таблицы WAV, S11b4).
    func chooseLibraryFiles() {
        importingLibrary = true
        importingProject = false
        importing = true
    }

    /// Аудиофайлы — в открытую папку (сэмплы — в Samples); не аудио — пропускаются.
    func libImport(_ urls: [URL]) {
        if tableMode {
            libImportTables(urls)
            return
        }
        let into: String = libFolder == LibraryBuiltins.folderId ? Library.root : libFolder
        let dir: URL = store.dir
        Task.detached(priority: .userInitiated) {
            var loaded: [SampleStore.Loaded] = []
            for u in urls {
                if let l = SampleStore.decode(u, dir: dir) { loaded.append(l) }
            }
            let result = loaded
            await MainActor.run {
                for l in result { self.store.add(l.key, l.data) }
                self.libEdit { lib in
                    for l in result { lib.addSample(into, key: l.key, name: l.name) }
                }
                self.libNote = result.isEmpty ? "Nothing to import: no audio files found"
                    : "Imported \(result.count) file\(result.count == 1 ? "" : "s")"
            }
        }
    }

    // MARK: — SAVE HERE

    /// Имя по умолчанию в поле NAME: пресет — движок и номер, сэмпл — имя файла без расширения.
    var libDefaultName: String {
        guard let b = browser else { return "" }
        switch b {
        case .savePreset:
            let e: Int? = SynthKey.engine(track.sample)
            let base: String = e.map { SynthEngines.all[$0].name } ?? "PRESET"
            let n: Int = library.nodes.filter { $0.kind == .preset && $0.name.hasPrefix(base) }.count
            return "\(base) \(n + 1)"
        case .saveSample(let key):
            return (sampleName(key) as NSString).deletingPathExtension
        default:
            return ""
        }
    }

    /// Папка сохранения (в RECORDINGS — в корень).
    var libSaveFolder: String {
        if libFolder == Library.recordings || libFolder == LibraryBuiltins.folderId { return Library.root }
        return libFolder
    }

    /// Узел с тем же именем (вопрос OVERWRITE / SAVE AS) или nil — можно сохранять.
    func libSameName(_ name: String) -> LibNode? {
        return library.sameName(libSaveFolder, name)
    }

    /// Сохранить (over — перезаписать этот узел); затем браузер — в загрузке.
    func libSave(_ name: String, over: String? = nil) {
        let into: String = libSaveFolder
        let i: Int = selectedTrack
        guard let b = browser else { return }
        switch b {
        case .savePreset:
            guard let p = track.preset(named: Library.clean(name)) else { return }
            var saved: SynthPreset = p
            libEdit { lib in
                if let id = over {
                    lib.overwrite(id, with: FolderItem(preset: p))
                    saved = lib.node(id)?.preset ?? p
                } else {
                    saved = lib.addPreset(into, p).preset ?? p
                }
            }
            edit { pr in pr.tracks[i].addItems([FolderItem(preset: saved)]) }
            libNote = "Saved preset " + saved.name
        case .saveSample(let key):
            libEdit { lib in
                if let id = over {
                    lib.overwrite(id, with: FolderItem(sample: key))
                } else {
                    lib.addSample(into, key: key, name: name)
                }
            }
            libNote = "Saved sample " + Library.clean(name)
        default:
            return
        }
        browser = .load(steps: [])
    }

    /// Свободное имя («Name 2») — подсказка для SAVE AS.
    func libFreeName(_ name: String) -> String {
        return library.uniqueName(libSaveFolder, name)
    }
}

// MARK: — предпрослушка ▶ (S11b3)

extension AppModel {
    /// ▶: сэмпл — целиком, в исходной высоте, сразу на выход (мимо дорожек); пресет — одна нота через выбранную
    /// дорожку движком и ручками пресета (на дорожку не ставится). Звук не загружается, выбор не меняется.
    func libPreview(_ n: LibNode) {
        ensureAudio()
        if n.kind == .sample, let key = n.key {
            previewLibrarySample(key)
        } else if n.kind == .preset, let p = n.preset, channel == .track, selectedTrack < project.tracks.count {
            let locks = NoteLocks(p.params)
            audio.core.events.push(.presetNote(track: selectedTrack, note: Params.sampleRoot, hash: SoundKey.hash(p.sound),
                                               locks: locks))
        }
    }

    private func previewLibrarySample(_ key: String) {
        if store.data(key) != nil {
            startLibraryPreview(key)
            return
        }
        let dir: URL = store.dir
        Task.detached(priority: .userInitiated) {
            let d: SampleData? = SampleStore.read(key: key, dir: dir)
            await MainActor.run {
                guard let data = d else {
                    self.libNote = "This sample is no longer stored on this iPad"
                    return
                }
                self.store.add(key, data)
                self.startLibraryPreview(key)
            }
        }
    }

    private func startLibraryPreview(_ key: String) {
        // Снимок с сэмплом вне дорожек — раньше команды (колбэк берёт снимки до команд).
        if libPreviewKey != key {
            libPreviewKey = key
            publishAudio()
        }
        previewOn = true
        audio.core.events.push(.preview(hash: SoundKey.hash(key), a: 0, b: 1))
    }

    func stopLibraryPreview() {
        guard libPreviewKey != nil else { return }
        if previewOn { audio.core.events.push(.previewStop) }
        libPreviewKey = nil
        publishAudio()
    }

    // MARK: — таблицы WTABLE (S11b4)

    /// IMPORT в LOAD TABLE: WAV до 4 МБ — таблицами в открытую папку; размер кадра — из метки Serum, иначе вопрос.
    func libImportTables(_ urls: [URL]) {
        let into: String = libFolder == LibraryBuiltins.folderId ? Library.root : libFolder
        Task.detached(priority: .userInitiated) {
            var found: [TableImport] = []
            var tooBig: [String] = []
            for u in urls {
                let access = u.startAccessingSecurityScopedResource()
                defer { if access { u.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: u) else { continue }
                let name: String = (u.lastPathComponent as NSString).deletingPathExtension
                if data.count > WtWav.maxBytes {
                    tooBig.append(u.lastPathComponent)
                    continue
                }
                guard let w = WtWav.parse(data) else { continue }
                found.append(TableImport(name: name, folder: into, data: data, wav: w))
            }
            let result = found
            let big = tooBig
            await MainActor.run {
                var ask: [TableImport] = []
                for t in result {
                    if let c = t.wav.clm, WtWav.frameSizes.contains(c) { self.libAddTable(t, frameSize: c) } else { ask.append(t) }
                }
                self.libTableAsk += ask
                if !big.isEmpty {
                    self.libNote = big.joined(separator: ", ") + ": a wavetable must be up to 4 MB"
                } else if result.isEmpty {
                    self.libNote = "Nothing to import: no wavetable WAV files found"
                }
            }
        }
    }

    /// Ответ на вопрос о размере кадра (nil — CANCEL): таблица — в библиотеку, дальше — следующий файл.
    func libAnswerTable(_ size: Int?) {
        guard !libTableAsk.isEmpty else { return }
        let t: TableImport = libTableAsk.removeFirst()
        if let s = size { libAddTable(t, frameSize: s) }
    }

    /// WAV — в Tables (по ключу содержимого), узел таблицы — в папку.
    private func libAddTable(_ t: TableImport, frameSize: Int) {
        let key: String = SampleStore.key(t.data)
        let url: URL = WtWav.url(key, in: WtWav.appDir())
        if !FileManager.default.fileExists(atPath: url.path) { try? t.data.write(to: url, options: .atomic) }
        let tkey: String = WavetableKey.user(key, frameSize: frameSize)
        libEdit { $0.addTable(t.folder, key: tkey, name: t.name) }
        libNote = "Imported table " + t.name
    }

    /// Тап по таблице: на дорожку (UNDO).
    func libUseTable(_ key: String, name: String) {
        guard channel == .track else { return }
        editTrack { t in t.table = key }
        libNote = trackLabel(selectedTrack) + ": table " + name
    }
}

extension Library {
    func isFolder(_ id: String) -> Bool {
        return id == Library.root || node(id)?.kind == .folder
    }
}
