import Foundation

// Режим CHORD: пресеты прогрессий и случайная прогрессия (SHIFT + CHORD) — запись аккордов в открытый паттерн.

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

    /// Аккорды пресета для текущей гаммы и корня (строка окна CHORD).
    func progressionNames(_ p: ChordProgression) -> String {
        return Chords.names(p.degrees, scale: project.scale, root: project.root, kind: chordKind[selectedTrack])
    }

    /// Страница секвенсора, на которую пишутся аккорды (открытая; при нескольких на экране — выбранная).
    private var chordPage: Int {
        return max(0, min(viewPage, track.pages.count - 1))
    }

    /// Пресет или случайная прогрессия: 4 аккорда текущего типа на шаги 1, 5, 9, 13 текущей страницы, по 4 шага;
    /// ноты — конкретные (от гаммы, корня и октавы клавиатуры сейчас). Остальные шаги не трогаются. Одна запись UNDO.
    func writeProgression(_ degrees: [Int]) {
        guard channel == .track else { return }
        let cs: [[Int]] = Chords.chords(degrees, scale: project.scale, root: project.root, octave: octave,
                                        kind: chordKind[selectedTrack])
        let base: Int = chordPage * Params.stepsPerPage
        editTrack { t in
            for (i, notes) in cs.enumerated() where i < Chords.slots.count {
                t.withStep(base + Chords.slots[i]) { s in
                    s.on = true
                    s.notes = notes
                    s.lens = nil
                    s.vels = nil
                    s.setAllLen(Chords.slotLen)
                }
            }
        }
    }

    func writeRandomProgression() {
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = Chords.random(scale: project.scale, avoid: lastRandomProgression, using: &g)
        lastRandomProgression = degrees
        writeProgression(degrees)
    }

    /// Clear chords: аккорды (шаги с несколькими нотами) на шагах 1, 5, 9, 13 текущей страницы снимаются. Одна запись UNDO.
    func clearProgression() {
        guard channel == .track else { return }
        let base: Int = chordPage * Params.stepsPerPage
        let t0: Track = track
        let any: Bool = Chords.slots.contains { (t0.step(base + $0)?.notes.count ?? 0) > 1 }
        if !any { return }
        editTrack { t in
            for slot in Chords.slots {
                t.withStep(base + slot) { s in
                    if s.notes.count > 1 { s = Step() }
                }
            }
        }
    }
}
