import Foundation

/// Слежение ударных за нотами (14.11, PitchKey): SHIFT + тап по 1.1 KICK, SNARE, HAT, CLAP, PERC — вкл./выкл. (одна
/// запись UNDO); подпись «… Key»; пока звучит нота не C3 — на ручке её частота (как p-lock).
extension AppModel {
    /// Движок выбранной дорожки, если её ручка id — 1.1 ударного.
    func pitchKeyEngine(_ id: String) -> Int? {
        guard id == "harm", let e = SynthKey.engine(track.sample), PitchKey.drum(e) else { return nil }
        return e
    }

    /// SHIFT + тап: вкл./выкл.; false — ручка не из этих.
    func pitchKeyShiftTap(_ id: String) -> Bool {
        if pitchKeyEngine(id) == nil { return false }
        let on: Bool = (track.params[PitchKey.id] ?? 0) < 0.5
        editTrack { t in t.params[PitchKey.id] = on ? 1 : 0 }
        return true
    }

    /// Ручка со слежением вместо p (nil — выключено).
    func pitchKeyDef(_ p: ParamDef) -> ParamDef? {
        guard let e = pitchKeyEngine(p.id), (track.params[PitchKey.id] ?? 0) >= 0.5 else { return nil }
        return PitchKey.drumDefs[e]
    }

    /// Нота на ручке: нажатая клавиша, иначе зажатый шаг, иначе при игре — последний прозвучавший шаг играющих страниц.
    func pitchKeyNote() -> Int? {
        if let n = pressedNotes.min() { return n }
        if let held = heldSteps.min() {
            guard let s = track.step(held), s.on else { return nil }
            return s.notes.min()
        }
        if !playing { return nil }
        let pos = openPlayPos
        if pos < 0 { return nil }
        let t: Track = track
        let lo: Int = t.playFrom * Params.stepsPerPage
        let len: Int = (t.playTo - t.playFrom + 1) * Params.stepsPerPage
        if len <= 0 { return nil }
        var k: Int = 0
        while k < len {
            let i: Int = lo + ((pos - lo - k) % len + len) % len
            if let s = t.step(i), s.on, let n = s.notes.min() { return n }
            k += 1
        }
        return nil
    }

    /// Значение 1.1 для показа (нота не C3) — частота ноты в единицах ручки; nil — показывать как есть.
    func pitchKeyShown(_ p: ParamDef, _ v: Double) -> Double? {
        guard let e = pitchKeyEngine(p.id), (track.params[PitchKey.id] ?? 0) >= 0.5, let n = pitchKeyNote(),
              Double(n) != PitchKey.root else { return nil }
        return PitchKey.knob(e, v / 100, note: Double(n)) * 100
    }
}
