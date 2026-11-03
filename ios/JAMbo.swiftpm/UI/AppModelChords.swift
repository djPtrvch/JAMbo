import Foundation

// Режим CHORD: случайная прогрессия (SHIFT + CHORD) — запись аккордов в выбранные страницы открытого паттерна; на
// ударном движке (KICK, SNARE, HAT, CLAP, PERC) — случайный ритм стиля дорожки (DrumRhythm), стили — в окне CHORD.

extension AppModel {
    /// Тап по CHORD: с SHIFT — случайная прогрессия (режим не меняется), иначе — вкл./выкл. режима.
    func chordTap() {
        if shiftHeld {
            // SETTINGS → RANDOM: выключенный DRUMS или CHORDS — ничего.
            if drumTrack {
                if settings.randomDrums { writeRandomDrums() }
            } else if settings.randomChords {
                if arpMode { writeRandomArp() } else { writeRandomProgression() }
            }
        } else if arpMode {
            toggleArp()
        } else {
            toggleChord()
        }
    }

    /// Дорожка с ударным движком (KICK, SNARE, HAT, CLAP, PERC): у CHORD — стили ритма вместо типов аккорда.
    var drumTrack: Bool {
        guard channel == .track else { return false }
        return track.drumRole != nil
    }

    /// Стиль ритма выбранной дорожки (хранится в проекте, одна запись UNDO).
    /// SETTINGS → RANDOM → STYLE ALL TRACKS — всем ударным дорожкам проекта.
    func setDrumStyle(_ k: Int) {
        let v: Int = DrumRhythm.styleIndex(k)
        if settings.randomStyleAll {
            edit { p in
                for i in p.tracks.indices where p.tracks[i].drumRole != nil { p.tracks[i].drumStyle = v }
            }
        } else {
            editTrack { t in t.drumStyle = v }
        }
    }

    /// Окно и MIDI CHORD TYPE n: на ударной дорожке — стиль, в режиме ARP — направление, иначе — тип аккорда.
    func chooseChordType(_ k: Int) {
        if drumTrack {
            setDrumStyle(k)
        } else if arpMode {
            setArpDir(k)
        } else {
            setChordKind(k)
        }
    }

    /// Подписи окна CHORD и под словом на кнопке: стили, направления арпеджио или типы аккорда.
    var chordTypeNames: [String] {
        if drumTrack { return DrumRhythm.styles }
        return arpMode ? Arp.dirs : Scales.chordKinds
    }

    /// Номер выбранного типа (на ударной дорожке — стиля, в ARP — направления).
    var chordTypeIndex: Int {
        if drumTrack { return track.drumStyle }
        return arpMode ? track.arp.dir : chordKind[selectedTrack]
    }

    /// Подписи клавиш в режиме CHORD: аккорд и римская ступень («Em · i»).
    func chordKeyLabel(_ k: Int) -> String {
        return Chords.keyLabel(scale: project.scale, root: project.root, octave: octave, degree: k,
                               kind: chordKind[selectedTrack])
    }

    /// Выбранные страницы открытого паттерна (playFrom…playTo); вне их — открытая страница.
    private var chordPages: ClosedRange<Int> {
        let t: Track = track
        let last: Int = t.pages.count - 1
        if t.playFrom >= 0 && t.playFrom <= t.playTo && t.playTo <= last { return t.playFrom...t.playTo }
        let v: Int = max(0, min(viewPage, last))
        return v...v
    }

    /// Случайная прогрессия из 4 аккордов текущего типа на выбранные страницы поровну (одна страница — шаги 1, 5, 9,
    /// 13 по 4 шага; четыре — по странице на аккорд). Прежние шаги выбранных страниц стираются. Ноты — конкретные
    /// (гамма, корень, октава клавиатуры сейчас). Одна запись UNDO; режим CHORD не меняется.
    func writeRandomProgression() {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = Chords.random(scale: project.scale, avoid: lastRandomProgression, using: &g)
        lastRandomProgression = degrees
        let cs: [[Int]] = Chords.chords(degrees, scale: project.scale, root: project.root, octave: octave,
                                        kind: chordKind[selectedTrack])
        let range: ClosedRange<Int> = chordPages
        editTrack { t in t.writeProgression(cs, pages: range) }
    }

    /// Режим ARP: случайная прогрессия (как writeRandomProgression), разложенная по шагам выбранных страниц —
    /// четверть на аккорд, направление, октавы, RATE и GATE арпеджиатора. Одна запись UNDO; ARP не меняется.
    func writeRandomArp() {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = Chords.random(scale: project.scale, avoid: lastRandomProgression, using: &g)
        lastRandomProgression = degrees
        let cs: [[Int]] = Chords.chords(degrees, scale: project.scale, root: project.root, octave: octave,
                                        kind: chordKind[selectedTrack])
        let range: ClosedRange<Int> = chordPages
        let a: TrackArp = track.arp
        let total: Int = (range.upperBound - range.lowerBound + 1) * Params.stepsPerPage
        let notes: [ArpStepNote] = Arp.steps(cs, steps: total, dir: a.dir, octaves: a.octaves, rate: a.rate,
                                             gate: a.gate, using: &g)
        editTrack { t in t.writeArpSteps(notes, pages: range) }
    }

    /// Случайный ритм ударного движка дорожки (KICK, SNARE, HAT, CLAP, PERC) на выбранные страницы: по длинам
    /// страниц (короткая — своей длиной), нота — корневая в октаве клавиатуры. SETTINGS → RANDOM → STEPS ALL TRACKS —
    /// на все ударные дорожки (каждая — своим движком и стилем, на свои выбранные страницы). Одна запись UNDO.
    func writeRandomDrums() {
        guard channel == .track, track.drumRole != nil else { return }
        let sel: Int = selectedTrack
        let all: Bool = settings.randomStepsAll
        let range: ClosedRange<Int> = chordPages
        var g = SystemRandomNumberGenerator()
        var last: [Int: [Int]] = lastRandomDrums
        let root: Int = project.root
        let octs: [Int] = (0..<project.tracks.count).map { i in i == sel ? octave : octaveOf(i) }
        edit { p in
            for i in p.tracks.indices where (i == sel || all) && p.tracks[i].drumRole != nil {
                let r: ClosedRange<Int> = i == sel ? range : p.tracks[i].openClip.range
                let note: Int = Scales.baseNote(root: root, octave: octs[i])
                let id: Int = p.tracks[i].id
                last[id] = p.tracks[i].writeRandomDrums(pages: r, note: note, avoid: last[id], using: &g)
            }
        }
        lastRandomDrums = last
    }

    /// Октава клавиатуры дорожки i (у каждой своя).
    private func octaveOf(_ i: Int) -> Int {
        guard i >= 0 && i < octaves.count else { return Scales.octaveDef }
        return min(octaves[i], topOctave)
    }
}
