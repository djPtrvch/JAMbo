import Foundation

// Звук дорожки в интерфейсе (как sample.ts, sampleedit.ts и state.ts веба): загрузка файлов, папка и стрелки,
// меню звука, редактор сэмпла (обрезка, TRIM, NORMALIZE, MONO, CLEAR, маркеры нарезки, ▶), полоса
// воспроизведения, живые ноты, микшер (громкости, M, S, меню дорожки, перестановка), перенос страниц.

/// Звучащий голос сэмпла: позиция считается по времени от начала ноты (модуляция Pitch не учитывается).
struct VoiceHead {
    let track: Int
    let hash: UInt64
    let frame: Int64
    let a: Double
    let b: Double
    let rate: Double
    let frames: Int
}

/// Меню звука: для дорожки (steps пустой) или для зажатых шагов (запомнены при открытии).
struct SoundMenuState: Equatable {
    let steps: [Int]
}

/// Выбор файлов: на дорожку или звуком зажатых шагов.
struct ImportTarget: Equatable {
    let track: Int
    let steps: [Int]
}

/// Меню дорожки у ручки громкости (MIX): slot — ручка; add — серая ручка (ADD TRACK).
struct TrackMenuState: Equatable {
    let slot: Int
    let add: Bool
}

extension AppModel {
    // MARK: — снимки звука

    func publishAudio() {
        audio.core.publish(project, samples: store.samples, map: settings.sliceMap, octave: octave)
    }

    /// Голоса из колбэка → полоса воспроизведения.
    func drainVoices() {
        var changed = false
        while let e = audio.core.sampler.out.pop() {
            switch e {
            case .start(let v, let t, let h, let f, let a, let b, let r, let n):
                heads[v] = VoiceHead(track: t, hash: h, frame: f, a: a, b: b, rate: r, frames: n)
                changed = true
            case .end(let v):
                heads[v] = nil
                if v == Sampler.previewVoice { previewOn = false }
                changed = true
            case .none:
                break
            }
        }
        if changed && headCount != heads.count { headCount = heads.count }
    }

    /// Кадр ядра, который слышен сейчас (по времени хоста с поправкой на задержку выхода).
    func heardFrame() -> Double {
        let c = audio.core.sequencer.clock.read()
        if c.blockHost <= 0 { return Double(audio.core.framesRendered) }
        let heard: Double = audio.hostNow() - audio.outputLatency
        return c.blockFrame + (heard - c.blockHost) * AudioCore.sampleRate
    }

    /// Полосы воспроизведения сэмпла key дорожки track: доля длины и непрозрачность (линия ноты тает за 1,2 с).
    func playheads(track: Int, key: String) -> [(f: Double, a: Double)] {
        if key.isEmpty || heads.isEmpty { return [] }
        let h = SoundKey.hash(key)
        let now = heardFrame()
        var out: [(f: Double, a: Double)] = []
        for v in heads.values where v.hash == h && (v.track == track || v.track < 0) {
            let dt: Double = now - Double(v.frame)
            if dt < 0 { continue }
            let f: Double = v.a + dt * v.rate / Double(max(1, v.frames))
            let alpha: Double = v.track < 0 ? 1 : 1 - dt / AudioCore.sampleRate / 1.2
            if f < v.b && alpha > 0.02 { out.append((f, alpha)) }
        }
        return out
    }

    // MARK: — что показывает окно сэмпла

    /// Зажатый шаг (первый) на выбранной дорожке.
    var firstHeld: Int? {
        return channel == .track ? heldSteps.min() : nil
    }

    /// Звук окна сэмпла: пока зажат шаг со своим звуком — его звук.
    var shownSound: String {
        if let h = firstHeld, let s = track.step(h)?.sound { return s }
        return track.sample
    }

    /// Значение ручки для окна синта и иконки: p-lock зажатого шага, при игре — играющего шага, иначе ручка дорожки
    /// (как knobState).
    func synthValue(_ p: ParamDef) -> Double {
        let t = track
        if let held = heldSteps.min() {
            if let v = t.step(held)?.locks[p.id] { return v }
        } else if playing {
            let pos = openPlayPos
            if pos >= 0, let v = t.step(pos)?.locks[p.id] { return v }
        }
        return t.params[p.id] ?? p.def
    }

    /// Значения иконки движка: ручки 1.1, 1.2, 1.3 и Decay 2.2 (0…1); ступенчатая — скачком по пункту.
    func iconValues(_ engine: Int) -> IconValues {
        let grid: [ParamDef] = Params.synthGrids[engine]
        func norm(_ slot: Int) -> Double {
            let p = grid[slot]
            let n: Double = p.toNorm(synthValue(p))
            if let s = p.steps { return (Double(Params.stepIndex(n, s)) + 0.5) / Double(s) }
            return n
        }
        return IconValues(h: norm(0), t: norm(4), m: norm(8), d: norm(5))
    }

    func sample(_ key: String) -> SampleData? {
        return key.isEmpty ? nil : store.data(key)
    }

    func sampleName(_ key: String) -> String {
        if key.isEmpty { return "No sample" }
        return project.files[key] ?? "file"
    }

    func sampleRoot(_ key: String) -> Int? {
        return project.roots[key]
    }

    // MARK: — загрузка файлов

    /// Меню звука → LOAD: системный выбор файлов («Файлы» iPad и iCloud Drive), можно сразу несколько.
    func chooseFiles(steps: [Int]) {
        importTarget = ImportTarget(track: selectedTrack, steps: steps)
        importing = true
    }

    /// Выбранные файлы: все ложатся в папку дорожки, первый звучит (для шагов — первый становится их звуком).
    func importFiles(_ urls: [URL]) {
        guard let target = importTarget else { return }
        importTarget = nil
        let dir = store.dir
        Task.detached(priority: .userInitiated) {
            var loaded: [SampleStore.Loaded] = []
            for u in urls {
                if let l = SampleStore.decode(u, dir: dir) { loaded.append(l) }
            }
            let result = loaded
            await MainActor.run { self.addLoaded(result, target) }
        }
    }

    private func addLoaded(_ loaded: [SampleStore.Loaded], _ target: ImportTarget) {
        if loaded.isEmpty { return }
        for l in loaded { store.add(l.key, l.data) }
        samplesVersion += 1
        let keys: [String] = loaded.map { $0.key }
        let i = target.track
        guard i < project.tracks.count else { return }
        edit { p in
            for l in loaded {
                p.files[l.key] = l.name
                if let r = l.root { p.roots[l.key] = r }
            }
            if target.steps.isEmpty {
                p.tracks[i].addSamples(keys)
            } else {
                p.tracks[i].addSamplesQuiet(keys)
                p.tracks[i].setStepSound(target.steps, keys[0])
            }
        }
    }

    // MARK: — стрелки и меню звука

    /// Стрелка: соседний звук папки; с зажатыми шагами — звук этих шагов (p-lock).
    func folderArrow(_ dir: Int) {
        guard channel == .track else { return }
        let held = heldSteps
        if held.isEmpty {
            editTrack { t in t.stepFolder(dir) }
        } else {
            usedSteps.formUnion(held)
            editTrack { t in t.stepFolderOnSteps(held.sorted(), dir) }
        }
    }

    /// Подпись между стрелками: «номер / всего».
    var folderLabel: String {
        let pos = track.folderPos(held: firstHeld)
        if pos.1 == 0 { return "folder" }
        return "\(pos.0 > 0 ? String(pos.0) : "–") / \(pos.1)"
    }

    /// Тап по окну сэмпла: меню звука (зажаты шаги — для них; пальцы потом можно убрать).
    func openSoundMenu() {
        guard channel == .track else { return }
        let held = heldSteps.sorted()
        usedSteps.formUnion(held)
        soundMenu = SoundMenuState(steps: held)
    }

    /// Меню звука шагов → TRACK: снова звук дорожки.
    func stepSoundToTrack(_ steps: [Int]) {
        editTrack { t in t.setStepSound(steps, nil) }
    }

    /// Голоса синта Plaits: таблицы — Resources/plaits (в bundle — в корне или в подпапке).
    func installSynth() {
        guard let dir = PlaitsSelfTest.directory(of: "lut_sine.f32", in: Bundle.main,
                                                 subdirectories: ["plaits", "Resources/plaits"]),
              let r = PlaitsResources.load(dir: dir) else {
            trace("plaits tables not found")
            return
        }
        audio.core.installSynth(r)
    }

    /// MI SYNTH: движок на дорожку (setTrackSynth веба) или, с зажатыми шагами, — их свой звук.
    func pickSynth(_ engine: Int, steps: [Int]) {
        let key = SynthKey.key(engine)
        if steps.isEmpty {
            editTrack { t in t.setSynth(engine) }
        } else {
            editTrack { t in t.setStepSound(steps, key) }
        }
    }

    /// SAMPLER: дорожка без звука и сразу чистое окно редактора сэмпла (LOAD).
    func cleanSampler() {
        editTrack { t in t.sample = "" }
        openEditor()
    }

    // MARK: — редактор сэмпла

    func openEditor() {
        patternView = false
        editorOpen = true
    }

    func closeEditor() {
        editorOpen = false
        heldFlag = nil
        if previewOn { audio.core.events.push(.previewStop) }
    }

    /// Сэмпл выбранной дорожки для редактора ('' — нет или не дорожка).
    var editorKey: String {
        return channel == .track ? track.sample : ""
    }

    /// TRIM, NORMALIZE, MONO: отредактированная копия сразу на дорожке (в папке — на месте исходного).
    func applyEdit(_ make: @escaping (SampleData) -> SampleData) {
        let key = editorKey
        guard let src = sample(key) else { return }
        let i = selectedTrack
        let dir = store.dir
        let name = sampleName(key)
        let root = sampleRoot(key)
        Task.detached(priority: .userInitiated) {
            let out = make(src)
            let newKey = SampleStore.store(out, dir: dir)
            await MainActor.run {
                self.store.add(newKey, out)
                self.samplesVersion += 1
                guard i < self.project.tracks.count else { return }
                self.edit { p in
                    p.files[newKey] = name
                    if let r = root { p.roots[newKey] = r }
                    p.tracks[i].replaceSample(key, newKey)
                }
            }
        }
    }

    func trimSample(_ a: Double, _ b: Double) {
        applyEdit { SampleEdit.trim($0, a, b) }
    }

    func normalizeSample() {
        applyEdit { SampleEdit.normalize($0) }
    }

    func monoSample() {
        applyEdit { SampleEdit.mono($0) }
    }

    func clearSample() {
        editTrack { t in t.clearSample() }
    }

    /// ▶: выделение (или весь сэмпл) в исходной высоте сразу на выход; повторный тап — стоп.
    func togglePreview(_ a: Double, _ b: Double) {
        ensureAudio()
        if previewOn {
            audio.core.events.push(.previewStop)
            return
        }
        let key = editorKey
        if key.isEmpty { return }
        previewOn = true
        audio.core.events.push(.preview(hash: SoundKey.hash(key), a: a, b: b))
    }

    // MARK: — маркеры нарезки

    var editorMarks: [SliceMark] {
        return track.sliceMarks(editorKey)
    }

    var editorMarkNotes: [Int] {
        return Slices.notes(editorMarks, map: settings.sliceMap, scale: project.scale, root: project.root, octave: octave)
    }

    func addSlice(at f: Double) {
        let key = editorKey
        if key.isEmpty { return }
        editTrack { t in t.addSlice(key, at: f) }
    }

    func deleteSlice(_ idx: Int) {
        let key = editorKey
        editTrack { t in t.deleteSlice(key, idx) }
    }

    /// Внутри жеста (beginGesture / endGesture): одна запись в UNDO.
    func moveSlice(_ idx: Int, at f: Double, gap: Double) {
        let key = editorKey
        editTrack { t in t.moveSlice(key, idx, at: f, gap: gap) }
    }

    /// Держат флажок + клавиша: маркеру — эта нота. true — нота ушла маркеру (флажок держат, не двигая).
    func assignHeldSlice(_ note: Int) -> Bool {
        guard editorOpen, let idx = heldFlag, !editorKey.isEmpty else { return false }
        let key = editorKey
        let notes = editorMarkNotes
        var ok = false
        flagUsed = true
        editTrack { t in ok = t.setSliceNote(key, idx, note: note, notes: notes) }
        if !ok {
            // Нота уже у другого маркера — не назначается: флажок на 0,5 с красный.
            refusedFlag = (idx, Date.timeIntervalSinceReferenceDate + 0.5)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.refusedFlag = (-1, 0)
            }
        }
        return true
    }

    func setSliceMap(_ m: SliceMap) {
        updateSettings { s in s.sliceMap = m }
        publishAudio()
    }

    // MARK: — живые ноты (пианоролл)

    func liveNoteOn(track t: Int, notes: [Int], id: Int, velocity: Double) {
        ensureAudio()
        let v: Float = settings.velocity ? Float(velocity) : 1
        for n in notes { audio.core.events.push(.noteOn(track: t, note: n, id: id, velocity: v)) }
    }

    func liveNoteOff(track t: Int, id: Int) {
        audio.core.events.push(.noteOff(track: t, id: id))
    }

    // MARK: — микшер (MIX)

    /// Ручка громкости дорожки slot (MIX): подпись — имя дорожки; несуществующая — nil (серая).
    func mixParam(_ slot: Int) -> ParamDef? {
        guard slot < project.tracks.count else { return nil }
        let base = Params.mixGrid[slot]
        return ParamDef(id: base.id, label: project.tracks[slot].name, min: base.min, max: base.max, def: base.def,
                        format: base.format)
    }

    func toggleMute(_ i: Int) {
        guard i < project.tracks.count else { return }
        edit { p in
            p.tracks[i].mute.toggle()
            if p.tracks[i].mute { p.tracks[i].solo = false }
        }
    }

    func toggleSolo(_ i: Int) {
        guard i < project.tracks.count else { return }
        edit { p in
            p.tracks[i].solo.toggle()
            if p.tracks[i].solo { p.tracks[i].mute = false }
        }
    }

    /// Двойной тап по ручке громкости — меню дорожки; по серой — ADD TRACK.
    func openTrackMenu(_ slot: Int) {
        if slot < project.tracks.count {
            trackMenu = TrackMenuState(slot: slot, add: false)
        } else if project.canAddTrack {
            trackMenu = TrackMenuState(slot: slot, add: true)
        }
    }

    func addTrack() {
        edit { p in p.addTrack() }
    }

    func copyTrack(_ i: Int) {
        guard i < project.tracks.count else { return }
        trackClipboard = project.tracks[i]
        hasTrackClip = true
    }

    func pasteTrack(_ i: Int) {
        guard let c = trackClipboard else { return }
        edit { p in p.pasteTrack(i, c) }
        if i == selectedTrack {
            heldSteps.removeAll()
            viewPage = min(viewPage, track.pages.count - 1)
        }
    }

    func deleteTrack(_ i: Int) {
        guard project.canDeleteTrack(i) else { return }
        let sel = selectedTrack
        edit { p in p.deleteTrack(i) }
        if sel >= project.tracks.count || sel > i { selectTrackIndex(max(0, min(project.tracks.count - 1, sel > i ? sel - 1 : sel))) }
    }

    func renameTrack(_ i: Int, _ name: String) {
        edit { p in p.renameTrack(i, name) }
    }

    /// Перестановка в MIX: выбранная дорожка остаётся выбранной.
    func moveTrack(_ from: Int, _ to: Int) {
        let id = track.id
        edit { p in p.moveTrack(from, to) }
        if let k = project.tracks.firstIndex(where: { $0.id == id }) { selectTrackIndex(k) }
    }

    // MARK: — страницы

    /// Перенос страницы (удержание миниатюры и протягивание); открыта — перенесённая.
    func movePage(_ from: Int, _ to: Int) {
        guard channel == .track else { return }
        editTrack { t in t.movePage(from, to) }
        viewPage = min(to, track.pages.count - 1)
        heldSteps.removeAll()
    }
}
