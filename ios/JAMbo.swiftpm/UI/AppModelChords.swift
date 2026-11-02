import Foundation

// Режим CHORD: случайная прогрессия (SHIFT + CHORD) — запись аккордов в выбранные страницы открытого паттерна; на
// ударном движке (KICK, SNARE, HAT, CLAP, PERC) — случайный ритм стиля дорожки (DrumRhythm), стили — в окне CHORD.

extension AppModel {
    /// Тап по CHORD: с SHIFT — случайная прогрессия (режим не меняется), иначе — вкл./выкл. режима.
    func chordTap() {
        if shiftHeld {
            if drumTrack {
                writeRandomDrums()
            } else {
                writeRandomProgression()
            }
        } else {
            toggleChord()
        }
    }

    /// Дорожка с ударным движком (KICK, SNARE, HAT, CLAP, PERC): у CHORD — стили ритма вместо типов аккорда.
    var drumTrack: Bool {
        guard channel == .track else { return false }
        return DrumRhythm.role(engine: SynthKey.engine(track.sample)) != nil
    }

    /// Стиль ритма выбранной дорожки (хранится в проекте, одна запись UNDO).
    func setDrumStyle(_ k: Int) {
        let v: Int = DrumRhythm.styleIndex(k)
        editTrack { t in t.drumStyle = v }
    }

    /// Окно и MIDI CHORD TYPE n: на ударной дорожке — стиль, иначе — тип аккорда.
    func chooseChordType(_ k: Int) {
        if drumTrack { setDrumStyle(k) } else { setChordKind(k) }
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

    /// Случайный ритм ударного движка дорожки (KICK, SNARE, HAT, CLAP, PERC) на выбранные страницы: по длинам
    /// страниц (короткая — своей длиной), нота — корневая в октаве клавиатуры. Одна запись UNDO.
    func writeRandomDrums() {
        guard channel == .track, let role = DrumRhythm.role(engine: SynthKey.engine(track.sample)) else { return }
        let range: ClosedRange<Int> = chordPages
        let t: Track = track
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        var g = SystemRandomNumberGenerator()
        let id: Int = t.id
        let pattern: [[DrumRhythm.Hit]] = DrumRhythm.pattern(role, style: t.drumStyle, lens: lens,
                                                             avoid: lastRandomDrums[id], using: &g)
        lastRandomDrums[id] = pattern.first(where: { !$0.isEmpty })?.map { $0.step }
        let note: Int = Scales.baseNote(root: project.root, octave: octave)
        editTrack { tr in tr.writeDrums(pattern, note: note, pages: range) }
    }
}
