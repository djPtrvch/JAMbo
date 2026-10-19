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
    /// Пункты ступенчатой ручки с непрерывным значением (WAVE у ANALOG): значение — середина
    /// пункта на min…max (как steps в params.ts веба).
    public let steps: Int?
    /// Шаг значения (0,1 dB у мастера).
    public let step: Double?
    /// Последняя доля хода — AUTO (значение MasterChain.autoValue); шкала до неё — как обычно.
    public let autoTop: Double?
    /// Первая доля хода — OFF (значение 0); шкала после неё — как обычно.
    public let offBottom: Double?
    /// P-lock на ручку не ставится (ручки мастера): с зажатым шагом крутится само значение.
    public let noLock: Bool
    public let format: (Double) -> String

    public init(id: String, label: String, kind: KnobKind = .smooth, min: Double, max: Double, def: Double,
                curve: Double? = nil, exp: Bool = false, bipolar: Bool = false, options: [String] = [], steps: Int? = nil,
                step: Double? = nil, autoTop: Double? = nil, offBottom: Double? = nil, noLock: Bool = false,
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
        self.step = step
        self.autoTop = autoTop
        self.offBottom = offBottom
        self.noLock = noLock
        self.format = format
    }

    /// Та же шкала без AUTO, OFF и шага (как { ...p, autoTop: undefined } веба).
    private var plain: ParamDef {
        return ParamDef(id: id, label: label, kind: kind, min: min, max: max, def: def, curve: curve, exp: exp,
                        bipolar: bipolar, options: options, steps: steps, format: format)
    }

    /// Значение → положение ручки 0…1.
    public func toNorm(_ v: Double) -> Double {
        if let o = offBottom { return v <= 0 ? 0 : o + (1 - o) * plain.toNorm(Swift.max(min, v)) }
        if let a = autoTop { return v >= MasterChain.autoValue ? 1 : (1 - a) * plain.toNorm(Swift.min(max, v)) }
        if exp { return log(v / min) / log(max / min) }
        let lin: Double = Swift.min(1, Swift.max(0, (v - min) / (max - min)))
        if let c = curve { return pow(lin, 1 / c) }
        return lin
    }

    /// Положение ручки 0…1 → значение (ступенчатые округляются).
    public func fromNorm(_ n0: Double) -> Double {
        let n: Double = Swift.min(1, Swift.max(0, n0))
        if let o = offBottom { return n < o ? 0 : plain.fromNorm((n - o) / (1 - o)) }
        if let a = autoTop { return n >= 1 - a ? MasterChain.autoValue : plain.fromNorm(n / (1 - a)) }
        if let st = step { return (plain.fromNorm(n) / st).rounded() * st }
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
    /// Дорожка ручки громкости MIX по id (mix.vol1 → 0), иначе nil.
    public static func mixTrack(_ id: String) -> Int? {
        guard id.hasPrefix("mix.vol"), let n = Int(id.dropFirst(7)), n >= 1 && n <= 16 else { return nil }
        return n - 1
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

    /// Пустая ячейка сетки (id ""): неактивная серая ручка.
    public static let empty = ParamDef(id: "", label: "", min: 0, max: 1, def: 0) { _ in "" }

    /// Swing дорожки (S12): не на сетке — ползунок в меню клавиатуры; без p-lock и LFO/ENV.
    public static let swing = ParamDef(id: "swing", label: "Swing", min: 50, max: 75, def: 50, format: Fmt.pct)

    /// Колонки сетки ручек дорожки сэмплера (у синта колонка 1 — synthGrids; колонка 1 — сэмпл, 2 — огибающая и фильтр,
    /// 3 — посылы, 4 — Pan, Chance, Ratchet, Velocity). 1.4 у сэмпла пока пустая (S12).
    public static let trackColumns: [[ParamDef]] = [
        [
            smooth("pitch", "Pitch", -24, 24, 0, bipolar: true, Fmt.pitch),
            smooth("start", "Start", 0, 100, 0, Fmt.pct),
            smooth("end", "End", 0, 100, 100, Fmt.pct),
            empty,
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
            // Velocity (S12; прежний Level, id тот же): множитель уровня нот дорожки, на ручке — проценты, хранится 0…127.
            smooth("level", "Velocity", 0, 127, 127) { v in "\(Int((v / 127 * 100).rounded()))%" },
        ],
    ]

    /// Сетка 4×4 ряд за рядом (индекс = ряд·4 + столбец).
    public static let trackGrid: [ParamDef] = (0..<16).map { i in trackColumns[i % 4][i / 4] }

    /// Колонка 1 синта (вместо Pitch, Start, End): Harmonics, Timbre, Morph — 0…100 %, по умолчанию 50 (SYNTH_GRID).
    public static let synthColumn: [ParamDef] = [
        smooth("harm", "Harmonics", 0, 100, 50, Fmt.pct),
        smooth("timbre", "Timbre", 0, 100, 50, Fmt.pct),
        smooth("morph", "Morph", 0, 100, 50, Fmt.pct),
        smooth("p4", "Knob 4", 0, 100, 50, Fmt.pct),
    ]

    /// Пункт ступенчатой ручки по положению 0…1.
    public static func stepIndex(_ n: Double, _ steps: Int) -> Int {
        return Swift.min(steps - 1, Swift.max(0, Int((n * Double(steps)).rounded(.down))))
    }

    /// Сетка синта по номеру движка (ENGINE_GRIDS): подписи 1.1–1.4 из таблицы движков, ступенчатые — по пунктам
    /// движка (значение — середина пункта); у незанятого номера — пустая.
    public static let synthGrids: [[ParamDef]] = SynthEngines.byId.map { eo in
        guard let e = eo else { return [] }
        let col: [ParamDef] = synthColumn.enumerated().map { k, p in
            let label = SynthEngines.capitalized(e.knobs[k])
            let o: [String] = e.options[k]
            if !o.isEmpty {
                return ParamDef(id: p.id, label: label, kind: .stepped, min: p.min, max: p.max, def: p.def,
                                steps: o.count) { v in o[stepIndex(v / 100, o.count)] }
            }
            // Свой формат: PITCH у KICK — Гц, RATIO у FM — ×2.00, DETUNE у WTABLE — центы.
            if k == 0 && e.id == Jambo.drum {
                return ParamDef(id: p.id, label: label, min: p.min, max: p.max, def: p.def) { v in
                    "\(Int(Jambo.drumPitch(v / 100).rounded())) Hz"
                }
            }
            if k == 0 && e.id == Jambo.fm {
                return ParamDef(id: p.id, label: label, min: p.min, max: p.max, def: p.def) { v in
                    "×" + String(format: "%.2f", Jambo.fmRatio(v / 100))
                }
            }
            if k == 3 && e.id == Jambo.wtable {
                return ParamDef(id: p.id, label: label, min: p.min, max: p.max, def: p.def) { v in
                    "\(Int((v / 100 * Jambo.wtDetune).rounded())) ct"
                }
            }
            return ParamDef(id: p.id, label: label, min: p.min, max: p.max, def: p.def, format: p.format)
        }
        return (0..<16).map { i in
            if i % 4 == 0 { return col[i / 4] }
            let p = trackGrid[i]
            // Свой предел Decay (у KICK — 1000 мс).
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
            // По умолчанию 40 % (решение пользователя, в вебе — 50).
            smooth("rev.size", "Rev Size", 0, 100, 40, Fmt.pct),
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

    // MARK: — Мастер (MST, MASTER_GRID веба): колонки SAT, COMP, CLIP, LIM; без p-lock

    /// dB мастера: знак «+» выше нуля, единица — второй строкой.
    static func masterDb(_ v: Double) -> String {
        return (v > 0.04 ? "+" : "") + String(format: "%.1f\ndB", v)
    }

    static func masterMs(_ v: Double) -> String {
        if v >= MasterChain.autoValue { return "AUTO" }
        if v >= 1000 { return String(format: "%.1f s", v / 1000) }
        if v < 10 { return String(format: "%.1f ms", v) }
        return "\(Int(v.rounded())) ms"
    }

    private static func master(_ id: String, _ label: String, _ min: Double, _ max: Double, _ def: Double,
                               exp: Bool = false, step: Double? = nil, autoTop: Double? = nil, offBottom: Double? = nil,
                               _ format: @escaping (Double) -> String) -> ParamDef {
        return ParamDef(id: id, label: label, min: min, max: max, def: def, exp: exp, step: step, autoTop: autoTop,
                        offBottom: offBottom, noLock: true, format: format)
    }

    public static let satTypes = ["TAPE", "TUBE", "EDGE"]

    public static let masterColumns: [[ParamDef]] = [
        [
            master("sat.drive", "Drive", 0, 24, 0, step: 0.1, masterDb),
            ParamDef(id: "sat.type", label: "Type", kind: .stepped, min: 0, max: 2, def: 0, options: satTypes,
                     noLock: true) { v in satTypes[Swift.min(2, Swift.max(0, Int(v.rounded())))] },
            master("sat.tone", "Tone", -100, 100, 0) { v in masterDb(v / 100 * 6) },
            master("sat.mix", "Mix", 0, 100, 100, Fmt.pct),
        ],
        [
            master("cmp.threshold", "Threshold", -40, 0, -10, step: 0.1, masterDb),
            master("cmp.attack", "Attack", 0.1, 100, MasterChain.newAttack, exp: true, masterMs),
            master("cmp.release", "Release", 20, 2000, 400, exp: true, autoTop: 0.08, masterMs),
            master("cmp.makeup", "Makeup", 0, 18, 0, step: 0.1, masterDb),
        ],
        [
            master("clip.drive", "Input", 0, 12, 0, step: 0.1, masterDb),
            master("clip.ceiling", "Ceiling", -12, 0, -1, step: 0.1, masterDb),
            master("clip.softness", "Softness", 0, 100, 30, Fmt.pct),
            master("clip.bass", "Bass", 20, 300, 0, exp: true, offBottom: 0.05) { v in
                v <= 0 ? "OFF" : "\(Int(v.rounded())) Hz"
            },
        ],
        [
            master("lim.input", "Input", 0, 24, 0, step: 0.1, masterDb),
            master("lim.ceiling", "Ceiling", -24, 0, -1, step: 0.1, masterDb),
            master("lim.lookahead", "Lookahead", 0.5, 6, 3) { v in String(format: "%.1f ms", v) },
            master("lim.release", "Release", 10, 1000, 150, exp: true, autoTop: 0.08, masterMs),
        ],
    ]

    /// Частота окна модуля мастера: «OFF» у нижнего края (FOCUS, SC HPF — 20 Hz), иначе Hz или kHz.
    static func masterHz(_ v: Double) -> String {
        if v <= 20.5 { return "OFF" }
        if v >= 1000 { return String(format: "%.2f kHz", v / 1000) }
        return "\(Int(v.rounded())) Hz"
    }

    /// Параметры окон модулей мастера без ручек (MASTER_EXTRA веба без убранных в S5a): только поля окна и пресеты,
    /// p-lock и LFO/ENV не принимают.
    public static let masterExtra: [ParamDef] = [
        master("sat.focus", "Focus", 20, 2000, 20, exp: true, masterHz),
        master("cmp.ratio", "Ratio", 1, 20, 2, exp: true, step: 0.01) { v in
            v < 9.95 ? String(format: "%.1f:1", v) : "\(Int(v.rounded())):1"
        },
        master("cmp.knee", "Knee", 0, 24, 6, step: 0.1) { v in String(format: "%.1f dB", v) },
        master("cmp.mix", "Mix", 0, 100, 100, Fmt.pct),
        master("cmp.schpf", "SC HPF", 20, 500, 90, exp: true, masterHz),
    ]

    /// Сетка MST 4×4 ряд за рядом.
    public static let masterGrid: [ParamDef] = (0..<16).map { i in masterColumns[i % 4][i / 4] }

    public static let byId: [String: ParamDef] = {
        var d: [String: ParamDef] = [:]
        for p in trackGrid + synthColumn + modGrid + fxGrid + hiddenFx + masterGrid + masterExtra where !p.id.isEmpty { d[p.id] = p }
        return d
    }()

    public static func defaults() -> [String: Double] {
        var d: [String: Double] = [:]
        for p in trackGrid + synthColumn + modGrid + [swing] where !p.id.isEmpty { d[p.id] = p.def }
        return d
    }
}
