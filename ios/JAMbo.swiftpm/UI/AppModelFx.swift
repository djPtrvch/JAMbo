import Foundation

// Страница FX (удержание кнопки FX): ручки общих эффектов — Reverb, Delay, Drive, Duck (сетка FX).
// Значения принадлежат клипу-лидеру (как гамма и нота); с зажатым шагом — p-lock FX на шаге (меняет FX на время шага).

extension AppModel {
    /// Ручки показывают FX: зажата FX на дорожке.
    var fxMode: Bool { return fxHeld && channel == .track && (!modHeld || lastPage == .fx) }

    /// Параметр ручки FX; SC Source — только среди существующих дорожек, подписи — имена дорожек.
    func fxParam(_ slot: Int) -> ParamDef {
        let p = Params.fxGrid[slot]
        if p.id == "dly.time" && !delaySynced { return Params.dlyTimeFree }
        if p.id != "sc.source" { return p }
        let names: [String] = project.tracks.map { $0.name }
        return ParamDef(id: p.id, label: p.label, kind: .stepped, min: 0, max: Double(max(0, names.count - 1)), def: 0,
                        options: names) { v in
            let i = Int(v.rounded())
            return i >= 0 && i < names.count ? names[i] : ""
        }
    }

    // MARK: — картинка FX в окне сэмпла (FxPreview)

    /// Картинка видна: на дорожке палец на ручке FX или ручку FX только что повернули с MIDI (SETTINGS → APPEARANCE →
    /// FX ANIMATION включён).
    var fxPicture: Bool {
        return settings.fxPictures && channel == .track && (fxMidiShow || (fxMode && !knobFingers.isEmpty))
    }

    /// Палец (или нажатие энкодера) на ручке FX — картинка её колонки.
    func fxFinger(_ slot: Int) {
        if fxMode { fxPicCol = slot % 4 }
    }

    /// Поворот ручки FX с MIDI: картинка колонки, гаснет через 0,5 с после последнего поворота.
    func fxMidiPulse(_ slot: Int) {
        fxPicCol = slot % 4
        fxMidiShow = true
        fxMidiTask?.cancel()
        fxMidiTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            self?.fxMidiShow = false
        }
    }

    /// Значение FX на картинке — как на ручке: p-lock зажатого шага, иначе FX клипа.
    func fxShown(_ id: String) -> Double {
        if let held = heldSteps.min(), let v = track.step(held)?.locks[id] { return v }
        return project.fx[id] ?? Params.byId[id]?.def ?? 0
    }

    /// Значение FX клипа (без p-lock).
    func fxValue(_ p: ParamDef) -> Double {
        return project.fx[p.id] ?? p.def
    }

    /// Поворот ручки FX без зажатого шага: значение — в проект и в клип лидера.
    func setFx(_ p: ParamDef, _ v: Double) {
        edit { pr in
            pr.fx[p.id] = v
            writeLead(&pr)
        }
    }

    // MARK: — по темпу: SHIFT + тап по Dly Time и по Speed LFO

    /// Время Delay по темпу (Dly Sync; по умолчанию — да).
    var delaySynced: Bool {
        return (project.fx["dly.sync"] ?? 1) >= 0.5
    }

    /// LFOn (0…2) выбранной дорожки по темпу.
    func lfoSynced(_ l: Int) -> Bool {
        return (track.params[Params.lfoSyncIds[l]] ?? 0) >= 0.5
    }

    /// Параметр ручки MOD: Speed LFO по темпу — подпись пунктом (1/4, 1 bar…).
    func modParam(_ slot: Int) -> ParamDef {
        let p: ParamDef = Params.modGrid[slot]
        // Speed — второй ряд, столбцы LFO1–3 (ячейки 4…6).
        let l: Int = slot - 4
        if l >= 0 && l < 3 && lfoSynced(l) { return Params.lfoSpeedSync(l + 1) }
        return p
    }

    /// SHIFT + тап по ручке: Dly Time и Speed LFO — по темпу или свободно; true — тап обработан.
    @discardableResult
    func knobShiftTap(_ slot: Int) -> Bool {
        guard channel == .track else { return false }
        if modMode {
            let l: Int = slot - 4
            guard l >= 0 && l < 3 else { return false }
            let id: String = Params.lfoSyncIds[l]
            let on: Bool = !lfoSynced(l)
            editTrack { t in t.params[id] = on ? 1 : 0 }
            return true
        }
        guard fxMode, Params.fxGrid[slot].id == "dly.time" else { return false }
        // Время сохраняется: по темпу — ближайший пункт, свободно — те же мс.
        let v: Double = fxValue(fxParam(slot))
        let bpm: Double = project.bpm
        let toSync: Bool = !delaySynced
        let nv: Double
        if toSync {
            nv = Double(Params.nearestDelayDiv(ms: Params.dlyFreeMs(v), bpm: bpm))
        } else {
            let k: Int = min(Params.delayDivs.count - 1, max(0, Int(v.rounded())))
            nv = Params.dlyFreeValue(ms: Params.delayDivs[k].beats * 60000 / max(1, bpm))
        }
        edit { pr in
            pr.fx["dly.sync"] = toSync ? 1 : 0
            pr.fx["dly.time"] = nv
            writeLead(&pr)
        }
        return true
    }
}
