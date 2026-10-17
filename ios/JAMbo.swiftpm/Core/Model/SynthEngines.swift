// Движки синта (как SYNTH_ENGINES, synthKey, synthEngine в src/params.ts веба): звук дорожки или шага «mi:<n>».
// Пока MI SYNTH — Plaits 0–7; MI DRUMS (8–15) и свои движки (16–19) — S3b.

/// Движок: короткое имя (меню), полное (окно синта), подписи ручек 1.1–1.3, пункты Harmonics и точки harmonics
/// для Plaits по пункту (SPEECH: Formant, Phoneme, LPC — 0, 1/6, 1/3; Words отключён).
public struct SynthEngine: Sendable {
    public let name: String
    public let full: String
    public let harm: String
    public let timbre: String
    public let morph: String
    public let options: [String]
    public let harmPoints: [Float]
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
    ]

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
    /// Синт на дорожку (setTrackSynth веба): звук дорожки — «mi:<n>»; ручки Harmonics, Timbre, Morph остаются.
    public mutating func setSynth(_ engine: Int) {
        sample = SynthKey.key(engine)
    }
}
