import Foundation

// MOD (удержание MOD): ручки LFO1–3 и ENV выбранной дорожки. Назначение: удерживать LFO1–3 или ENV и вращать ручку
// дорожки или FX — степень −100…+100 % (от нуля в обе стороны); на ручку — один источник; снять — удерживать ту же
// кнопку и дважды тапнуть по ручке. Кольцо модуляции на ручке — от значения до текущего (LFO1–3 — своя прозрачность,
// ENV — пунктир); пока держат источник — видна вся зона воздействия и степень на ручке.

extension AppModel {
    /// Ручки показывают MOD: зажата MOD на дорожке (из FX и MOD — нажатая последней).
    var modMode: Bool { return modHeld && channel == .track && (!fxHeld || lastPage == .mod) }

    /// Окно сэмпла показывает миниатюры LFO/ENV: держат MOD или 1,5 с после поворота ручки MOD.
    var modPreview: Bool { return modMode || Date() < modPreviewUntil }

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
            editTrack { t in t.assigns[p.id] = ModAssign(lfo: lfo, amount: a) }
        }
    }

    /// Снять назначение источника lfo с ручки slot (двойной тап с зажатым источником).
    func clearAssign(_ slot: Int, lfo: Int) {
        guard canAssign, let p = param(slot) else { return }
        if fxMode {
            if project.fxAssigns[p.id]?.lfo == lfo { edit { pr in pr.fxAssigns[p.id] = nil } }
        } else if track.assigns[p.id]?.lfo == lfo {
            editTrack { t in t.assigns[p.id] = nil }
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
