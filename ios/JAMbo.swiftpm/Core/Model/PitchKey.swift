import Foundation

// Pitch по нотам (14.11, решение пользователя): SHIFT + тап по Pitch — у ударных KICK, SNARE, HAT, CLAP, PERC
// (ручка 1.1) и у сэмпла. Значение звука Params.stepModeId("pitch") (pitch.step; у сэмпла — тот же переключатель
// ступенчатого хода Pitch). Ручка — транспонирование по полутонам (−24…+24; на ручке нота C3 + сдвиг, по умолчанию
// C3); шаг звучит своей нотой (клавиатура, MIDI) + сдвиг, и на ручке — эта нота, как p-lock (держится до следующей
// ноты). Без режима у ударных нота высоту не меняет (как прежде). Регистр ударных: KICK — на 2 октавы ниже ноты
// (C3 → C1), SNARE и PERC — как есть, CLAP (TONE — фильтр шума) — на 3 октавы выше; HAT (TUNE — от 808) — полутоны от
// C3. Сэмпл — как прежде: высота от ноты (C3 — исходная) и Pitch.

public enum PitchKey {
    public static let id: String = Params.stepModeId("pitch")
    /// Нота без сдвига (как C3 у сэмпла).
    public static let root: Double = Double(Params.sampleRoot)
    /// Полутонов на единицу хода ручки 1.1 (0…100, середина — 0): ±24.
    static let perUnit: Double = 0.48

    /// Движок с Pitch по нотам (ручка 1.1).
    @inline(__always) public static func drum(_ e: Int) -> Bool {
        return e == Jambo.drum || e == Jambo.snare || e == Jambo.hat || e == Jambo.clap || e == Jambo.perc
    }

    /// Сдвиг регистра движка, полутоны (нота шага → нота звука).
    @inline(__always) static func register(_ e: Int) -> Double {
        if e == Jambo.drum { return -24 }
        if e == Jambo.clap { return 36 }
        return 0
    }

    /// Пределы частоты 1.1 (Гц, логарифмически по ходу); у HAT — 0 (TUNE ±1 октава), у CLAP — своя кривая.
    @inline(__always) static func range(_ e: Int) -> (lo: Double, hi: Double) {
        if e == Jambo.drum { return (Jambo.drumPitchMin, Jambo.drumPitchMax) }
        if e == Jambo.snare { return (120, 400) }
        if e == Jambo.perc { return (60, 2000) }
        if e == Jambo.clap { return (700, 3000) }
        return (0, 0)
    }

    /// Сдвиг (полутоны, целый) по значению ручки v: у сэмпла (e = nil) — Pitch, у ударного — 1.1 (0…100).
    @inline(__always) public static func semis(_ e: Int?, _ v: Double) -> Double {
        if e == nil { return v.rounded() }
        return ((v - 50) * perUnit).rounded()
    }

    /// Значение ручки для сдвига s.
    @inline(__always) static func value(_ e: Int?, semis s: Double) -> Double {
        if e == nil { return s }
        return 50 + s / perUnit
    }

    /// Положение 1.1 (0…1; у KICK, SNARE, PERC, HAT — за краями хода продолжение шкалы), на котором звучит MIDI-нота m.
    public static func norm(_ e: Int, midi m: Double) -> Double {
        let r = range(e)
        if r.lo <= 0 { return ((m - root) / 12 + 1) / 2 }
        let f: Double = 440 * pow(2, (m - 69) / 12)
        let x: Double = log(f / r.lo) / log(r.hi / r.lo)
        // CLAP: TONE = 700 · (3000/700)^(n^1,69) — обратная кривая, в пределах хода.
        if e == Jambo.clap { return pow(Swift.max(0, Swift.min(1, x)), 1 / 1.69) }
        return x
    }

    /// Колбэк: 1.1 ударного по ноте note и ручке (n = значение / 100).
    @inline(__always) public static func knob(_ e: Int, _ n: Double, note: Double) -> Double {
        let m: Double = note + semis(e, n * 100) + register(e)
        let v: Double = norm(e, midi: m)
        return Swift.max(-1, Swift.min(2, v))
    }
}

extension PitchKey {
    /// Pitch сэмпла по нотам: ход по полутонам, на ручке — нота (C3 + Pitch).
    public static let sampleDef: ParamDef = ParamDef(id: "pitch", label: "Pitch Note", min: -24, max: 24, def: 0,
                                                     bipolar: true) { v in
        Params.noteName(Params.sampleRoot + Int(v.rounded()))
    }

    /// 1.1 ударного по нотам: подпись «… Note», значение — нота C3 + сдвиг.
    public static let drumDefs: [Int: ParamDef] = {
        var out: [Int: ParamDef] = [:]
        for e in [Jambo.drum, Jambo.snare, Jambo.hat, Jambo.clap, Jambo.perc] {
            guard e < Params.synthGrids.count, let p = Params.synthGrids[e].first else { continue }
            out[e] = ParamDef(id: p.id, label: p.label + " Note", min: p.min, max: p.max, def: p.def,
                              bipolar: true) { v in
                Params.noteName(Params.sampleRoot + Int(PitchKey.semis(e, v)))
            }
        }
        return out
    }()

    /// Значение ручки, на котором видна нота шага note со сдвигом ручки v (как p-lock; может выйти за ход).
    public static func shifted(_ e: Int?, _ v: Double, note: Int) -> Double {
        let s: Double = Double(note) - root + semis(e, v)
        return value(e, semis: s)
    }

    /// Ход по полутонам: значение ручки — на ближайшем полутоне.
    public static func snapped(_ e: Int?, _ v: Double) -> Double {
        let s: Double = semis(e, v)
        if e == nil { return s }
        return Swift.max(0, Swift.min(100, value(e, semis: s)))
    }
}
