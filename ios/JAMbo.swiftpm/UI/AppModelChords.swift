import Foundation

// Режим CHORD: случайная прогрессия (SHIFT + CHORD) — запись аккордов в выбранные страницы открытого паттерна; на
// ударном движке (KICK, SNARE, HAT, CLAP, PERC) — случайный ритм стиля дорожки (DrumRhythm), на нарезанном сэмпле
// (SETTINGS → RANDOM → SAMPLES) — случайный рисунок кусков (SliceRhythm); стили — в окне CHORD.

extension AppModel {
    /// Тап по CHORD: с SHIFT — случайная прогрессия (режим не меняется), иначе — вкл./выкл. режима.
    func chordTap() {
        if shiftHeld {
            // SETTINGS → RANDOM: выключенный DRUMS или CHORDS — ничего.
            if drumTrack {
                if settings.randomDrums { writeRandomDrums() }
            } else if sliceTrack {
                writeRandomSlices()
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

    /// Дорожка с нарезанным сэмплом при SETTINGS → RANDOM → SAMPLES: у CHORD — RANDOM и стили, как у ударной.
    var sliceTrack: Bool {
        guard channel == .track, settings.randomSamples else { return false }
        return track.drumRole == nil && track.sliced
    }

    /// У кнопки CHORD — стили вместо типов аккорда (ударная или нарезанная дорожка; в режиме ARP — направления).
    var styleTrack: Bool { return drumTrack || sliceTrack }

    /// Слово на кнопке CHORD: ARP — в режиме ARP; RANDOM — на ударной (при DRUMS) и нарезанной дорожке.
    var chordWord: String {
        if arpMode { return "ARP" }
        if (drumTrack && settings.randomDrums) || sliceTrack { return "RANDOM" }
        return "CHORD"
    }

    /// Стиль ритма выбранной дорожки (хранится в проекте, одна запись UNDO).
    /// SETTINGS → RANDOM → STYLE ALL TRACKS — всем ударным и нарезанным дорожкам проекта.
    func setDrumStyle(_ k: Int) {
        let v: Int = DrumRhythm.styleIndex(k)
        if settings.randomStyleAll {
            let sl: Bool = settings.randomSamples
            edit { p in
                for i in p.tracks.indices where p.tracks[i].drumRole != nil || (sl && p.tracks[i].sliced) {
                    p.tracks[i].drumStyle = v
                }
            }
        } else {
            editTrack { t in t.drumStyle = v }
        }
    }

    /// Окно и MIDI CHORD TYPE n: на ударной дорожке — стиль, в режиме ARP — направление, иначе — тип аккорда.
    func chooseChordType(_ k: Int) {
        if arpMode {
            setArpDir(k)
        } else if styleTrack {
            setDrumStyle(k)
        } else {
            setChordKind(k)
        }
    }

    /// Подписи окна CHORD и под словом на кнопке: стили, направления арпеджио или типы аккорда.
    var chordTypeNames: [String] {
        if arpMode { return Arp.dirs }
        return styleTrack ? DrumRhythm.styles : Scales.chordKinds
    }

    /// Номер выбранного типа (на ударной дорожке — стиля, в ARP — направления).
    var chordTypeIndex: Int {
        if arpMode { return track.arp.dir }
        return styleTrack ? track.drumStyle : chordKind[selectedTrack]
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

    /// Случайный рисунок нарезанного сэмпла выбранной дорожки на выбранные страницы (SliceRhythm): куски —
    /// от маркера до следующего, длина в шагах по темпу (с WARP — по долям карты), ноты — как у маркеров.
    /// Одна запись UNDO; рисунок не повторяет прошлый рисунок дорожки.
    func writeRandomSlices() {
        guard sliceTrack else { return }
        let key: String = track.sample
        guard let d = sample(key) else { return }
        let pieces: [SliceRhythm.Piece] = slicePieces(key, d)
        if pieces.isEmpty { return }
        let range: ClosedRange<Int> = chordPages
        let id: Int = track.id
        var g = SystemRandomNumberGenerator()
        let avoid: [Int]? = lastRandomDrums[-1 - id]
        var code: [Int]? = nil
        editTrack { t in code = t.writeRandomSlices(pieces, pages: range, avoid: avoid, using: &g) }
        lastRandomDrums[-1 - id] = code
    }

    /// Куски нарезки сэмпла key дорожки: нота маркера, длина в шагах (до следующего маркера, последний — до конца),
    /// роль. С включённым WARP — по долям карты меток, иначе — по времени в темпе проекта.
    private func slicePieces(_ key: String, _ d: SampleData) -> [SliceRhythm.Piece] {
        let marks: [SliceMark] = track.sliceMarks(key)
        let notes: [Int] = Slices.notes(marks, map: settings.sliceMap, scale: project.scale, root: project.root,
                                        octave: octave)
        let info: WarpInfo? = track.warps[key]
        let frames: Double = Double(max(1, d.frames))
        var warp: WarpMap? = nil
        if let i = info, !i.isEmpty, !i.isOff {
            warp = WarpMap(i, frames: d.frames, bpm: WarpMap.bpm(i, detected: d.loopBpm))
        }
        let stepSec: Double = 15 / max(1, project.bpm)
        var out: [SliceRhythm.Piece] = []
        for (k, m) in marks.enumerated() where k < notes.count {
            let end: Double = k + 1 < marks.count ? marks[k + 1].at : 1
            var len: Double = (end - m.at) * d.duration / stepSec
            if let w = warp { len = (w.beat(end * frames) - w.beat(m.at * frames)) * 4 }
            out.append(SliceRhythm.Piece(note: notes[k], len: max(0, len), role: SliceRhythm.role(m.role)))
        }
        return out
    }

    /// Октава клавиатуры дорожки i (у каждой своя).
    private func octaveOf(_ i: Int) -> Int {
        guard i >= 0 && i < octaves.count else { return Scales.octaveDef }
        return min(octaves[i], topOctave)
    }
}
