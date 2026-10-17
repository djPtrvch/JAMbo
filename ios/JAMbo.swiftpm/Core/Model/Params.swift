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
    /// Подпись у синта (ручки 1.1–1.3 — позже по таблице движков).
    public let alt: String?
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
    public let format: (Double) -> String

    public init(id: String, label: String, alt: String? = nil, kind: KnobKind = .smooth, min: Double, max: Double, def: Double,
                curve: Double? = nil, exp: Bool = false, bipolar: Bool = false, options: [String] = [],
                format: @escaping (Double) -> String) {
        self.id = id
        self.label = label
        self.alt = alt
        self.kind = kind
        self.min = min
        self.max = max
        self.def = def
        self.curve = curve
        self.exp = exp
        self.bipolar = bipolar
        self.options = options
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
                               alt: String? = nil, curve: Double? = nil, bipolar: Bool = false,
                               _ format: @escaping (Double) -> String) -> ParamDef {
        return ParamDef(id: id, label: label, alt: alt, min: min, max: max, def: def, curve: curve, bipolar: bipolar, format: format)
    }

    private static func stepped(_ id: String, _ label: String, _ options: [String], def: Double = 0) -> ParamDef {
        let opts = options
        return ParamDef(id: id, label: label, kind: .stepped, min: 0, max: Double(options.count - 1), def: def, options: options) { v in
            let i = Int(v.rounded())
            return i >= 0 && i < opts.count ? opts[i] : ""
        }
    }

    /// Колонки сетки ручек дорожки (колонка 1 — сэмпл, 2 — огибающая и фильтр, 3 — посылы, 4 — Pan, Chance, Ratchet, Swing).
    public static let trackColumns: [[ParamDef]] = [
        [
            smooth("pitch", "Pitch", -24, 24, 0, alt: "Harmonics", bipolar: true, Fmt.pitch),
            smooth("start", "Start", 0, 100, 0, alt: "Timbre", Fmt.pct),
            smooth("end", "End", 0, 100, 100, alt: "Morph", Fmt.pct),
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

    public static let byId: [String: ParamDef] = {
        var d: [String: ParamDef] = [:]
        for p in trackGrid { d[p.id] = p }
        return d
    }()

    public static func defaults() -> [String: Double] {
        var d: [String: Double] = [:]
        for p in trackGrid { d[p.id] = p.def }
        return d
    }
}
