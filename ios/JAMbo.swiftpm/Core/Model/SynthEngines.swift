import Foundation

// Таблица движков синта (как SYNTH_ENGINES в params.ts веба) — одно место для названий, подписей ручек 1.1–1.3,
// ступенчатой 1.1 и признаков. Номер = номер движка: 0–15 — Plaits, 16–19 — свои (DRUM, ANALOG, FM, WTABLE).
// Ключ звука дорожки — "mi:<n>".

public enum SynthBank: Sendable { case synth, drum, jambo }

public struct SynthEngine: Sendable {
    public let name: String
    public let full: String
    public let bank: SynthBank
    /// Затухает сам (11–15 и DRUM): Decay управляет затуханием, Morph — OUT→AUX; огибающая только с атакой.
    public let decay: Bool
    public let harm: String
    public let timbre: String
    public let morph: String
    /// Ступенчатая 1.1: подписи пунктов (значение остаётся 0…100 %, ручка встаёт на середину пункта).
    public let options: [String]
    /// SPEECH: значение harmonics для Plaits по пункту.
    public let harmPoints: [Float]
    /// Перенесён ли движок в Swift-версию (остальные в меню серые).
    public let ready: Bool

    init(_ name: String, _ full: String, _ bank: SynthBank, decay: Bool = false, _ harm: String, _ timbre: String,
         _ morph: String, options: [String] = [], harmPoints: [Float] = [], ready: Bool = true) {
        self.name = name
        self.full = full
        self.bank = bank
        self.decay = decay
        self.harm = harm
        self.timbre = timbre
        self.morph = morph
        self.options = options
        self.harmPoints = harmPoints
        self.ready = ready
    }

    public var isPlaits: Bool { bank != .jambo }
}

public enum SynthEngines {
    public static let all: [SynthEngine] = [
        SynthEngine("VA", "Pair of classic waves", .synth, "detune", "pulse width", "triangle→saw"),
        SynthEngine("WAVESHAPE", "Waveshaper", .synth, "shaper waveform", "fold depth", "asymmetry"),
        SynthEngine("FM", "Two-operator FM", .synth, "frequency ratio", "mod index", "feedback"),
        SynthEngine("GRAIN", "Granular formant", .synth, "formant ratio", "formant freq", "formant width"),
        SynthEngine("ADDITIVE", "Harmonic", .synth, "bumps", "main harmonic", "bump shape"),
        SynthEngine("WAVETABLE", "Wavetable", .synth, "bank", "row", "column", options: ["A", "B", "C", "D"]),
        SynthEngine("CHORDS", "Chords", .synth, "chord type", "inversion", "waveform",
                    options: ["oct", "5", "sus4", "m", "m7", "m9", "m11", "6/9", "M9", "M7", "M"]),
        SynthEngine("SPEECH", "Vowel & speech", .synth, "mode", "species", "phoneme",
                    options: ["Formant", "Phoneme", "LPC"], harmPoints: [0, 1.0 / 6, 1.0 / 3]),
        SynthEngine("SWARM", "Granular cloud", .drum, "pitch spread", "density", "grain length", ready: false),
        SynthEngine("NOISE", "Filtered noise", .drum, "LP→BP→HP", "clock freq", "resonance", ready: false),
        SynthEngine("PARTICLE", "Particle noise", .drum, "freq spread", "density", "all-pass→band-pass", ready: false),
        SynthEngine("STRING", "Inharmonic string", .drum, decay: true, "material (inharmonicity)", "excitation brightness",
                    "OUT→AUX", ready: false),
        SynthEngine("MODAL", "Modal resonator", .drum, decay: true, "material", "brightness & dust", "OUT→AUX", ready: false),
        SynthEngine("KICK", "Analog bass drum", .drum, decay: true, "attack & overdrive", "brightness", "OUT→AUX", ready: false),
        SynthEngine("SNARE", "Analog snare", .drum, decay: true, "harmonics↔noise", "mode balance", "OUT→AUX", ready: false),
        SynthEngine("HI-HAT", "Analog hi-hat", .drum, decay: true, "metal↔noise", "HPF cutoff", "OUT→AUX", ready: false),
        SynthEngine("DRUM", "Drum", .jambo, decay: true, "pitch", "sweep", "drive", ready: false),
        SynthEngine("ANALOG", "Analog", .jambo, "wave", "detune", "sub", options: ["Sine", "Triangle", "Saw", "Square"],
                    ready: false),
        SynthEngine("FM", "FM", .jambo, "ratio", "index", "contour", ready: false),
        SynthEngine("WTABLE", "Wavetable", .jambo, "position", "warp", "unison", ready: false),
    ]
    public static let speech = 7

    public static func key(_ engine: Int) -> String { "mi:\(engine)" }

    /// Номер движка из ключа звука; не синт или неизвестный номер — nil.
    public static func engine(_ key: String) -> Int? {
        guard key.hasPrefix("mi:"), let n = Int(key.dropFirst(3)), n >= 0, n < all.count else { return nil }
        return n
    }

    /// Ключи "mi:n" по номеру (хэши — для колбэка: свой звук шага по хэшу).
    public static let hashes: [UInt64] = (0..<all.count).map { SoundKey.hash(key($0)) }

    /// Пункт ступенчатой ручки по положению 0…1.
    public static func stepIndex(_ n: Double, _ steps: Int) -> Int {
        Swift.min(steps - 1, Swift.max(0, Int((n * Double(steps)).rounded(.down))))
    }

    /// Сетка ручек движка (готовая на каждый движок).
    public static func grid(_ engine: Int) -> [ParamDef] { grids[Swift.max(0, Swift.min(all.count - 1, engine))] }
    private static let grids: [[ParamDef]] = (0..<all.count).map { makeGrid($0) }

    /// Колонка 1 движка: Harmonics, Timbre, Morph с подписями из таблицы (у ступенчатых — пункты).
    static func makeGrid(_ engine: Int) -> [ParamDef] {
        let e = all[engine]
        func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
        return Params.trackGrid.enumerated().map { i, p in
            switch i {
            case 0:
                if !e.options.isEmpty {
                    let o = e.options
                    return ParamDef(id: "harm", label: cap(e.harm), min: 0, max: 100, def: 50, steps: o.count) { v in
                        o[stepIndex(v / 100, o.count)]
                    }
                }
                return ParamDef(id: "harm", label: cap(e.harm), min: 0, max: 100, def: 50, format: Fmt.pct)
            case 4: return ParamDef(id: "timbre", label: cap(e.timbre), min: 0, max: 100, def: 50, format: Fmt.pct)
            case 8: return ParamDef(id: "morph", label: cap(e.morph), min: 0, max: 100, def: 50, format: Fmt.pct)
            default: return p
            }
        }
    }

    /// Параметры ручек движка 0…1 для голоса: harmonics (у SPEECH — точка пункта), timbre, morph, aux.
    /// У затухающих самих (11–15) Morph Plaits — затухание (по Decay), ручка Morph — OUT→AUX.
    @inline(__always)
    public static func plaitsParams(_ engine: Int, harm: Float, timbre: Float, morph: Float, decayMs: Float)
        -> (h: Float, t: Float, m: Float, aux: Float) {
        var h = harm / 100
        if engine == speech {
            let i = Swift.min(2, Swift.max(0, Int(h * 3)))
            h = i == 0 ? 0 : (i == 1 ? 1.0 / 6 : 1.0 / 3)
        }
        if engine >= 11 && engine <= 15 {
            let d = Swift.min(1, Swift.max(0, decayMs / 4000)).squareRoot()
            return (h, timbre / 100, d, morph / 100)
        }
        return (h, timbre / 100, morph / 100, 0)
    }
}
