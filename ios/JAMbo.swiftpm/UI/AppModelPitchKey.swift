import Foundation

/// Pitch по нотам (14.11, PitchKey): SHIFT + тап по Pitch сэмпла или 1.1 ударного (KICK, SNARE, HAT, PERC) — режим
/// вкл./выкл. (одна запись UNDO); ручка — нота, по полутонам; нота зажатого или играющего шага — на ручке, как p-lock.
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

    /// Нота зажатого (иначе играющего) шага — любая, и C3; nil — нет или режим выключен.
    func pitchKeyNote(_ id: String) -> Int? {
        if !pitchKeyOn(id) { return nil }
        var step: Step? = nil
        if let held = heldSteps.min() {
            step = track.step(held)
        } else if playing {
            let pos = openPlayPos
            if pos >= 0 { step = track.step(pos) }
        }
        guard let s = step, s.on, let n = s.notes.min() else { return nil }
        return n
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
                    var want: Double = v.rounded() - b.rounded()
                    if let eng = e {
                        let to: Double = PitchKey.base(eng, v / 100)
                        let at: Double = PitchKey.base(eng, b / 100)
                        want = to - at
                    }
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
