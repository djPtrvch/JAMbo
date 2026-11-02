// Гаммы, виды и варианты аккордов, ноты клавиатуры и аккорды (как SCALES, PROGRESSIONS, scaleNotes, chordOnDegree в вебе).

public struct Scale: Sendable {
    public let name: String
    public let short: String
    public let steps: [Int]
}

public struct ChordVariant: Sendable {
    public let name: String
    /// Полутоны от ноты клавиши; пусто — по гамме.
    public let intervals: [Int]

    public init(_ name: String, _ intervals: [Int]) {
        self.name = name
        self.intervals = intervals
    }
}

public enum Scales {
    public static let all: [Scale] = [
        Scale(name: "Major", short: "Maj", steps: [0, 2, 4, 5, 7, 9, 11]),
        Scale(name: "Minor", short: "Min", steps: [0, 2, 3, 5, 7, 8, 10]),
        Scale(name: "Dorian", short: "Dor", steps: [0, 2, 3, 5, 7, 9, 10]),
        Scale(name: "Phrygian", short: "Phr", steps: [0, 1, 3, 5, 7, 8, 10]),
        Scale(name: "Lydian", short: "Lyd", steps: [0, 2, 4, 6, 7, 9, 11]),
        Scale(name: "Mixolydian", short: "Mix", steps: [0, 2, 4, 5, 7, 9, 10]),
        Scale(name: "Locrian", short: "Loc", steps: [0, 1, 3, 5, 6, 8, 10]),
        Scale(name: "Harm Minor", short: "HMin", steps: [0, 2, 3, 5, 7, 8, 11]),
        Scale(name: "Pent Major", short: "PMaj", steps: [0, 2, 4, 7, 9]),
        Scale(name: "Pent Minor", short: "PMin", steps: [0, 3, 5, 7, 10]),
        Scale(name: "Chromatic", short: "Chr", steps: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
    ]

    /// Виды аккорда строки под клавишами (CHORD; выбирается один): базовые трезвучия, септаккорды, расширенные.
    public static let chordKinds: [String] = ["TRIAD", "7th", "9th"]

    /// Варианты каждого вида (поле VARIANT): SCALE — по гамме, остальные — интервалы в полутонах от ноты клавиши.
    public static let chordVariants: [[ChordVariant]] = [
        [ChordVariant("Scale", []), ChordVariant("Maj", [0, 4, 7]), ChordVariant("Min", [0, 3, 7]),
         ChordVariant("Dim", [0, 3, 6]), ChordVariant("Aug", [0, 4, 8]), ChordVariant("Sus2", [0, 2, 7]),
         ChordVariant("Sus4", [0, 5, 7])],
        [ChordVariant("Scale", []), ChordVariant("Maj7", [0, 4, 7, 11]), ChordVariant("7", [0, 4, 7, 10]),
         ChordVariant("m7", [0, 3, 7, 10]), ChordVariant("m7b5", [0, 3, 6, 10]), ChordVariant("dim7", [0, 3, 6, 9]),
         ChordVariant("mMaj7", [0, 3, 7, 11]), ChordVariant("7sus4", [0, 5, 7, 10])],
        [ChordVariant("Scale", []), ChordVariant("Maj9", [0, 4, 7, 11, 14]), ChordVariant("9", [0, 4, 7, 10, 14]),
         ChordVariant("m9", [0, 3, 7, 10, 14]), ChordVariant("add9", [0, 4, 7, 14]), ChordVariant("m(add9)", [0, 3, 7, 14]),
         ChordVariant("7b9", [0, 4, 7, 10, 13]), ChordVariant("7#9", [0, 4, 7, 10, 15])],
    ]

    /// Октава клавиатуры: 0…7, по умолчанию 2 (C2).
    public static let octaveMin = 0
    public static let octaveMax = 7
    public static let octaveDef = 2
    /// Клавиш самое большее (две октавы хроматики + 1).
    public static let maxKeys = 25

    public static func wrap(_ v: Int, _ n: Int) -> Int {
        return ((v % n) + n) % n
    }

    /// Нижняя нота клавиатуры: корневая нота октавы.
    public static func baseNote(root: Int, octave: Int) -> Int {
        return 12 * (octave + 1) + root
    }

    /// Нота гаммы на ступени k от базовой (k может уходить в следующие октавы).
    public static func note(scale: Int, root: Int, octave: Int, degree k: Int) -> Int {
        let steps = all[wrap(scale, all.count)].steps
        let n = steps.count
        let oct = Int((Double(k) / Double(n)).rounded(.down))
        return baseNote(root: root, octave: octave) + 12 * oct + steps[wrap(k, n)]
    }

    /// Клавиш на экране: одна или две октавы гаммы + верхняя корневая нота.
    public static func keyCount(scale: Int, octaves: Int) -> Int {
        return min(maxKeys, all[wrap(scale, all.count)].steps.count * octaves + 1)
    }

    /// Верхняя октава клавиатуры, при которой самая высокая нота (с CHORD — верх аккорда верхней клавиши) не выше
    /// 127: выше пианоролл её не показывает и MIDI не отправляет.
    public static func topOctave(scale: Int, root: Int, octaves: Int, chord: Bool, kind: Int = 0, variant: Int = 0) -> Int {
        let last: Int = keyCount(scale: scale, octaves: octaves) - 1
        var o: Int = octaveMax
        while o > octaveMin {
            let top: Int = chord
                ? (Scales.chord(scale: scale, root: root, octave: o, degree: last, kind: kind, variant: variant).max() ?? 0)
                : note(scale: scale, root: root, octave: o, degree: last)
            if top <= 127 { break }
            o -= 1
        }
        return o
    }

    /// Аккорд клавиши: ступень degree, вид kind (TRIAD, 7th, 9th) и вариант variant (chordVariants[kind]). Вариант 0
    /// SCALE — ноты гаммы через одну (3, 4 или 5 нот); остальные — свои интервалы от ноты клавиши (одинаковые на всех
    /// клавишах, мимо гаммы).
    public static func chord(scale: Int, root: Int, octave: Int, degree: Int, kind: Int = 0, variant: Int = 0) -> [Int] {
        let kd: Int = min(chordKinds.count - 1, max(0, kind))
        let vs: [ChordVariant] = chordVariants[kd]
        let v: ChordVariant = vs[min(vs.count - 1, max(0, variant))]
        let base: Int = note(scale: scale, root: root, octave: octave, degree: degree)
        if !v.intervals.isEmpty { return v.intervals.map { base + $0 } }
        var out: [Int] = []
        var i: Int = 0
        while i < 3 + kd {
            out.append(note(scale: scale, root: root, octave: octave, degree: degree + 2 * i))
            i += 1
        }
        return out
    }
}
