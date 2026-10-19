import Foundation

/// Имена кнопок — целей MIDI (S13b, как registerAction веба). Кнопка AUTO заменена на ROLL (пианоролл, решение
/// пользователя); ячейки и строки сетки паттернов — по месту в окне строк 1–8.
enum MidiButtons {
    static let bpm = "BPM"
    static let fixed: [String] = ["PLAY", "REC", "PATTERNS", "EQ", "ROLL", "UNDO", "METRONOME", "CHORD", "OCTAVE ▲",
                                  "OCTAVE ▼", "LFO1", "LFO2", "LFO3", "ENV", "FX", "MOD", "MORPH", "MIX", "MST",
                                  "ARM MST", "GRID ▲", "GRID ▼", bpm]

    /// Все имена (список действий нажатия ручки в окне MIDI MAP): постоянные, затем с номерами.
    static var all: [String] {
        var out: [String] = fixed.filter { $0 != bpm }
        for n in 1...Params.maxTracks { out.append("T\(n)") }
        for p in ["MUTE", "SOLO", "ARM"] {
            for n in 1...Params.maxTracks { out.append("\(p) \(n)") }
        }
        for n in 1...16 { out.append("STEP \(n)") }
        for n in 1...25 { out.append("KEY \(n)") }
        for n in 1...8 { out.append("PROG CHORD \(n)") }
        for n in 1...8 { out.append("ROW \(n)") }
        return out
    }

    static func clip(_ track: Int, _ row: Int) -> String {
        return "CLIP \(track + 1).\(row + 1)"
    }

    /// Номер в конце имени («MUTE 3» → 3); nil — другое имя.
    static func number(_ name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    /// Ячейка «CLIP t.r» → (дорожка, строка окна), с нуля.
    static func cell(_ name: String) -> (Int, Int)? {
        guard name.hasPrefix("CLIP ") else { return nil }
        let parts = name.dropFirst(5).split(separator: ".")
        guard parts.count == 2, let t = Int(parts[0]), let r = Int(parts[1]) else { return nil }
        return (t - 1, r - 1)
    }
}

/// Кнопки по MIDI: нажатие и отпускание — те же действия, что у пальца.
extension AppModel {
    func midiButtonPress(_ name: String) {
        ensureAudio()
        if midiPressFixed(name) { return }
        if let (t, r) = MidiButtons.cell(name) {
            let rows: [Int?] = gridWindow.rows
            guard t < project.tracks.count, r < rows.count, let k = rows[r] else { return }
            tapCell(t, k)
            return
        }
        if let n = MidiButtons.number(name, prefix: "ROW ") {
            let rows: [Int?] = gridWindow.rows
            guard n >= 1 && n <= rows.count, let k = rows[n - 1] else { return }
            queueScene(k)
            return
        }
        if let n = MidiButtons.number(name, prefix: "T"), n >= 1 && n <= project.tracks.count {
            select(track: n - 1)
            return
        }
        if midiPressTrackButton(name) { return }
        if let n = MidiButtons.number(name, prefix: "KEY "), let notes = keyNotes(n - 1) {
            keyDown(id: midiKeyId(name), notes: notes, velocity: 1)
            return
        }
        if let n = MidiButtons.number(name, prefix: "PROG CHORD "), let notes = chipNotes(n - 1) {
            keyDown(id: midiKeyId(name), notes: notes, velocity: 1)
            return
        }
        if let n = MidiButtons.number(name, prefix: "STEP "), n >= 1 && n <= 16 {
            let index: Int = viewPages.lowerBound * 16 + n - 1
            heldSteps.insert(index)
            midiRun.stepDown[index] = Date.timeIntervalSinceReferenceDate
            beginGesture()
        }
    }

    func midiButtonRelease(_ name: String) {
        switch name {
        case "LFO1": setSource(1, held: false)
        case "LFO2": setSource(2, held: false)
        case "LFO3": setSource(3, held: false)
        case "ENV": setSource(4, held: false)
        case "FX": pageRelease(.fx)
        case "MOD": pageRelease(.mod)
        case "MORPH": morphRelease()
        default: break
        }
        if name.hasPrefix("KEY ") || name.hasPrefix("PROG CHORD ") { keyUp(id: midiKeyId(name)) }
        if let n = MidiButtons.number(name, prefix: "STEP "), n >= 1 && n <= 16 {
            let index: Int = viewPages.lowerBound * 16 + n - 1
            guard let t0 = midiRun.stepDown.removeValue(forKey: index) else { return }
            let quick: Bool = Date.timeIntervalSinceReferenceDate - t0 < 0.35
            if quick && !usedSteps.contains(index) { toggleStep(index) }
            heldSteps.remove(index)
            usedSteps.remove(index)
            endGesture()
        }
    }

    /// Постоянные кнопки (верхняя панель, клавиатура, колонки, MIX, MST): true — нажатие обработано.
    private func midiPressFixed(_ name: String) -> Bool {
        let sources: [String] = ["LFO1", "LFO2", "LFO3", "ENV"]
        if let i = sources.firstIndex(of: name) {
            if channel != .master { setSource(i + 1, held: true) }
            return true
        }
        switch name {
        case "PLAY": togglePlay()
        case "REC": toggleRec()
        case "PATTERNS": togglePatterns()
        case "EQ": toggleEqView()
        case "ROLL": toggleRoll()
        case "UNDO": undoTapped()
        case "METRONOME": toggleMetronome()
        case "CHORD": toggleChord()
        case "OCTAVE ▲": setOctave(octave + 1)
        case "OCTAVE ▼": setOctave(octave - 1)
        case "FX": pagePress(.fx)
        case "MOD": pagePress(.mod)
        case "MORPH": morphPress()
        case "MIX": select(channel: .mix)
        case "MST": select(channel: .master)
        case "ARM MST": stemTap(StemRing.master)
        case "GRID ▲": gridArrow(-1)
        case "GRID ▼": gridArrow(1)
        default: return false
        }
        return true
    }

    /// MUTE n, SOLO n, ARM n (кнопки M, S, ● в MIX; работают и вне MIX).
    private func midiPressTrackButton(_ name: String) -> Bool {
        let tracks: Int = project.tracks.count
        if let n = MidiButtons.number(name, prefix: "MUTE "), n >= 1 && n <= tracks {
            toggleMute(n - 1)
            return true
        }
        if let n = MidiButtons.number(name, prefix: "SOLO "), n >= 1 && n <= tracks {
            toggleSolo(n - 1)
            return true
        }
        if let n = MidiButtons.number(name, prefix: "ARM "), n >= 1 && n <= tracks {
            stemTap(n - 1)
            return true
        }
        return false
    }

    /// Касание клавиши для KEY n и PROG CHORD n (не пересекается с нотами MIDI и пальцами).
    private func midiKeyId(_ name: String) -> Int {
        let k: Int = MidiButtons.number(name, prefix: "KEY ") ?? (100 + (MidiButtons.number(name, prefix: "PROG CHORD ") ?? 0))
        return Int.min + 10_000 + k
    }
}
