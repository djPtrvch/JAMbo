import Foundation

/// Слежение ударных за нотами (14.11, PitchKey): SHIFT + тап по 1.1 KICK, SNARE, HAT, CLAP, PERC — вкл./выкл. (одна
/// запись UNDO); на ручке — её значение, подпись «… Key».
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
}
