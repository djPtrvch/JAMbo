import Foundation

/// Огибающая референса для строки REF: наибольший модуль (оба канала) на каждые RefWave.hop кадров.
struct RefWave: Equatable {
    static let hop = 512
    let key: String
    let frames: Int
    let peaks: [Float]

    static func make(_ key: String, _ s: SampleData) -> RefWave {
        let n: Int = (s.frames + hop - 1) / hop
        var out = [Float](repeating: 0, count: n)
        let l = s.left, r = s.right
        let stereo: Bool = s.channels == 2
        var k = 0
        while k < n {
            let a: Int = k * hop
            let b: Int = min(s.frames, a + hop)
            var m: Float = 0
            var i: Int = a
            while i < b {
                let v: Float = abs(l[i])
                if v > m { m = v }
                if stereo {
                    let w: Float = abs(r[i])
                    if w > m { m = w }
                }
                i += 1
            }
            out[k] = m
            k += 1
        }
        return RefWave(key: key, frames: s.frames, peaks: out)
    }
}

/// REF — референс-трек (S15g, docs/ai/arranger.md «REF»): кнопка REF показывает и скрывает строку REF над дорожками
/// (файла нет — браузер библиотеки: тап по сэмплу или IMPORT; копия — в проекте, в библиотеку не попадает); A/B —
/// слева от линейки, пока строка видна; в положении B измеритель, LUFS и его регулятор — референса.
extension AppModel {
    /// Строка REF на экране аранжировщика.
    var arrRefShown: Bool { return project.arrange.showRef && project.arrange.ref != nil }

    /// Слышен референс: B, строка REF видна, аранжировщик открыт (вне его — всегда A: проект не глохнет).
    var refBActive: Bool { return arrRefB && arrRefShown && arrangeView }

    /// Кнопка REF: файла нет — браузер; иначе — показать или скрыть строку (скрыли — A).
    func toggleArrRef() {
        if project.arrange.ref == nil {
            openBrowser(.ref)
            return
        }
        let show: Bool = !project.arrange.showRef
        if !show { arrRefB = false }
        edit { p in p.arrange.showRef = show }
    }

    /// A/B (слева от линейки).
    func toggleArrRefB() {
        arrRefB.toggle()
        publishAudio()
    }

    /// Референс — файл с ключом key (уже в хранилище): строка REF видна, браузер закрыт, аранжировщик открыт.
    func arrLoadRef(_ key: String, name: String) {
        edit { p in
            p.arrange.ref = ArrRef(key: key, name: name)
            p.arrange.showRef = true
        }
        closeBrowser()
        if !arrangeView { toggleArrange() }
    }

    /// Меню REF → DELETE: референса нет, строка скрыта.
    func arrDeleteRef() {
        arrRefB = false
        edit { p in
            p.arrange.ref = nil
            p.arrange.showRef = false
        }
    }

    /// Перетаскивание волны (внутри жеста): начало файла — offset секунд от начала таймлайна.
    func setArrRefOffset(_ offset: Double) {
        guard project.arrange.ref != nil else { return }
        edit { p in p.arrange.ref?.offset = offset }
    }

    /// Секунды на шаг при текущем темпе.
    var arrStepSeconds: Double { return 15 / max(20, project.bpm) }

    /// Громкость референса (регулятор измерителя в положении B), −∞…0 dB.
    func setArrRefGain(_ db: Double) {
        guard project.arrange.ref != nil else { return }
        let v: Double = max(Params.volMin, min(0, db))
        edit { p in p.arrange.ref?.gain = v }
    }

    /// Огибающая для строки REF: строится в фоне, когда файл в памяти (после загрузки сэмплов — заново).
    func ensureRefWave() {
        guard let r = project.arrange.ref else {
            if refWave != nil { refWave = nil }
            return
        }
        if refWave?.key == r.key { return }
        guard let s = store.data(r.key) else { return }
        let key: String = r.key
        Task.detached(priority: .userInitiated) {
            let w: RefWave = RefWave.make(key, s)
            await MainActor.run {
                if self.project.arrange.ref?.key == key { self.refWave = w }
            }
        }
    }

    /// Браузер REF: тап по сэмплу — референс.
    func libUseRef(_ n: LibNode) {
        guard n.kind == .sample, let key = n.key else { return }
        let name: String = n.name
        libUseSamples([(key, name)]) { [weak self] ok in
            if ok { self?.arrLoadRef(key, name: name) }
        }
    }

    /// IMPORT в браузере REF: первый аудиофайл — референс (в библиотеку не попадает).
    func refImport(_ urls: [URL]) {
        let dir: URL = store.dir
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
                self.mutatePlay({ p in if p.files[l.key] == nil { p.files[l.key] = l.name } }, publish: false)
                self.arrLoadRef(l.key, name: l.name)
            }
        }
    }
}
