import Foundation

// GRANULAR: сэмпл дорожки (SOURCE в меню звука) — браузер сэмплов, тап или IMPORT ставит сэмпл (UNDO); длина сэмпла
// выбранной дорожки — для значения POSITION на ручке; огибающая сэмпла — для иконки.

extension AppModel {
    /// Тап по сэмплу в SOURCE: сэмпл — в хранилище (если ещё нет), затем на дорожку; браузер закрывается.
    func libUseSource(_ n: LibNode) {
        guard n.kind == .sample, let key = n.key else { return }
        let i: Int = selectedTrack
        let name: String = n.name
        libUseSamples([(key, name)]) { [weak self] ok in
            guard let self = self, ok else { return }
            self.setGrain(key, track: i)
        }
    }

    /// IMPORT в SOURCE: первый аудиофайл — в открытую папку библиотеки и сэмплом GRANULAR дорожки.
    func sourceImport(_ urls: [URL]) {
        let dir: URL = store.dir
        let i: Int = selectedTrack
        let into: String = libFolder == LibraryBuiltins.folderId ? Library.root : libFolder
        Task.detached(priority: .userInitiated) {
            var loaded: SampleStore.Loaded? = nil
            for u in urls {
                if let l = SampleStore.decode(u, dir: dir) {
                    loaded = l
                    break
                }
            }
            let result = loaded
            await MainActor.run {
                guard let l = result else {
                    self.libNote = "Nothing to import: no audio found"
                    return
                }
                self.store.add(l.key, l.data)
                self.samplesVersion += 1
                self.libEdit { lib in _ = lib.addSample(into, key: l.key, name: l.name) }
                self.mutatePlay({ p in if p.files[l.key] == nil { p.files[l.key] = l.name } }, publish: false)
                self.setGrain(l.key, track: i)
            }
        }
    }

    /// Сэмпл GRANULAR дорожки i (UNDO); браузер закрывается.
    func setGrain(_ key: String, track i: Int) {
        guard i < project.tracks.count else { return }
        edit { p in p.tracks[i].grain = key }
        closeBrowser()
    }

    /// Огибающая сэмпла SOURCE для иконки GRANULAR (кэш по ключу); сэмпла нет или он не загружен — nil.
    func grainPeaks(_ key: String) -> [Double]? {
        if let p = grainPeakCache[key] { return p }
        guard let s = sample(key) else { return nil }
        let p: [Double] = EngineIcons.samplePeaks(s)
        if grainPeakCache.count > 16 { grainPeakCache.removeAll() }
        grainPeakCache[key] = p
        return p
    }

    /// Длина сэмпла GRANULAR выбранной дорожки → значение POSITION на ручке (секунды).
    func updateGrainSeconds() {
        let i: Int = selectedTrack
        guard i < project.tracks.count else {
            TexGran.sourceSeconds = 0
            return
        }
        let t: Track = project.tracks[i]
        guard SynthKey.engine(t.sample) == Jambo.granular, let s = sample(t.grain) else {
            TexGran.sourceSeconds = 0
            return
        }
        TexGran.sourceSeconds = Double(s.frames) / AudioCore.sampleRate
    }
}
