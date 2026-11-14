import Foundation

// Режим XY (на пробу; SETTINGS → MORPH → XY PADS; docs/ai/ui-layout.md, «Режим XY»): вместо страницы ручек дорожки —
// четыре площадки выбранной дорожки; оси X и Y — ручки этой дорожки (Track.xy, двойной тап — меню). Палец двигает
// ручку тем же путём, что поворот (setKnob: p-lock, MORPH, автоматизация, UNDO).

extension AppModel {
    /// Площадки видны: включены, страница дорожки (не MIX, MST, FX, MOD), не MIDI LEARN.
    var xyShown: Bool {
        return settings.xyPads && channel == .track && !fxMode && !modMode && !midiLearn.on
    }

    /// Ручка оси k (0…7) выбранной дорожки; nil — не назначена или ручка пустая.
    func xySlot(_ k: Int) -> Int? {
        guard let s = track.xySlot(k), param(s) != nil else { return nil }
        return s
    }

    /// Положение оси 0…1 — как начало поворота ручки (p-lock зажатого шага, кривая аранжировки, значение).
    func xyNorm(_ k: Int) -> Double? {
        guard let s = xySlot(k) else { return nil }
        return knobStart(s)
    }

    /// С LFO/ENV на ручке оси — итог модуляции (полупрозрачная точка); иначе nil.
    func xyModNorm(_ k: Int) -> Double? {
        guard let s = xySlot(k) else { return nil }
        let st: KnobState = knobState(s)
        return st.assign == nil ? nil : modulatedNorm(st)
    }

    /// Палец на площадке pad: ручки её осей «в руке» (кривая аранжировки не действует), как палец на ручке.
    func xyTouch(_ pad: Int, _ on: Bool) {
        for k in [pad * 2, pad * 2 + 1] {
            if let s = xySlot(k) { knobTouch(s, on) }
        }
    }

    /// Подпись ручки оси k; не назначена — пусто.
    func xyLabel(_ k: Int) -> String {
        guard let s = xySlot(k), let p = param(s) else { return "" }
        return p.label
    }

    /// Назначить ось k выбранной дорожки на ручку slot (nil — снять); UNDO.
    func xyAssign(_ k: Int, slot: Int?) {
        editTrack { t in t.setXYSlot(k, slot) }
    }
}
