import Foundation

/// Pitch по нотам (14.11, PitchKey): SHIFT + тап по Pitch сэмпла или 1.1 ударного (KICK, SNARE, HAT, PERC) — режим
/// вкл./выкл. (одна запись UNDO); ручка — нота, по полутонам; нота зажатого или играющего шага (не C3) — на ручке, как p-lock.
extension AppModel {
    /// Ручка id выбранной дорожки умеет Pitch по нотам; движок — у ударного, nil — у сэмпла.
    func pitchKeyEngine(_ id: String) -> (ok: Bool, engine: Int?) {
        if let e = SynthKey.engine(track.sample) {
            return (id == "harm" && PitchKey.drum(e), e)
        }
        return (id == "pitch", nil)
    }

    /// Режим включён у ручки id.
    func pitchKeyOn(_ id: String) -> Bool {
        return pitchKeyEngine(id).ok && (track.params[PitchKey.id] ?? 0) >= 0.5
    }

    /// SHIFT + тап: вкл./выкл.; включение ставит ручку на ближайшую ноту. false — ручка не из этих.
    func pitchKeyShiftTap(_ id: String) -> Bool {
        let k = pitchKeyEngine(id)
        if !k.ok { return false }
        let on: Bool = !pitchKeyOn(id)
        let e: Int? = k.engine
        editTrack { t in
            t.params[PitchKey.id] = on ? 1 : 0
            if on, let v = t.params[id] { t.params[id] = PitchKey.snapped(e, v) }
        }
        return true
    }

    /// Ручка по нотам вместо p (nil — без режима).
    func pitchKeyDef(_ p: ParamDef) -> ParamDef? {
        if !pitchKeyOn(p.id) { return nil }
        guard let e = pitchKeyEngine(p.id).engine else { return PitchKey.sampleDef }
        return PitchKey.drumDefs[e]
    }

    /// Нота зажатого (иначе играющего) шага, если она не C3; nil — нет или режим выключен.
    func pitchKeyNote(_ id: String) -> Int? {
        if !pitchKeyOn(id) { return nil }
        var step: Step? = nil
        if let held = heldSteps.min() {
            step = track.step(held)
        } else if playing {
            let pos = openPlayPos
            if pos >= 0 { step = track.step(pos) }
        }
        guard let s = step, s.on, let n = s.notes.min(), n != Params.sampleRoot else { return nil }
        return n
    }
}
