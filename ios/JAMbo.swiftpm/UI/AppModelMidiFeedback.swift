import Foundation

/// Обратная связь MIDI (S13d, как sendFeedback веба): по таймеру UI (drain), не чаще раза в 30 мс. Ручка шлёт значение,
/// которое показывает экран (p-lock зажатого или играющего шага, ручка GLOBAL — параметр своего места), в своём
/// диапазоне Range; регуляторы BPM, LEVEL, XFADER — так же; кнопка — 127, когда горит, иначе 0. Только изменения.
extension AppModel {
    func tickMidiFeedback() {
        let now: Double = Date.timeIntervalSinceReferenceDate
        if now - midiRun.feedbackAt < 0.03 { return }
        midiRun.feedbackAt = now
        let ms: MidiSettings = settings.midi
        if ms.mappings.isEmpty || !midi.started { return }
        if midiRun.feedbackGen != midi.generation {
            midiRun.feedbackGen = midi.generation
            midiRun.feedback.reset()
        }
        var out: [Int32: [UInt32]] = [:]
        var seen: Set<String> = []
        for m in ms.feedbackMappings(midiContext) {
            guard let dst = m.feedbackDest(default: ms.feedback), midi.hasDestination(dst) else { continue }
            // Один источник на выходе — одно значение (маппинги с разных входов не спорят).
            if !seen.insert(MidiFeedback.key(dest: dst, src: m.src)).inserted { continue }
            guard let v = midiFeedbackValue(m) else { continue }
            if !midiRun.feedback.change(dest: dst, src: m.src, value: v) { continue }
            out[dst, default: []].append(MidiFeedback.word(m.src, value: v))
        }
        for (dst, words) in out { midi.send(words, to: dst) }
    }

    /// Значение 0–127 маппинга; nil — слать нечего (нет параметра, нет перехода MIX).
    private func midiFeedbackValue(_ m: MidiMapping) -> Int? {
        switch m.target {
        case .knob(let s):
            guard let n = midiKnobNorm(s, m) else { return nil }
            return m.feedbackValue(n)
        case .press:
            return nil
        case .button(let name):
            if name == MidiButtons.bpm {
                let lo: Double = Params.bpmMin
                return m.feedbackValue((project.bpm - lo) / (Params.bpmMax - lo))
            }
            if name == MidiButtons.level {
                let lo: Double = Params.volMin
                return m.feedbackValue((meterVol(meterChannel) - lo) / -lo)
            }
            if name == MidiButtons.xfader {
                guard let tr = mix else { return nil }
                return m.feedbackValue(tr.pos)
            }
            return midiLit(name) ? 127 : 0
        }
    }

    /// Положение ручки, как на экране; GLOBAL не на своём месте — основное значение параметра места (без p-lock).
    private func midiKnobNorm(_ s: Int, _ m: MidiMapping) -> Double? {
        if let place = m.place, !place.matches(midiContext) { return placeNorm(s, place) }
        guard param(s) != nil else { return nil }
        return knobState(s).norm
    }

    /// Значение ручки slot на месте place — без смены выбранной дорожки и страницы (как withKnobPlace, но только чтение).
    private func placeNorm(_ s: Int, _ place: MidiPlace) -> Double? {
        let tracks: [Track] = project.tracks
        switch place.page {
        case .mix:
            guard s < tracks.count else { return nil }
            let p: ParamDef = Params.mixGrid[s]
            return p.toNorm(tracks[s].vol)
        case .master:
            let p: ParamDef = Params.masterGrid[s]
            return p.id.isEmpty ? nil : p.toNorm(masterValue(p))
        case .fx:
            let p: ParamDef = fxParam(s)
            return p.id.isEmpty ? nil : p.toNorm(fxValue(p))
        case .mod, .track:
            guard place.track < tracks.count else { return nil }
            let t: Track = tracks[place.track]
            let p: ParamDef = place.page == .mod ? Params.modGrid[s] : Params.grid(sound: t.sample)[s]
            if p.id.isEmpty { return nil }
            return p.toNorm(t.params[p.id] ?? p.def)
        }
    }

    /// Кнопка горит (как на экране; у кнопок без состояния — UNDO, OCTAVE, стрелки сетки — никогда).
    func midiLit(_ name: String) -> Bool {
        switch name {
        case "PLAY": return playing
        case "REC": return recOn
        case "PATTERNS": return patternView
        case "EQ": return eqView
        case "ROLL": return rollView
        case "METRONOME": return metronome
        case "CHORD": return chordMode[selectedTrack]
        case "LFO1": return heldSources.contains(1)
        case "LFO2": return heldSources.contains(2)
        case "LFO3": return heldSources.contains(3)
        case "ENV": return heldSources.contains(4)
        case "FX": return fxHeld
        case "MOD": return modHeld
        case "MORPH": return morph
        case "MIX": return channel == .mix
        case "MST": return channel == .master
        case "ARM MST": return stemLit(StemRing.master)
        default: return midiLitNumbered(name)
        }
    }

    /// Кнопки с номером: дорожки, M / S / ●, шаги, клавиши, аккорды, ячейки и строки сетки паттернов.
    private func midiLitNumbered(_ name: String) -> Bool {
        let tracks: [Track] = project.tracks
        if let (t, r) = MidiButtons.cell(name) {
            let rows: [Int?] = gridWindow.rows
            guard t >= 0 && t < tracks.count, r >= 0 && r < rows.count, let k = rows[r] else { return false }
            return tracks[t].clipFilled(k) && tracks[t].slot == k && !tracks[t].stopped
        }
        if let n = MidiButtons.number(name, prefix: "ROW ") {
            let rows: [Int?] = gridWindow.rows
            guard n >= 1 && n <= rows.count, let k = rows[n - 1] else { return false }
            return playing && live.sceneRow == k
        }
        if let n = MidiButtons.number(name, prefix: "T"), n >= 1 {
            return channel == .track && selectedTrack == n - 1
        }
        if let n = MidiButtons.number(name, prefix: "MUTE "), n >= 1 && n <= tracks.count { return tracks[n - 1].mute }
        if let n = MidiButtons.number(name, prefix: "SOLO "), n >= 1 && n <= tracks.count { return tracks[n - 1].solo }
        if let n = MidiButtons.number(name, prefix: "ARM "), n >= 1 && n <= tracks.count { return stemLit(n - 1) }
        if let n = MidiButtons.number(name, prefix: "STEP "), n >= 1 && n <= 16 {
            return seq.step(viewPages.lowerBound * 16 + n - 1)?.on ?? false
        }
        // Клавиши и аккорды — пока зажаты (пальцем или с MIDI).
        let pressed: Set<Int> = pressedNotes
        if let n = MidiButtons.number(name, prefix: "KEY "), let notes = keyNotes(n - 1) {
            return !notes.isEmpty && notes.allSatisfy { pressed.contains($0) }
        }
        if let n = MidiButtons.number(name, prefix: "PROG CHORD "), let notes = chipNotes(n - 1) {
            return !notes.isEmpty && notes.allSatisfy { pressed.contains($0) }
        }
        return false
    }
}
