// Движки синта (как SYNTH_ENGINES, synthKey, synthEngine в src/params.ts веба): звук дорожки или шага «mi:<n>».
// MI SYNTH — Plaits 0–7, MI DRUMS — Plaits 8–15, свои (SYNTH) — DRUM, ANALOG, FM, WTABLE (16–19).

/// Движок: короткое имя (меню), полное (окно синта), подписи ручек 1.1–1.3, пункты Harmonics и точки harmonics
/// для Plaits по пункту (SPEECH: Formant, Phoneme, LPC — 0, 1/6, 1/3; Words отключён).
/// decay — затухает сам (STRING, MODAL, KICK, SNARE, HI-HAT): Morph Plaits — от ручки Decay, ручка 1.3 — OUT→AUX,
/// огибающая дорожки только с атакой.
public struct SynthEngine: Sendable {
    public let name: String
    public let full: String
    public let harm: String
    public let timbre: String
    public let morph: String
    public let options: [String]
    public let harmPoints: [Float]
    public var decay = false
    /// Свой движок JAMbo (Core/Jambo, jambo-synth-worklet.js веба): ручки 1.1–1.3 — p1–p3 (0…1), Decay — в мс.
    public var jambo = false
    /// Свой предел ручки Decay, мс (у DRUM — 1000).
    public var decayMax: Double? = nil
    /// Ручки 1.1–1.3 (harm, timbre, morph), которые ставятся при выборе движка на дорожку с другого звука.
    public var initKnobs: [Double] = []
}

public enum SynthEngines {
    public static let all: [SynthEngine] = [
        SynthEngine(name: "VA", full: "Pair of classic waves", harm: "detune", timbre: "pulse width",
                    morph: "triangle→saw", options: [], harmPoints: []),
        SynthEngine(name: "WAVESHAPE", full: "Waveshaper", harm: "shaper waveform", timbre: "fold depth",
                    morph: "asymmetry", options: [], harmPoints: []),
        SynthEngine(name: "FM", full: "Two-operator FM", harm: "frequency ratio", timbre: "mod index",
                    morph: "feedback", options: [], harmPoints: []),
        SynthEngine(name: "GRAIN", full: "Granular formant", harm: "formant ratio", timbre: "formant freq",
                    morph: "formant width", options: [], harmPoints: []),
        SynthEngine(name: "ADDITIVE", full: "Harmonic", harm: "bumps", timbre: "main harmonic",
                    morph: "bump shape", options: [], harmPoints: []),
        SynthEngine(name: "WAVETABLE", full: "Wavetable", harm: "bank", timbre: "row", morph: "column",
                    options: ["A", "B", "C", "D"], harmPoints: []),
        SynthEngine(name: "CHORDS", full: "Chords", harm: "chord type", timbre: "inversion", morph: "waveform",
                    options: ["oct", "5", "sus4", "m", "m7", "m9", "m11", "6/9", "M9", "M7", "M"], harmPoints: []),
        SynthEngine(name: "SPEECH", full: "Vowel & speech", harm: "mode", timbre: "species", morph: "phoneme",
                    options: ["Formant", "Phoneme", "LPC"], harmPoints: [0, 0.16666667, 0.33333334]),
        SynthEngine(name: "SWARM", full: "Granular cloud", harm: "pitch spread", timbre: "density",
                    morph: "grain length", options: [], harmPoints: []),
        SynthEngine(name: "NOISE", full: "Filtered noise", harm: "LP→BP→HP", timbre: "clock freq",
                    morph: "resonance", options: [], harmPoints: []),
        SynthEngine(name: "PARTICLE", full: "Particle noise", harm: "freq spread", timbre: "density",
                    morph: "all-pass→band-pass", options: [], harmPoints: []),
        SynthEngine(name: "STRING", full: "Inharmonic string", harm: "material (inharmonicity)",
                    timbre: "excitation brightness", morph: "OUT→AUX", options: [], harmPoints: [], decay: true),
        SynthEngine(name: "MODAL", full: "Modal resonator", harm: "material", timbre: "brightness & dust",
                    morph: "OUT→AUX", options: [], harmPoints: [], decay: true),
        SynthEngine(name: "KICK", full: "Analog bass drum", harm: "attack & overdrive", timbre: "brightness",
                    morph: "OUT→AUX", options: [], harmPoints: [], decay: true),
        SynthEngine(name: "SNARE", full: "Analog snare", harm: "harmonics↔noise", timbre: "mode balance",
                    morph: "OUT→AUX", options: [], harmPoints: [], decay: true),
        SynthEngine(name: "HI-HAT", full: "Analog hi-hat", harm: "metal↔noise", timbre: "HPF cutoff",
                    morph: "OUT→AUX", options: [], harmPoints: [], decay: true),
        // Свои движки: DRUM — бочка (высота — ручкой PITCH, монофонична), ANALOG — по умолчанию чистый синус.
        SynthEngine(name: "DRUM", full: "Drum", harm: "pitch", timbre: "sweep", morph: "drive", options: [],
                    harmPoints: [], decay: true, jambo: true, decayMax: 1000),
        SynthEngine(name: "ANALOG", full: "Analog", harm: "wave", timbre: "detune", morph: "sub",
                    options: ["Sine", "Triangle", "Saw", "Square"], harmPoints: [], jambo: true,
                    initKnobs: [12.5, 0, 0]),
        SynthEngine(name: "FM", full: "FM", harm: "ratio", timbre: "index", morph: "contour", options: [],
                    harmPoints: [], jambo: true),
        // WTABLE: таблица — у дорожки (Track.table), в окне синта вместо иконки — кадр таблицы.
        SynthEngine(name: "WTABLE", full: "Wavetable", harm: "position", timbre: "warp", morph: "unison",
                    options: [], harmPoints: [], jambo: true),
    ]

    /// Первый свой движок (DRUM).
    public static let firstJambo = 16

    /// Первый движок MI DRUMS (Plaits 8–15).
    public static let firstDrum = 8

    public static var count: Int { return all.count }

    static func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return String(f).uppercased() + s.dropFirst()
    }
}

/// Ключ звука синта: «mi:<n>» — движок n (как synthKey / synthEngine веба).
public enum SynthKey {
    public static func key(_ engine: Int) -> String { return "mi:\(engine)" }

    /// Номер движка из ключа звука; не синт или неизвестный номер — nil.
    public static func engine(_ key: String) -> Int? {
        guard key.hasPrefix("mi:"), let n = Int(key.dropFirst(3)), n >= 0, n < SynthEngines.count else { return nil }
        return n
    }
}

extension Track {
    /// Синт на дорожку (setTrackSynth веба): звук дорожки — «mi:<n>»; ручки Harmonics, Timbre, Morph остаются,
    /// кроме своих начальных у движка (ANALOG — синус без DETUNE и SUB) при переходе с другого звука; Decay больше
    /// предела движка (DRUM — 1000 мс) — к пределу.
    public mutating func setSynth(_ engine: Int) {
        let key = SynthKey.key(engine)
        let was = sample
        sample = key
        guard engine >= 0 && engine < SynthEngines.count else { return }
        let e = SynthEngines.all[engine]
        if e.initKnobs.count == 3 && was != key {
            params["harm"] = e.initKnobs[0]
            params["timbre"] = e.initKnobs[1]
            params["morph"] = e.initKnobs[2]
        }
        if let max = e.decayMax, let d = params["decay"], d > max { params["decay"] = max }
    }
}
