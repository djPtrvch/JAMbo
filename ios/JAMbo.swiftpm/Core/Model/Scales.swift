// Гаммы, части аккордов, ноты клавиатуры и аккорды (как SCALES, PROGRESSIONS, scaleNotes, chordOnDegree в вебе).

public struct Scale: Sendable {
    public let name: String
    public let short: String
    public let steps: [Int]
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

    /// Части аккорда строки под клавишами (CHORD; выбираются в любом сочетании, бит k — пункт k).
    public static let chordParts: [String] = ["TRIAD", "7th", "9th"]

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

    /// Верхняя октава клавиатуры, при которой самая высокая нота (с CHORD — верх аккорда с частями parts верхней
    /// клавиши) не выше 127: выше пианоролл её не показывает и MIDI не отправляет.
    public static func topOctave(scale: Int, root: Int, octaves: Int, chord: Bool, parts: Int = 1) -> Int {
        let span: Int = chord ? chordSpan(parts) : 0
        let last: Int = keyCount(scale: scale, octaves: octaves) - 1 + span
        var o: Int = octaveMax
        while o > octaveMin && note(scale: scale, root: root, octave: o, degree: last) > 127 { o -= 1 }
        return o
    }

    /// Аккорд от ступени degree (ноты гаммы через одну): основной тон и части по маске parts — бит 0 TRIAD (терция
    /// и квинта), бит 1 7th (септима), бит 2 9th (нона); сочетания любые (TRIAD + 9th — add9, 7th + 9th без TRIAD…).
    public static func chord(scale: Int, root: Int, octave: Int, degree: Int, parts: Int = 1) -> [Int] {
        var offsets: [Int] = [0]
        if parts & 1 != 0 { offsets += [2, 4] }
        if parts & 2 != 0 { offsets.append(6) }
        if parts & 4 != 0 { offsets.append(8) }
        return offsets.map { note(scale: scale, root: root, octave: octave, degree: degree + $0) }
    }

    /// Ступеней гаммы от основного тона до верхней ноты аккорда с маской parts.
    public static func chordSpan(_ parts: Int) -> Int {
        if parts & 4 != 0 { return 8 }
        if parts & 2 != 0 { return 6 }
        return parts & 1 != 0 ? 4 : 0
    }
}
