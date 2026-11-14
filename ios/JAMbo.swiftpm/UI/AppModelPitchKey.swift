import Foundation

/// Pitch по нотам (14.11, PitchKey): SHIFT + тап по Pitch сэмпла или 1.1 ударного (KICK, SNARE, HAT, CLAP, PERC) —
/// режим вкл./выкл. (одна запись UNDO); ручка — сдвиг нотой, по полутонам; нота зажатого или последнего прозвучавшего
/// шага — на ручке, как p-lock.
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
            // Включение: у ударного сдвиг 0 (шаг звучит своей нотой), у сэмпла — Pitch на ближайшем полутоне.
            if on && e != nil { t.params[id] = 50 }
            if on && e == nil, let v = t.params[id] { t.params[id] = PitchKey.snapped(e, v) }
        }
        return true
    }

    /// Ручка по нотам вместо p (nil — без режима).
    func pitchKeyDef(_ p: ParamDef) -> ParamDef? {
        if !pitchKeyOn(p.id) { return nil }
        guard let e = pitchKeyEngine(p.id).engine else { return PitchKey.sampleDef }
        return PitchKey.drumDefs[e]
    }

    /// Нота зажатого (иначе играющего) шага — любая, и C3; nil — нет или режим выключен.
    func pitchKeyNote(_ id: String) -> Int? {
        if !pitchKeyOn(id) { return nil }
        if let held = heldSteps.min() {
            guard let s = track.step(held), s.on, let n = s.notes.min() else { return nil }
            return n
        }
        if !playing { return nil }
        let pos = openPlayPos
        if pos < 0 { return nil }
        // При игре — нота последнего прозвучавшего шага играющих страниц (держится до следующей ноты).
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
}

extension AppModel {
    /// Значение ручки с нотой шага (как на ручке): Pitch шага (p-lock или ручка дорожки) + нота.
    func pitchKeyShown(_ p: ParamDef, step i: Int) -> Double? {
        guard pitchKeyOn(p.id), let s = track.step(i), let n = s.notes.min() else { return nil }
        let b: Double = s.locks[p.id] ?? track.params[p.id] ?? p.def
        return PitchKey.shifted(pitchKeyEngine(p.id).engine, b, note: n)
    }

    /// Поворот на зажатых шагах — как p-lock (решение пользователя): меняется нота шага (аккорд — целиком), чтобы на
    /// ручке встало значение v; шаг без ноты получает её. false — режим выключен (обычный p-lock).
    func pitchKeySetSteps(_ id: String, _ v: Double, _ held: [Int]) -> Bool {
        if !pitchKeyOn(id) { return false }
        let e: Int? = pitchKeyEngine(id).engine
        let def: Double = track.params[id] ?? Params.byId[id]?.def ?? 0
        usedSteps.formUnion(held)
        editTrack { t in
            for i in held {
                t.withStep(i) { s in
                    let b: Double = s.locks[id] ?? def
                    let want: Double = PitchKey.semis(e, v) - PitchKey.semis(e, b)
                    let target: Int = Params.sampleRoot + Int(want)
                    let from: Int = s.notes.min() ?? Params.sampleRoot
                    let d: Int = target - from
                    if s.notes.isEmpty {
                        s.notes = [Swift.max(0, Swift.min(127, target))]
                    } else if d != 0 {
                        s.notes = s.notes.map { Swift.max(0, Swift.min(127, $0 + d)) }
                    }
                }
            }
        }
        return true
    }
}
