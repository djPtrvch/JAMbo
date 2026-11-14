import Foundation

// Pitch по нотам у ударных (14.11, решение пользователя — простой вариант): SHIFT + тап по 1.1 KICK, SNARE, HAT, CLAP,
// PERC — слежение за нотами вкл./выкл. (значение звука Params.stepModeId("pitch")). Включено: C3 звучит на высоте
// ручки, другие ноты (шаги, клавиатура, MIDI) — на столько же полутонов выше или ниже (HAT — TUNE, CLAP — TONE);
// на ручке — её собственное значение (подпись «… Key»). Выключено — нота высоту не меняет (как прежде).

public enum PitchKey {
    public static let id: String = Params.stepModeId("pitch")
    /// Нота, на которой звучит высота ручки (как C3 у сэмпла).
    public static let root: Double = Double(Params.sampleRoot)

    /// Движок со слежением за нотами (ручка 1.1).
    @inline(__always) public static func drum(_ e: Int) -> Bool {
        return e == Jambo.drum || e == Jambo.snare || e == Jambo.hat || e == Jambo.clap || e == Jambo.perc
    }

    /// Пределы частоты 1.1 (Гц, логарифмически по ходу); у HAT — 0 (TUNE ±1 октава), у CLAP — своя кривая.
    @inline(__always) static func range(_ e: Int) -> (lo: Double, hi: Double) {
        if e == Jambo.drum { return (Jambo.drumPitchMin, Jambo.drumPitchMax) }
        if e == Jambo.snare { return (120, 400) }
        if e == Jambo.perc { return (60, 2000) }
        if e == Jambo.clap { return (700, 3000) }
        return (0, 0)
    }

    /// Колбэк: положение 1.1 (n — значение / 100) для ноты note — частота ручки · 2^((note − C3)/12); за краями хода —
    /// продолжение шкалы (у CLAP — в пределах хода).
    @inline(__always) public static func knob(_ e: Int, _ n: Double, note: Double) -> Double {
        let k: Double = note - root
        if k == 0 { return n }
        let r = range(e)
        if r.lo <= 0 { return Swift.max(-1, Swift.min(2, n + k / 24)) }
        let span: Double = log(r.hi / r.lo)
        if e == Jambo.clap {
            // TONE = 700 · (3000/700)^(n^1,69).
            let x0: Double = pow(Swift.max(0, Swift.min(1, n)), 1.69)
            let x: Double = x0 + k * log(2) / 12 / span
            return pow(Swift.max(0, Swift.min(1, x)), 1 / 1.69)
        }
        let v: Double = n + k * log(2) / 12 / span
        return Swift.max(-1, Swift.min(2, v))
    }

    /// 1.1 ударного со слежением за нотами: значение — как без него, подпись «… Key».
    public static let drumDefs: [Int: ParamDef] = {
        var out: [Int: ParamDef] = [:]
        for e in [Jambo.drum, Jambo.snare, Jambo.hat, Jambo.clap, Jambo.perc] {
            guard e < Params.synthGrids.count, let p = Params.synthGrids[e].first else { continue }
            out[e] = ParamDef(id: p.id, label: p.label + " Key", min: p.min, max: p.max, def: p.def, format: p.format)
        }
        return out
    }()
}
