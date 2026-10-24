import Foundation

// MOD (удержание MOD): ручки LFO1–3 и ENV выбранной дорожки. Назначение: удерживать LFO1–3 или ENV и вращать ручку
// дорожки или FX — степень −100…+100 % (от нуля в обе стороны); на ручку — один источник; снять — удерживать ту же
// кнопку и дважды тапнуть по ручке. Кольцо модуляции на ручке — от значения до текущего (LFO1–3 — своя прозрачность,
// ENV — пунктир); пока держат источник — видна вся зона воздействия и степень на ручке.

extension AppModel {
    /// Ручки показывают MOD: зажата MOD на дорожке (из FX и MOD — нажатая последней).
    var modMode: Bool { return modHeld && channel == .track && (!fxHeld || lastPage == .mod) }

    /// Окно сэмпла показывает миниатюры LFO/ENV, пока держат MOD (решение пользователя: отпустили — сразу гаснут;
    /// в вебе — ещё 1,5 с после поворота ручки MOD).
    var modPreview: Bool { return modMode }

    /// Удерживаемый источник (1–3 — LFO, 4 — ENV): нажатый последним из зажатых.
    var heldSource: Int? {
        if heldSources.contains(lastSource) { return lastSource }
        return heldSources.min()
    }

    func setSource(_ s: Int, held on: Bool) {
        if on {
            heldSources.insert(s)
            lastSource = s
            sourceTapped(s)
        } else {
            heldSources.remove(s)
        }
    }

    /// Палец держит ручку с назначением: тап по другому источнику — назначение переходит к нему с той же степенью,
    /// двойной тап по назначенному источнику — назначение снимается.
    private func sourceTapped(_ s: Int) {
        let now = Date()
        let double: Bool = lastSourceTap.map { $0.source == s && now.timeIntervalSince($0.at) < 0.35 } ?? false
        lastSourceTap = double ? nil : (s, now)
        for slot in knobFingers {
            guard let a = assign(slot) else { continue }
            if a.lfo != s {
                setAssign(slot, lfo: s, amount: a.amount)
            } else if double {
                clearAssign(slot, lfo: s)
            }
        }
    }

    func setPageHeld(_ page: GridPage, _ on: Bool) {
        if page == .fx { fxHeld = on } else { modHeld = on }
        if on { lastPage = page }
    }

    func pageOn(_ page: GridPage) -> Bool { return page == .fx ? fxHeld : modHeld }

    func latched(_ page: GridPage) -> Bool { return page == .fx ? settings.latchFx : settings.latchMod }

    /// Нажатие FX или MOD. SHIFT + двойной тап — режим toggle кнопки (и обратно); в режиме toggle тап включает
    /// страницу, следующий — выключает, включённая toggle-кнопка выключает другую; иначе — удержание.
    func pagePress(_ page: GridPage) {
        if shiftHeld {
            let now = Date()
            if let l = lastPageTap, l.page == page, now.timeIntervalSince(l.at) < 0.35 {
                lastPageTap = nil
                let on = !latched(page)
                updateSettings { s in
                    if page == .fx { s.latchFx = on } else { s.latchMod = on }
                }
                if !on { setPageHeld(page, false) }
            } else {
                lastPageTap = (page, now)
            }
            return
        }
        if latched(page) {
            let on = !pageOn(page)
            setPageHeld(page, on)
            let other: GridPage = page == .fx ? .mod : .fx
            if on && latched(other) && pageOn(other) { setPageHeld(other, false) }
            return
        }
        setPageHeld(page, true)
    }

    func pageRelease(_ page: GridPage) {
        if !latched(page) { setPageHeld(page, false) }
    }

    // MARK: — MORPH

    /// MORPH: тап включает режим; повторный — выключает и возвращает всё, что меняли, на всех дорожках: сразу или
    /// плавно (SETTINGS → MORPH → RETURN, по темпу). Включили снова во время возврата — ручки остаются, где были.
    func toggleMorph() {
        if morph {
            let sec: Double = MorphReturn.seconds(settings.morphReturn, bpm: project.bpm)
            let pts: [MorphPoint] = project.morphReturnPoints()
            if sec > 0 && !pts.isEmpty {
                morphGlide = MorphGlide(points: pts, start: Date.timeIntervalSinceReferenceDate, seconds: sec,
                                        before: project)
            } else {
                undoMorphEdits()
            }
        } else {
            stopMorphGlide()
        }
        morph.toggle()
    }

    /// Шаг возврата (60 раз в секунду): ручки — к исходным; в конце — всё, что меняли (и назначения), одной записью UNDO.
    func stepMorphGlide() {
        guard let g = morphGlide else { return }
        let f: Double = (Date.timeIntervalSinceReferenceDate - g.start) / g.seconds
        if f < 1 {
            mutatePlay({ p in p.applyMorphReturn(g.points, f) }, publish: true)
            return
        }
        morphGlide = nil
        mutatePlay({ p in
            for i in p.tracks.indices where p.tracks[i].morphEdited { p.tracks[i].undoMorph() }
        }, publish: false)
        history.record(before: g.before, after: project)
        changed()
    }

    /// Возврат прерван (MORPH снова включили, UNDO): ручки остаются, где были; пройденное — одна запись UNDO.
    func stopMorphGlide() {
        guard let g = morphGlide else { return }
        morphGlide = nil
        history.record(before: g.before, after: project)
        changed()
    }

    /// Вернуть изменения режима MORPH на всех дорожках (одна запись в UNDO).
    func undoMorphEdits() {
        stopMorphGlide()
        edit { p in
            for i in p.tracks.indices where p.tracks[i].morphEdited { p.tracks[i].undoMorph() }
        }
    }

    /// Нажатие MORPH. SHIFT + двойной тап — MORPH ALL TRACKS вкл./выкл. (как SETTINGS → MORPH → ALL TRACKS; решение
    /// пользователя), сам режим MORPH при этом не переключается.
    func morphPress() {
        morphHeld = true
        morphUsed = false
        guard shiftHeld else { return }
        morphUsed = true
        let now = Date()
        if let l = lastMorphShiftTap, now.timeIntervalSince(l) < 0.35 {
            lastMorphShiftTap = nil
            setMorphAll(!settings.morphAll)
        } else {
            lastMorphShiftTap = now
        }
    }

    func morphRelease() {
        morphHeld = false
        if !morphUsed { toggleMorph() }
    }

    /// UNDO: с зажатой MORPH — сбросить изменения режима MORPH (режим не переключается), иначе — обычная отмена.
    func undoTapped() {
        if morphHeld {
            morphUsed = true
            undoMorphEdits()
        } else {
            stopMorphGlide()
            undo()
        }
    }

    /// Назначения ставятся на ручки дорожки и FX (не на MOD, MIX, MST).
    var canAssign: Bool { return channel == .track && !modMode }

    /// Назначение на ручку slot в текущем режиме.
    func assign(_ slot: Int) -> ModAssign? {
        guard canAssign, let p = param(slot) else { return nil }
        return fxMode ? project.fxAssigns[p.id] : track.assigns[p.id]
    }

    /// Степень источника lfo на ручке slot (−1…+1): назначение — на всю ручку, источник один.
    func setAssign(_ slot: Int, lfo: Int, amount: Double) {
        guard canAssign, let p = param(slot) else { return }
        let a = Swift.min(1, Swift.max(-1, amount))
        if fxMode {
            let t = selectedTrack
            edit { pr in pr.fxAssigns[p.id] = ModAssign(lfo: lfo, amount: a, track: t) }
        } else {
            let m = morph
            editTrack { t in
                if m { t.morphAssign(p.id) }
                t.assigns[p.id] = ModAssign(lfo: lfo, amount: a)
            }
        }
    }

    /// Снять назначение источника lfo с ручки slot (двойной тап с зажатым источником).
    func clearAssign(_ slot: Int, lfo: Int) {
        guard canAssign, let p = param(slot) else { return }
        if fxMode {
            if project.fxAssigns[p.id]?.lfo == lfo { edit { pr in pr.fxAssigns[p.id] = nil } }
        } else if track.assigns[p.id]?.lfo == lfo {
            let m = morph
            editTrack { t in
                if m { t.morphAssign(p.id) }
                t.assigns[p.id] = nil
            }
        }
    }

    /// Выход источника lfo дорожки t (LFO −1…+1, ENV 0…1) — из колбэка, на начало последнего блока.
    func modSource(_ t: Int, _ lfo: Int) -> Double {
        let outs = audio.core.mod.outs
        let i = t * 4 + Swift.max(0, Swift.min(3, lfo - 1))
        return i < outs.count ? Double(outs[i].load()) : 0
    }

    /// Положение ручки с модуляцией (0…1) — для кольца и стрелки.
    func modulatedNorm(_ state: KnobState) -> Double {
        guard let a = state.assign else { return state.norm }
        let t: Int = a.track ?? selectedTrack
        return Swift.min(1, Swift.max(0, state.norm + a.amount * modSource(t, a.lfo)))
    }

    /// Источники, назначенные на ручки, которые сейчас держит палец (обводка их кнопок).
    var fingerSources: Set<Int> {
        var out = Set<Int>()
        for s in knobFingers {
            if let a = assign(s) { out.insert(a.lfo) }
        }
        return out
    }
}

/// Страница ручек по удержанию: FX или MOD.
enum GridPage {
    case fx
    case mod
}

/// Плавный возврат MORPH: точки, начало (с, системное время), длительность, проект до возврата (для UNDO).
struct MorphGlide {
    let points: [MorphPoint]
    let start: Double
    let seconds: Double
    let before: Project
}
