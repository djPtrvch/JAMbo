import Foundation

// Единая таблица параметров (как src/params.ts веба): подписи ручек, диапазоны, значения по умолчанию, форматы.
// Меняем подписи и диапазоны только здесь.

public enum KnobKind: Sendable {
    case smooth
    case stepped
}

public struct ParamDef: @unchecked Sendable {
    public let id: String
    public let label: String
    public let kind: KnobKind
    public let min: Double
    public let max: Double
    public let def: Double
    /// Степенная шкала от нуля: значение = min + (max − min)·n^curve.
    public let curve: Double?
    /// Экспоненциальная шкала (частоты).
    public let exp: Bool
    /// Дуга от центра (Pan, Pitch, Filter).
    public let bipolar: Bool
    /// Подписи пунктов ступенчатой ручки (значение = индекс).
    public let options: [String]
    /// Пункты ступенчатой ручки с непрерывным значением (Harmonics у WAVETABLE, CHORDS, SPEECH): значение — середина
    /// пункта на min…max (как steps в params.ts веба).
    public let steps: Int?
    public let format: (Double) -> String

    public init(id: String, label: String, kind: KnobKind = .smooth, min: Double, max: Double, def: Double,
                curve: Double? = nil, exp: Bool = false, bipolar: Bool = false, options: [String] = [], steps: Int? = nil,
                format: @escaping (Double) -> String) {
        self.id = id
        self.label = label
        self.kind = kind
        self.min = min
        self.max = max
        self.def = def
        self.curve = curve
        self.exp = exp
        self.bipolar = bipolar
        self.options = options
        self.steps = steps
        self.format = format
    }

    /// Значение → положение ручки 0…1.
    public func toNorm(_ v: Double) -> Double {
        if exp { return log(v / min) / log(max / min) }
        let lin: Double = Swift.min(1, Swift.max(0, (v - min) / (max - min)))
        if let c = curve { return pow(lin, 1 / c) }
        return lin
    }

    /// Положение ручки 0…1 → значение (ступенчатые округляются).
    public func fromNorm(_ n0: Double) -> Double {
        let n: Double = Swift.min(1, Swift.max(0, n0))
        if let s = steps { return min + (Double(Params.stepIndex(n, s)) + 0.5) / Double(s) * (max - min) }
        if kind == .stepped { return (n * (max - min)).rounded() + min }
        if exp { return min * pow(max / min, n) }
        if let c = curve { return min + pow(n, c) * (max - min) }
        return min + n * (max - min)
    }
}

public enum Fmt {
    public static func pct(_ v: Double) -> String { return "\(Int(v.rounded()))%" }

    public static func ms(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.2fs", v / 1000) }
        return "\(Int(v.rounded()))ms"
    }

    public static func hz(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        if v >= 100 { return "\(Int(v.rounded()))" }
        return String(format: "%.1f", v)
    }

    /// Двухполярный фильтр: влево от центра — low pass, вправо — high pass, в центре выключен.
    public static func filterFreq(_ v: Double) -> (type: Int, hz: Double) {
        if abs(v) < 0.5 { return (0, 0) }
        if v < 0 { return (-1, 20000 * pow(30.0 / 20000, -v / 100)) }
        return (1, 20 * pow(10000.0 / 20, v / 100))
    }

    public static func filter(_ v: Double) -> String {
        let f = filterFreq(v)
        if f.type == 0 { return "OFF" }
        return "\(f.type < 0 ? "LP" : "HP") \(hz(f.hz))"
    }

    public static func pan(_ v: Double) -> String {
        let r = Int(v.rounded())
        if r == 0 { return "C" }
        return r < 0 ? "L\(-r)" : "R\(r)"
    }

    public static func pitch(_ v: Double) -> String {
        return (v > 0 ? "+" : "") + String(format: "%.1fst", v)
    }
}

public enum Params {
    public static let stepsPerPage = 16
    public static let maxPages = 8
    public static let trackCount = 8
    /// Строк сетки паттернов (ячеек в столбце); на экране — gridRows.
    public static let patternSlots = 16
    public static let gridRows = 8
    public static let maxTracks = 16
    public static let bpmMin = 40.0
    public static let bpmMax = 240.0
    /// Сэмпл звучит в исходной высоте на C3.
    public static let sampleRoot = 48
    /// Громкость дорожки в микшере, dB: от тишины (−∞ на минимуме) до 0 dB, по умолчанию −10.
    public static let volMin = -60.0
    public static let volDef = -10.0

    /// Громкость (dB) → усиление; на минимуме — 0.
    public static func volGain(_ db: Double) -> Double {
        return db <= volMin + 0.05 ? 0 : pow(10, db / 20)
    }

    public static func volText(_ v: Double) -> String {
        return v <= volMin + 0.05 ? "−∞\ndB" : String(format: "%.1f\ndB", v)
    }

    /// Ручки микшера (MIX): громкости дорожек 1…16 (id mix.vol1…16), несуществующие — серые.
    public static let mixGrid: [ParamDef] = (0..<16).map { i in
        ParamDef(id: "mix.vol\(i + 1)", label: "\(i + 1)", min: volMin, max: 0, def: volDef, format: volText)
    }
    public static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func noteName(_ n: Int) -> String {
        let octave = Int((Double(n) / 12).rounded(.down)) - 1
        return noteNames[((n % 12) + 12) % 12] + "\(octave)"
    }

    private static func smooth(_ id: String, _ label: String, _ min: Double, _ max: Double, _ def: Double,
                               curve: Double? = nil, exp: Bool = false, bipolar: Bool = false,
                               _ format: @escaping (Double) -> String) -> ParamDef {
        return ParamDef(id: id, label: label, min: min, max: max, def: def, curve: curve, exp: exp, bipolar: bipolar,
                        format: format)
    }

    private static func stepped(_ id: String, _ label: String, _ options: [String], def: Double = 0) -> ParamDef {
        let opts = options
        return ParamDef(id: id, label: label, kind: .stepped, min: 0, max: Double(options.count - 1), def: def, options: options) { v in
            let i = Int(v.rounded())
            return i >= 0 && i < opts.count ? opts[i] : ""
        }
    }

    /// Колонки сетки ручек дорожки сэмплера (у синта колонка 1 — synthGrids; колонка 1 — сэмпл, 2 — огибающая и фильтр, 3 — посылы, 4 — Pan, Chance, Ratchet, Swing).
    public static let trackColumns: [[ParamDef]] = [
        [
            smooth("pitch", "Pitch", -24, 24, 0, bipolar: true, Fmt.pitch),
            smooth("start", "Start", 0, 100, 0, Fmt.pct),
            smooth("end", "End", 0, 100, 100, Fmt.pct),
            // Level: на ручке — проценты; хранится 0…127.
            smooth("level", "Level", 0, 127, 127) { v in "\(Int((v / 127 * 100).rounded()))%" },
        ],
        [
            smooth("attack", "Attack", 0, 2000, 0, curve: 3, Fmt.ms),
            smooth("decay", "Decay", 0, 4000, 500, curve: 3, Fmt.ms),
            smooth("filter", "Filter", -100, 100, 0, bipolar: true, Fmt.filter),
            smooth("reso", "Resonance", 0, 100, 0, Fmt.pct),
        ],
        [
            smooth("reverb", "Reverb", 0, 100, 0, Fmt.pct),
            smooth("delay", "Delay", 0, 100, 0, Fmt.pct),
            smooth("drive", "Drive", 0, 100, 0, Fmt.pct),
            smooth("sidechain", "Sidechain", 0, 100, 0, Fmt.pct),
        ],
        [
            smooth("pan", "Pan", -64, 63, 0, bipolar: true, Fmt.pan),
            smooth("prob", "Chance", 0, 100, 100, Fmt.pct),
            stepped("ratchet", "Ratchet", ["1", "2", "3", "4"]),
            smooth("swing", "Swing", 50, 75, 50, Fmt.pct),
        ],
    ]

    /// Сетка 4×4 ряд за рядом (индекс = ряд·4 + столбец).
    public static let trackGrid: [ParamDef] = (0..<16).map { i in trackColumns[i % 4][i / 4] }

    /// Колонка 1 синта (вместо Pitch, Start, End): Harmonics, Timbre, Morph — 0…100 %, по умолчанию 50 (SYNTH_GRID).
    public static let synthColumn: [ParamDef] = [
        smooth("harm", "Harmonics", 0, 100, 50, Fmt.pct),
        smooth("timbre", "Timbre", 0, 100, 50, Fmt.pct),
        smooth("morph", "Morph", 0, 100, 50, Fmt.pct),
    ]

    /// Пункт ступенчатой ручки по положению 0…1.
    public static func stepIndex(_ n: Double, _ steps: Int) -> Int {
        return Swift.min(steps - 1, Swift.max(0, Int((n * Double(steps)).rounded(.down))))
    }

    /// Сетка синта движка e (ENGINE_GRIDS): подписи 1.1–1.3 из таблицы движков, у WAVETABLE, CHORDS, SPEECH
    /// Harmonics ступенчатая (пункты движка).
    public static let synthGrids: [[ParamDef]] = SynthEngines.all.map { e in
        let col: [ParamDef] = synthColumn.enumerated().map { k, p in
            let label = SynthEngines.capitalized([e.harm, e.timbre, e.morph][k])
            if k == 0 && !e.options.isEmpty {
                let o = e.options
                return ParamDef(id: p.id, label: label, kind: .stepped, min: p.min, max: p.max, def: p.def,
                                steps: o.count) { v in o[stepIndex(v / 100, o.count)] }
            }
            // Свой формат 1.1: PITCH у DRUM — Гц, RATIO у FM — ×2.00 (harmFormat веба).
            if k == 0 && e.name == "DRUM" {
                return ParamDef(id: p.id, label: label, min: p.min, max: p.max, def: p.def) { v in
                    "\(Int(Jambo.drumPitch(v / 100).rounded())) Hz"
                }
            }
            if k == 0 && e.jambo && e.name == "FM" {
                return ParamDef(id: p.id, label: label, min: p.min, max: p.max, def: p.def) { v in
                    "×" + String(format: "%.2f", Jambo.fmRatio(v / 100))
                }
            }
            return ParamDef(id: p.id, label: label, min: p.min, max: p.max, def: p.def, format: p.format)
        }
        return (0..<16).map { i in
            if i % 4 == 0 && i / 4 < 3 { return col[i / 4] }
            let p = trackGrid[i]
            // Свой предел Decay (у DRUM — 1000 мс).
            if p.id == "decay", let max = e.decayMax {
                return ParamDef(id: p.id, label: p.label, kind: p.kind, min: p.min, max: max, def: p.def,
                                curve: p.curve, exp: p.exp, bipolar: p.bipolar, options: p.options, steps: p.steps,
                                format: p.format)
            }
            return p
        }
    }

    /// Сетка ручек дорожки по её звуку: синт — сетка движка, иначе сэмплер.
    public static func grid(sound: String) -> [ParamDef] {
        if let e = SynthKey.engine(sound) { return synthGrids[e] }
        return trackGrid
    }

    // MARK: — MOD: LFO1–3 и ENV (по дорожкам, MOD_GRID веба)

    public static let lfoWaves = ["Sine", "Triangle", "Saw", "Square", "Random"]

    static func lfoHz(_ v: Double) -> String { return v < 1 ? String(format: "%.2fHz", v) : String(format: "%.1fHz", v) }

    static func lfoColumn(_ n: Int) -> [ParamDef] {
        return [
            stepped("lfo\(n).wave", "LFO\(n) Wave", lfoWaves),
            smooth("lfo\(n).speed", "LFO\(n) Speed", 0.05, 20, [0.1, 0.5, 1][n - 1], exp: true, lfoHz),
            smooth("lfo\(n).invert", "LFO\(n) Invert", 0, 1, 0) { v in
                let p = Int(((1 - 2 * v) * 100).rounded())
                return p == 0 ? "flat" : "\(p > 0 ? "+" : "")\(p)%"
            },
            // Полярность: 0 — биполярная (−1…+1 вокруг значения ручки), 1 — однополярная (0…+1), между — плавно.
            smooth("lfo\(n).polar", "LFO\(n) Polarity", 0, 1, 0) { v in
                v < 0.005 ? "BI" : (v > 0.995 ? "UNI" : "UNI \(Int((v * 100).rounded()))%")
            },
        ]
    }

    public static let modColumns: [[ParamDef]] = [
        lfoColumn(1), lfoColumn(2), lfoColumn(3),
        [
            smooth("env.attack", "ENV Attack", 1, 4000, 10, exp: true, Fmt.ms),
            smooth("env.decay", "ENV Decay", 1, 4000, 100, exp: true, Fmt.ms),
            smooth("env.sustain", "ENV Sustain", 0, 100, 40, Fmt.pct),
            smooth("env.release", "ENV Release", 1, 4000, 300, exp: true, Fmt.ms),
        ],
    ]

    /// Сетка MOD 4×4 ряд за рядом; порядок в снимках для колбэка — modColumns подряд (LFO1, LFO2, LFO3, ENV).
    public static let modGrid: [ParamDef] = (0..<16).map { i in modColumns[i % 4][i / 4] }
    public static let modIds: [String] = modColumns.flatMap { $0 }.map { $0.id }
    public static let modCount = 16

    // MARK: — FX (общие параметры, FX_GRID веба)

    /// Время Delay в долях такта: подпись и длительность в четвертях.
    public static let delayDivs: [(name: String, beats: Double)] = [
        ("1/32", 0.125), ("1/16T", 1.0 / 6), ("1/16", 0.25), ("1/16D", 0.375), ("1/8T", 1.0 / 3), ("1/8", 0.5),
        ("1/8D", 0.75), ("1/4T", 2.0 / 3), ("1/4", 1), ("1/4D", 1.5), ("1/2", 2), ("1 bar", 4),
    ]
    /// LOW CUT Drive не выше — обход (OFF); в новом проекте — 80 Гц, LOW CUT реверба — 120 Гц.
    public static let driveLowCutOff = 25.0
    public static let driveLowCutNew = 80.0
    public static let revHpfNew = 120.0

    /// FILTER дилея: влево — LP 20 кГц → 500 Гц, вправо — HP 20 → 1500 Гц, в центре выключен.
    public static func delayFilterFreq(_ v: Double) -> (type: Int, hz: Double) {
        let a = abs(v) / 100
        if a < 0.02 { return (0, 0) }
        if v < 0 { return (-1, 20000 * pow(500.0 / 20000, a)) }
        return (1, 20 * pow(1500.0 / 20, a))
    }

    public static let fxColumns: [[ParamDef]] = [
        [
            smooth("rev.size", "Rev Size", 0, 100, 50, Fmt.pct),
            smooth("rev.decay", "Rev Decay", 0.1, 20, 2, exp: true) { v in String(format: "%.1fs", v) },
            smooth("rev.tone", "Rev Tone", -100, 100, 0, bipolar: true) { v in
                let r = Int(v.rounded())
                return r > 0 ? "+\(r)" : "\(r)"
            },
            smooth("rev.hpf", "Rev Low Cut", 20, 2000, 20, exp: true, Fmt.hz),
        ],
        [
            stepped("dly.time", "Dly Time", delayDivs.map { $0.name }, def: 5),
            smooth("dly.feedback", "Dly Feedback", 0, 100, 40, Fmt.pct),
            smooth("dly.filter", "Dly Filter", -100, 100, 0, bipolar: true) { v in
                let f = delayFilterFreq(v)
                return f.type == 0 ? "OFF" : "\(f.type < 0 ? "LP" : "HP") \(Fmt.hz(f.hz))"
            },
            smooth("dly.spread", "Dly Spread", 0, 100, 0, Fmt.pct),
        ],
        [
            smooth("od.drive", "Drive", 0, 100, 26, Fmt.pct),
            stepped("od.type", "Drive Type", ["Soft", "Hard", "Tube", "Fuzz", "Fold", "Crush"]),
            smooth("od.tone", "Drive Tone", 0, 100, 50, Fmt.pct),
            smooth("od.lowcut", "Drive Low Cut", 20, 1000, 20, exp: true) { v in v <= driveLowCutOff ? "OFF" : Fmt.hz(v) },
        ],
        [
            smooth("sc.attack", "SC Attack", 0.1, 100, 5, exp: true, Fmt.ms),
            smooth("sc.release", "SC Release", 10, 1000, 150, exp: true, Fmt.ms),
            stepped("sc.source", "SC Source", (0..<maxTracks).map { "\($0 + 1)" }),
            smooth("sc.curve", "SC Curve", 0, 100, 50, Fmt.pct),
        ],
    ]

    /// Сетка FX 4×4 ряд за рядом.
    public static let fxGrid: [ParamDef] = (0..<16).map { i in fxColumns[i % 4][i / 4] }
    /// Без ручки: дополнительная пред-задержка реверба (p-lock и MIDI по ключу работают).
    public static let hiddenFx: [ParamDef] = [smooth("rev.predelay", "Rev Predelay", 0, 200, 0, Fmt.ms)]
    /// Порядок FX в снимках для колбэка: сетка (ряд за рядом), затем пред-задержка.
    public static let fxIds: [String] = (fxGrid + hiddenFx).map { $0.id }
    public static let fxCount = 17

    /// FX нового проекта (LOW CUT реверба 120 Гц, Drive 80 Гц).
    public static func fxDefaults() -> [String: Double] {
        var d: [String: Double] = [:]
        for p in fxGrid + hiddenFx { d[p.id] = p.def }
        d["rev.hpf"] = revHpfNew
        d["od.lowcut"] = driveLowCutNew
        return d
    }

    public static let byId: [String: ParamDef] = {
        var d: [String: ParamDef] = [:]
        for p in trackGrid + synthColumn + modGrid + fxGrid + hiddenFx { d[p.id] = p }
        return d
    }()

    public static func defaults() -> [String: Double] {
        var d: [String: Double] = [:]
        for p in trackGrid + synthColumn + modGrid { d[p.id] = p.def }
        return d
    }
}
