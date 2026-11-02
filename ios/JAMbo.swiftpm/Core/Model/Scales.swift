// Гаммы, виды аккордов, ноты клавиатуры и аккорды (как SCALES, PROGRESSIONS, scaleNotes, chordOnDegree в вебе).

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

    /// Виды аккорда строки под клавишами (CHORD): трезвучие, септаккорд, нонаккорд — ноты гаммы через одну.
    public static let chordTypes: [String] = ["TRIAD", "7", "9"]

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

    /// Верхняя октава клавиатуры, при которой самая высокая нота (с CHORD — верх аккорда вида type верхней клавиши)
    /// не выше 127: выше пианоролл её не показывает и MIDI не отправляет.
    public static func topOctave(scale: Int, root: Int, octaves: Int, chord: Bool, type: Int = 0) -> Int {
        let span: Int = chord ? 4 + 2 * min(2, max(0, type)) : 0
        let last: Int = keyCount(scale: scale, octaves: octaves) - 1 + span
        var o: Int = octaveMax
        while o > octaveMin && note(scale: scale, root: root, octave: o, degree: last) > 127 { o -= 1 }
        return o
    }

    /// Аккорд от ступени degree (ноты гаммы через одну): type 0 — трезвучие, 1 — септаккорд, 2 — нонаккорд.
    public static func chord(scale: Int, root: Int, octave: Int, degree: Int, type: Int = 0) -> [Int] {
        let count: Int = 3 + min(2, max(0, type))
        var out: [Int] = []
        var i: Int = 0
        while i < count {
            out.append(note(scale: scale, root: root, octave: octave, degree: degree + 2 * i))
            i += 1
        }
        return out
    }

    /// Название аккорда ступени: C, Am, Bdim, Caug; с 7 — Cmaj7, Am7, G7, Bm7b5, Bdim7; с 9 — Cmaj9, Am9, G9, Em7b9.
    public static func chordName(scale: Int, root: Int, octave: Int, degree: Int, type: Int = 0) -> String {
        let c: [Int] = chord(scale: scale, root: root, octave: octave, degree: degree, type: type)
        let third: Int = c[1] - c[0]
        let fifth: Int = c[2] - c[0]
        let q: String = fifth == 6 ? "dim" : fifth == 8 ? "aug" : third == 3 ? "m" : ""
        let name: String = Params.noteNames[wrap(c[0], 12)]
        if c.count < 4 { return name + q }
        let seventh: Int = c[3] - c[0]
        var ext: String = "7"
        if c.count > 4 && c[4] - c[0] == 14 { ext = "9" }
        let tail: String = c.count > 4 && ext == "7" ? (c[4] - c[0] == 13 ? "b9" : c[4] - c[0] == 15 ? "#9" : "") : ""
        var body: String
        switch q {
        case "dim": body = seventh == 9 ? "dim" + ext : "m" + ext + "b5"
        case "m": body = seventh == 11 ? "mMaj" + ext : "m" + ext
        case "aug": body = seventh == 11 ? "augMaj" + ext : "aug" + ext
        default: body = seventh == 11 ? "maj" + ext : ext
        }
        body += tail
        return name + body
    }
}
