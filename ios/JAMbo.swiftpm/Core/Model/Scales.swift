// Гаммы, прогрессии, ноты клавиатуры и аккорды (как SCALES, PROGRESSIONS, scaleNotes, chordOnDegree в вебе).

public struct Scale: Sendable {
    public let name: String
    public let short: String
    public let steps: [Int]
}

public struct Progression: Sendable {
    public let name: String
    /// Ступени гаммы (0 = I).
    public let degrees: [Int]
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

    public static let progressions: [Progression] = [
        Progression(name: "I–V–vi–IV", degrees: [0, 4, 5, 3]),
        Progression(name: "I–vi–IV–V", degrees: [0, 5, 3, 4]),
        Progression(name: "vi–IV–I–V", degrees: [5, 3, 0, 4]),
        Progression(name: "ii–V–I", degrees: [1, 4, 0]),
        Progression(name: "I–IV–V–IV", degrees: [0, 3, 4, 3]),
        Progression(name: "i–VII–VI–VII", degrees: [0, 6, 5, 6]),
        Progression(name: "Canon", degrees: [0, 4, 5, 2, 3, 0, 3, 4]),
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

    /// Трезвучие от ступени degree (ноты гаммы через одну).
    public static func chord(scale: Int, root: Int, octave: Int, degree: Int) -> [Int] {
        return [0, 2, 4].map { note(scale: scale, root: root, octave: octave, degree: degree + $0) }
    }

    /// Название аккорда ступени: C, Am, Bdim, Caug.
    public static func chordName(scale: Int, root: Int, octave: Int, degree: Int) -> String {
        let c = chord(scale: scale, root: root, octave: octave, degree: degree)
        let third = c[1] - c[0]
        let fifth = c[2] - c[0]
        let q: String = fifth == 6 ? "dim" : fifth == 8 ? "aug" : third == 3 ? "m" : ""
        return Params.noteNames[wrap(c[0], 12)] + q
    }
}
