import Foundation

// Pitch по нотам (14.11, решение пользователя): SHIFT + тап по Pitch — у ударных KICK, SNARE, HAT, PERC (ручка 1.1)
// и у сэмпла. Значение звука Params.stepModeId("pitch") (pitch.step; у сэмпла — тот же переключатель ступенчатого хода
// Pitch): ручка показывает ноту и идёт по полутонам; нота шага, клавиатуры и MIDI сдвигает высоту от основы на
// (нота − C3); пока идёт или зажат шаг с нотой, на ручке — её нота, как p-lock. Без режима у ударных нота высоту не
// меняет (как прежде). KICK, SNARE, PERC — основа на ближайшей ноте темперации; HAT (TUNE — от 808) — полутоны от C3.

public enum PitchKey {
    public static let id: String = Params.stepModeId("pitch")
    /// Нота, на которой звучит основа (как C3 у сэмпла).
    public static let root: Double = Double(Params.sampleRoot)

    /// Движок с Pitch по нотам (ручка 1.1).
    @inline(__always) public static func drum(_ e: Int) -> Bool {
        return e == Jambo.drum || e == Jambo.snare || e == Jambo.hat || e == Jambo.perc
    }

    /// Пределы частоты 1.1 (Гц, логарифмически по ходу); у HAT — 0 (TUNE ±1 октава).
    @inline(__always) static func range(_ e: Int) -> (lo: Double, hi: Double) {
        if e == Jambo.drum { return (Jambo.drumPitchMin, Jambo.drumPitchMax) }
        if e == Jambo.snare { return (120, 400) }
        if e == Jambo.perc { return (60, 2000) }
        return (0, 0)
    }

    /// MIDI-нота основы (целая) по положению ручки n (0…1).
    public static func base(_ e: Int, _ n: Double) -> Double {
        let r = range(e)
        if r.lo <= 0 { return root + ((2 * n - 1) * 12).rounded() }
        let f: Double = r.lo * pow(r.hi / r.lo, n)
        return (69 + 12 * log2(f / 440)).rounded()
    }

    /// Положение ручки (0…1, за краями — продолжение шкалы), на котором звучит MIDI-нота m.
    public static func norm(_ e: Int, midi m: Double) -> Double {
        let r = range(e)
        if r.lo <= 0 { return ((m - root) / 12 + 1) / 2 }
        let f: Double = 440 * pow(2, (m - 69) / 12)
        return log(f / r.lo) / log(r.hi / r.lo)
    }

    /// Колбэк: 1.1 ударного с нотой — основа + (нота − C3); не дальше хода ручки в каждую сторону.
    @inline(__always) public static func knob(_ e: Int, _ n: Double, note: Double) -> Double {
        let v: Double = norm(e, midi: base(e, n) + note - root)
        return Swift.max(-1, Swift.min(2, v))
    }
}

extension PitchKey {
    /// Pitch сэмпла по нотам: ход по полутонам, на ручке — нота (C3 + Pitch).
    public static let sampleDef: ParamDef = ParamDef(id: "pitch", label: "Pitch Note", min: -24, max: 24, def: 0,
                                                     bipolar: true) { v in
        Params.noteName(Params.sampleRoot + Int(v.rounded()))
    }

    /// 1.1 ударного по нотам: подпись прежняя, значение — нота основы.
    public static let drumDefs: [Int: ParamDef] = {
        var out: [Int: ParamDef] = [:]
        for e in [Jambo.drum, Jambo.snare, Jambo.hat, Jambo.perc] {
            guard e < Params.synthGrids.count, let p = Params.synthGrids[e].first else { continue }
            out[e] = ParamDef(id: p.id, label: p.label + " Note", min: p.min, max: p.max, def: p.def) { v in
                Params.noteName(Int(PitchKey.base(e, v / 100)))
            }
        }
        return out
    }()

    /// Значение ручки (её единицы) с нотой шага: сэмпл — + (нота − C3) полутонов, ударный — основа + (нота − C3).
    public static func shifted(_ e: Int?, _ v: Double, note: Int) -> Double {
        let k: Double = Double(note) - root
        guard let eng = e else { return v.rounded() + k }
        return norm(eng, midi: base(eng, v / 100) + k) * 100
    }

    /// Ход по полутонам: значение ручки (единицы) — на ближайшей ноте.
    public static func snapped(_ e: Int?, _ v: Double) -> Double {
        guard let eng = e else { return v.rounded() }
        return Swift.max(0, Swift.min(100, norm(eng, midi: base(eng, v / 100)) * 100))
    }
}
