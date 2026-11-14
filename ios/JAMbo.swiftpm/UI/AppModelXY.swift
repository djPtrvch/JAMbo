import Foundation

// Режим XY (на пробу; SETTINGS → MORPH → XY PADS; docs/ai/ui-layout.md, «Режим XY»): вместо страницы ручек дорожки —
// четыре площадки, у каждой оси X и Y назначены на ручки (дорожки, FX, MOD, мастера) конкретной дорожки. Палец
// двигает параметры относительно, как ручку; правка — теми же путями (p-lock, MORPH, UNDO).

extension AppModel {
    /// Площадки видны: включены, страница дорожки (не MIX, MST, FX, MOD), не MIDI LEARN, не назначение оси.
    var xyShown: Bool {
        return settings.xyPads && channel == .track && !fxMode && !modMode && xyAssigning == nil && !midiLearn.on
    }

    /// Номер дорожки оси; у мастера дорожка не нужна (выбранная).
    func xyTrackIndex(_ a: XYAxis) -> Int? {
        if let i = project.tracks.firstIndex(where: { $0.id == a.track }) { return i }
        return a.page == 3 ? selectedTrack : nil
    }

    /// Ручка дорожки (страница 0) у выбранной дорожки — как на сетке ручек (поворот через setKnob).
    func xyOwnKnob(_ a: XYAxis, _ i: Int) -> Bool {
        return a.page == 0 && i == selectedTrack
    }

    /// Параметр оси (nil — не назначена, дорожки нет или ручка пустая).
    func xyDef(_ k: Int) -> ParamDef? {
        guard let a = project.xyAxis(k), let i = xyTrackIndex(a), a.slot >= 0, a.slot < 16 else { return nil }
        let t: Track = project.tracks[i]
        switch a.page {
        case 1: return fxParam(a.slot)
        case 2:
            let l: Int = lfoSpeedIndex(a.slot)
            if l >= 0 && (t.params[Params.lfoSyncIds[l]] ?? 0) >= 0.5 { return Params.lfoSpeedSync(l + 1) }
            return Params.modGrid[a.slot]
        case 3: return Params.masterGrid[a.slot]
        default:
            if xyOwnKnob(a, i) && channel == .track && !fxMode && !modMode { return param(a.slot) }
            let p: ParamDef = Params.grid(sound: t.sample)[a.slot]
            if p.id.isEmpty { return nil }
            if p.id == "rate" && (t.params[Params.rateModeId] ?? 0) >= 0.5 { return Params.rateTstr }
            if p.id == "filter" {
                return Params.filterDef(FilterType.effective(FilterType.of(t.params[Params.filterTypeId]), sound: t.sample))
            }
            if let e = SynthKey.engine(t.sample) { return AnalogMod.knob(p, engine: e, params: t.params) }
            return p
        }
    }

    /// Положение оси 0…1: p-lock зажатого шага (у выбранной дорожки и FX), иначе значение.
    func xyNorm(_ k: Int) -> Double? {
        guard let a = project.xyAxis(k), let i = xyTrackIndex(a), let p = xyDef(k) else { return nil }
        if xyOwnKnob(a, i) { return knobStart(a.slot) }
        if a.page == 3 { return p.toNorm(masterValue(p)) }
        if a.page == 1 || i == selectedTrack, let h = heldSteps.min(), let v = track.step(h)?.locks[p.id] {
            return p.toNorm(v)
        }
        if a.page == 1 { return p.toNorm(fxValue(p)) }
        return p.toNorm(project.tracks[i].params[p.id] ?? p.def)
    }

    /// Задать ось: с зажатыми шагами — p-lock (выбранная дорожка, FX), в MORPH — временно, иначе значение (UNDO).
    func xySet(_ k: Int, norm: Double) {
        guard let a = project.xyAxis(k), let i = xyTrackIndex(a), let p = xyDef(k) else { return }
        if xyOwnKnob(a, i) {
            setKnob(a.slot, norm: norm)
            return
        }
        let v: Double = p.fromNorm(min(1, max(0, norm)))
        if a.page == 3 {
            edit { pr in pr.master[p.id] = v }
            return
        }
        let held: Set<Int> = a.page == 1 || i == selectedTrack ? heldSteps : []
        if !held.isEmpty {
            usedSteps.formUnion(held)
            editTrack { t in
                for s in held { t.setLock(s, p.id, v) }
            }
        } else if a.page == 1 {
            setFx(p, v)
        } else if morph {
            editMorph { pr in
                pr.tracks[i].morphParam(p.id)
                pr.tracks[i].params[p.id] = v
            }
        } else {
            edit { pr in pr.tracks[i].params[p.id] = v }
        }
    }

    /// Палец на площадке pad: ручка выбранной дорожки — «рука» вместо кривой аранжировки (как палец на ручке).
    func xyTouch(_ pad: Int, _ on: Bool) {
        for k in [pad * 2, pad * 2 + 1] {
            guard let a = project.xyAxis(k), let i = xyTrackIndex(a), xyOwnKnob(a, i) else { continue }
            knobTouch(a.slot, on)
        }
    }

    /// Подпись оси: «имя дорожки · подпись ручки» (у мастера — MST); не назначена — X или Y.
    func xyLabel(_ k: Int) -> String {
        let axis: String = k % 2 == 0 ? "X" : "Y"
        guard let a = project.xyAxis(k), let i = xyTrackIndex(a), let p = xyDef(k) else { return axis }
        let who: String = a.page == 3 ? "MST" : project.tracks[i].name
        return axis + "  " + who + " · " + p.label
    }

    // MARK: — назначение (держат подпись оси и вращают ручку)

    /// Страница, которую сейчас показывают ручки: 0 — дорожка, 1 — FX, 2 — MOD, 3 — мастер; nil — MIX.
    var xyPage: Int? {
        switch channel {
        case .mix: return nil
        case .master: return 3
        case .track: return fxMode ? 1 : (modMode ? 2 : 0)
        }
    }

    /// Начало вращения при назначении: та же ручка — её степень, иначе 0.
    func xyAssignStart(_ k: Int, slot: Int) -> Double {
        guard let a = project.xyAxis(k), a.slot == slot, a.page == xyPage, a.track == track.id else { return 0 }
        return a.amount
    }

    /// Вращение ручки slot при удержанной подписи оси k: ось — на эту ручку выбранной дорожки, степень −1…+1.
    func xyAssign(_ k: Int, slot: Int, amount: Double) {
        guard let page = xyPage, param(slot) != nil else { return }
        let a = XYAxis(track: track.id, page: page, slot: slot, amount: amount)
        edit { pr in pr.setXYAxis(k, a) }
    }

    /// Двойной тап по ручке при удержанной подписи — снять назначение оси.
    func xyClear(_ k: Int) {
        edit { pr in pr.setXYAxis(k, nil) }
    }
}

extension AppModel {
    /// Положение оси с LFO/ENV (ручка дорожки выбранной дорожки с назначенным источником) — полупрозрачная точка.
    func xyModNorm(_ k: Int) -> Double? {
        guard let a = project.xyAxis(k), let i = xyTrackIndex(a), xyOwnKnob(a, i) else { return nil }
        let st: KnobState = knobState(a.slot)
        return st.assign == nil ? nil : modulatedNorm(st)
    }
}
