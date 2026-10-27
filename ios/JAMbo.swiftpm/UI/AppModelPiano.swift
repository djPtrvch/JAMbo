import Foundation

// Клавиатура, гамма и запись нот с REC (как piano.ts и recordNotes в вебе).

/// Зажатая клавиша: дорожка, ноты, записанный шаг (длина — при отпускании) и время нажатия (с).
struct KeyHold {
    let track: Int
    let notes: [Int]
    let recIndex: Int?
    let t0: Double
}

/// Меню выбора (SCALE, ROOT, PROGRESSION): пункты, столбцы, выбранный, рамка поля (в координатах экрана).
struct ChoiceState {
    let options: [String]
    let columns: Int
    let current: Int
    let anchor: CGRect
    let pick: (Int) -> Void
    /// Ширина меню (nil — по столбцам, 104 на столбец); меню — от левого края anchor.
    var width: CGFloat? = nil
}

extension AppModel {
    // MARK: — гамма, нота, октава, прогрессия

    var scale: Int { return project.scale }

    func setScale(_ v: Int) {
        let n = Scales.wrap(v, Scales.all.count)
        if n != project.scale { edit { p in p.scale = n; writeLead(&p) } }
    }

    func setRoot(_ v: Int) {
        let n = Scales.wrap(v, 12)
        if n != project.root { edit { p in p.root = n; writeLead(&p) } }
    }

    func setOctave(_ o: Int) {
        let o2 = min(topOctave, max(Scales.octaveMin, o))
        if o2 == octave { return }
        octaves[selectedTrack] = o2
        // Ноты маркеров нарезки идут от первой клавиши клавиатуры.
        publishAudio()
    }

    func setProgression(_ v: Int) {
        progression[selectedTrack] = Scales.wrap(v, Scales.progressions.count)
    }

    func toggleChord() {
        chordMode[selectedTrack].toggle()
    }

    func toggleRec() {
        recOn.toggle()
        endRecTake()
        syncArrRecord()
    }

    /// Верхняя октава клавиатуры выбранной дорожки (ноты не выше 127).
    var topOctave: Int {
        return Scales.topOctave(scale: project.scale, root: project.root, octaves: settings.pianoOctaves,
                                chord: chordMode[selectedTrack])
    }

    var keyCount: Int {
        return Scales.keyCount(scale: project.scale, octaves: settings.pianoOctaves)
    }

    /// Нота клавиши k (ступень гаммы от корневой ноты октавы).
    func keyNote(_ k: Int) -> Int {
        return Scales.note(scale: project.scale, root: project.root, octave: octave, degree: k)
    }

    /// Что играет клавиша k: нота или (CHORD) трезвучие от неё.
    func keyNotes(_ k: Int) -> [Int]? {
        if k >= keyCount { return nil }
        if chordMode[selectedTrack] { return Scales.chord(scale: project.scale, root: project.root, octave: octave, degree: k) }
        return [keyNote(k)]
    }

    var progressionDegrees: [Int] {
        return Scales.progressions[progression[selectedTrack]].degrees
    }

    func chipNotes(_ c: Int) -> [Int]? {
        let d = progressionDegrees
        if c >= d.count || !chordMode[selectedTrack] { return nil }
        return Scales.chord(scale: project.scale, root: project.root, octave: octave, degree: d[c])
    }

    func chipName(_ c: Int) -> String {
        return Scales.chordName(scale: project.scale, root: project.root, octave: octave, degree: progressionDegrees[c])
    }

    var pressedNotes: Set<Int> {
        var all = Set<Int>()
        for n in pressedKeys.values { all.formUnion(n) }
        return all
    }

    /// Ноты зажатого шага (триг) — подсвечены на клавишах и аккордах, как звучащие.
    var heldNotes: Set<Int> {
        guard channel == .track, let held = heldSteps.min(), let s = track.step(held), s.on else { return [] }
        return Set(s.notes)
    }

    /// Ноты, обведённые белым: ноты зажатого шага, иначе выбранные (нет выбранных — корневая).
    var shownNotes: Set<Int> {
        if channel == .track, let held = heldSteps.min() { return Set(track.step(held)?.notes ?? []) }
        let sel = selNotes[selectedTrack]
        return sel.isEmpty ? [keyNote(0)] : Set(sel)
    }

    /// Ноты звучащего шага выбранной дорожки (белая заливка, пока дорожка мигает).
    var playingNotes: Set<Int> {
        let t = selectedTrack
        guard playing, live.flashing[t] else { return [] }
        let pos = trackPlayPos
        if pos < 0 { return [] }
        return Set(track.step(pos)?.notes ?? [])
    }

    // MARK: — нажатия клавиш

    /// Касание клавиши (S12): с KEY VELOCITY и работающим акселерометром нота звучит через 15 мс — сила по толчку
    /// iPad в окне касания; без датчика — по месту касания (fallback).
    func keyPress(id: Int, notes: [Int], fallback: Double) {
        guard settings.velocity && tapSensor.running else {
            keyDown(id: id, notes: notes, velocity: fallback)
            return
        }
        let at: Double = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + TapVelocity.after) { [weak self] in
            guard let self = self else { return }
            let v: Double = self.tapSensor.velocity(at: at) ?? fallback
            self.keyDown(id: id, notes: notes, velocity: v)
        }
    }

    /// Клавишу отпустили: с задержкой нажатия — после него (тот же сдвиг 15 мс).
    func keyRelease(id: Int) {
        guard settings.velocity && tapSensor.running else {
            keyUp(id: id)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TapVelocity.after) { [weak self] in self?.keyUp(id: id) }
    }

    /// Нажатие клавиши или аккорда (id — касание): с REC при игре — запись; иначе выбор нот или замена нот зажатых шагов.
    /// track — дорожка для нот с MIDI по каналам (S13a; без неё — выбранная; ноты другой дорожки не подсвечивают
    /// клавиши и не становятся выбранными).
    func keyDown(id: Int, notes: [Int], velocity: Double, track: Int? = nil) {
        ensureAudio()
        let ti: Int = track ?? selectedTrack
        let own: Bool = ti == selectedTrack
        if own { pressedKeys[id] = notes }
        // Держат флажок маркера нарезки в редакторе: клавиша назначает ему ноту (и звучит).
        if track == nil, let first = notes.first, assignHeldSlice(first) {
            keyHolds[id] = KeyHold(track: ti, notes: [first], recIndex: nil, t0: Date.timeIntervalSinceReferenceDate)
            liveNoteOn(track: ti, notes: [first], id: id, velocity: velocity)
            return
        }
        // Нажатая нота сразу звучит на выбранной дорожке (живой наигрыш); держится, пока держат клавишу.
        liveNoteOn(track: ti, notes: notes, id: id, velocity: velocity)
        var recIndex: Int? = nil
        // С AUTO запись — аранжировки, ноты в паттерн не пишутся.
        if recOn && playing && !(arrAuto && arrPlay) && heldSteps.isEmpty && channel == .track {
            recIndex = record(track: ti, notes: notes, velocity: settings.velocity ? velocity : nil)
        } else if own {
            inputNotes()
        }
        // Capture: без REC и без зажатых шагов нажатие запоминается.
        if !(recOn && playing) && heldSteps.isEmpty && channel == .track {
            captureDown(id: id, track: ti, notes: notes, velocity: settings.velocity ? velocity : nil)
        }
        keyHolds[id] = KeyHold(track: ti, notes: notes, recIndex: recIndex, t0: Date.timeIntervalSinceReferenceDate)
    }

    /// Отпустили клавишу: с REC — длина записанной ноты по времени удержания.
    func keyUp(id: Int) {
        pressedKeys.removeValue(forKey: id)
        guard let k = keyHolds.removeValue(forKey: id) else { return }
        liveNoteOff(track: k.track, id: id)
        captureUp(id: id, track: k.track)
        guard let index = k.recIndex else { return }
        let stepSeconds: Double = 60 / project.bpm / 4
        let len = RecordClock.length(seconds: Date.timeIntervalSinceReferenceDate - k.t0, stepSeconds: stepSeconds)
        writeTake(track: k.track) { t in t.recordLength(index, len) }
    }

    /// Выбранными становятся все зажатые сейчас ноты; если зажат шаг — его ноты заменяются зажатыми.
    private func inputNotes() {
        let notes: [Int] = pressedNotes.sorted()
        if notes.isEmpty { return }
        if !heldSteps.isEmpty && channel == .track {
            let held = heldSteps
            usedSteps.formUnion(held)
            editTrack { t in
                for i in held {
                    t.withStep(i) { s in
                        s.setNotes(notes)
                        s.on = true
                    }
                }
            }
            return
        }
        selNotes[selectedTrack] = notes
    }

    // MARK: — запись с REC

    /// Шаг, на который ложится нота сейчас: по ходу транспорта из колбэка с поправкой на задержку выхода.
    private func record(track ti: Int, notes: [Int], velocity: Double?) -> Int? {
        guard let k = heardTick() else { return nil }
        let merge: Bool = lastRec.track == ti && lastRec.tick == k
        lastRec = (ti, k)
        let tr = project.tracks[ti]
        guard let clip = tr.clips[tr.slot] else { return nil }
        // Скорость клипа (S14): позиция прохода на тике k.
        let index = clip.playIndex(clip.localStep(k - live.trackStart[ti]))
        let overdub = settings.record.overdub
        takeTracks.insert(ti)
        takeWritten.insert(ti * 1000 + index)
        writeTake(track: ti) { t in t.recordNotes(index, notes, merge: merge, overdub: overdub, velocity: velocity) }
        return index
    }

    /// Тик транспорта, который слышен сейчас (с поправкой на задержку выхода; QUANTIZE — ближайший); nil — стоит.
    func heardTick() -> Int? {
        let c = audio.core.sequencer.clock.read()
        guard c.playing else { return nil }
        let heard: Double = audio.hostNow() - audio.outputLatency
        let frame: Double = c.blockFrame + (heard - c.blockHost) * AudioCore.sampleRate
        return RecordClock.tick(frame: frame, nextTick: c.nextTick, nextFrame: c.nextFrame, stepFrames: c.stepFrames,
                                quantize: settings.record.quantize)
    }

    /// Правка дубля: первая нота — новая запись в UNDO, следующие (пока не было других действий) — в неё же.
    /// Пишется в играющий клип дорожки, что бы ни было открыто в секвенсоре.
    private func writeTake(track ti: Int, _ change: (inout Track) -> Void) {
        if recTake >= 0 && recTake == history.serial {
            applyInTake { p in AppModel.inPlaying(&p.tracks[ti], change) }
            return
        }
        let before = history.serial
        edit { p in AppModel.inPlaying(&p.tracks[ti], change) }
        recTake = history.serial != before ? history.serial : -1
        if recTake < 0 {
            takeTracks.removeAll()
            takeWritten.removeAll()
        }
    }

    /// REC или PLAY выключены — дубль закончен.
    func endRecTake() {
        recTake = -1
        takeTracks.removeAll()
        takeWritten.removeAll()
        lastRec = (-1, -1)
    }

    /// OVERDUB OFF: шаг дорожки дубля, по которому проходит запись, очищается (кроме записанных в дубле).
    func recPassStep(_ ti: Int, _ pos: Int) {
        if settings.record.overdub || recTake < 0 || recTake != history.serial { return }
        if !takeTracks.contains(ti) || takeWritten.contains(ti * 1000 + pos) { return }
        guard ti < project.tracks.count else { return }
        let tr = project.tracks[ti]
        guard let s = tr.clips[tr.slot]?.step(pos) else { return }
        if !s.on && s.sound == nil && s.locks.isEmpty { return }
        applyInTake { p in AppModel.inPlaying(&p.tracks[ti]) { t in _ = t.clearPassStep(pos) } }
    }

    /// Правка играющего клипа дорожки (запись с REC).
    static func inPlaying(_ t: inout Track, _ change: (inout Track) -> Void) {
        let k = t.slot
        t.editing(k) { tr in change(&tr) }
    }

    // MARK: — SWING (S12): значение дорожки, без p-lock и LFO/ENV

    var trackSwing: Double {
        return track.params["swing"] ?? Params.swing.def
    }

    func setSwing(_ v: Double) {
        let x: Double = min(Params.swing.max, max(Params.swing.min, v))
        editTrack { t in t.params["swing"] = x }
    }
}
