import Foundation

// Режим CHORD: случайная прогрессия (SHIFT + CHORD) — запись аккордов в выбранные страницы открытого паттерна.

extension AppModel {
    /// Тап по CHORD: с SHIFT — случайная прогрессия (режим не меняется), иначе — вкл./выкл. режима.
    func chordTap() {
        if shiftHeld {
            writeRandomProgression()
        } else {
            toggleChord()
        }
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
}
