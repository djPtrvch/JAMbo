// Гаммы, виды и варианты аккордов, ноты клавиатуры и аккорды (как SCALES, PROGRESSIONS, scaleNotes, chordOnDegree в вебе).

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

    /// Типы аккорда (CHORD; выбирается один в окне долгого нажатия на CHORD; имя — и подпись под CHORD): ступени гаммы от ступени клавиши d —
    /// Triad d, d+2, d+4; 7th + d+6; 9th + d+6, d+8; sus2 d, d+1, d+4; sus4 d, d+3, d+4; add9 d, d+2, d+4, d+8.
    /// Все ноты — в гамме.
    public static let chordKinds: [String] = ["Triad", "7th", "9th", "Sus2", "Sus4", "Add9"]
    public static let chordDegrees: [[Int]] = [[0, 2, 4], [0, 2, 4, 6], [0, 2, 4, 6, 8], [0, 1, 4], [0, 3, 4], [0, 2, 4, 8]]

    /// Октава клавиатуры: 0…7, по умолчанию 3 (C3 — сэмпл в исходной высоте и первый маркер нарезки; решение пользователя
    /// 3.11, прежде 2).
    public static let octaveMin = 0
    public static let octaveMax = 7
    public static let octaveDef = 3
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
    public static func topOctave(scale: Int, root: Int, octaves: Int, chord: Bool, kind: Int = 0) -> Int {
        let last: Int = keyCount(scale: scale, octaves: octaves) - 1
        var o: Int = octaveMax
        while o > octaveMin {
            let top: Int = chord
                ? (chordRaw(scale: scale, root: root, octave: o, degree: last, kind: kind).max() ?? 0)
                : note(scale: scale, root: root, octave: o, degree: last)
            if top <= 127 { break }
            o -= 1
        }
        return o
    }

    /// Аккорд ступени degree типа kind (chordDegrees) — ноты гаммы вверх от ноты ступени, без переноса.
    static func chordRaw(scale: Int, root: Int, octave: Int, degree: Int, kind: Int) -> [Int] {
        let ds: [Int] = chordDegrees[min(chordDegrees.count - 1, max(0, kind))]
        return ds.map { note(scale: scale, root: root, octave: octave, degree: degree + $0) }
    }

    /// Аккорд клавиши: ступень degree, тип kind. Нота выше 127 (верх MIDI и движков) — на октаву ниже.
    public static func chord(scale: Int, root: Int, octave: Int, degree: Int, kind: Int = 0) -> [Int] {
        return chordRaw(scale: scale, root: root, octave: octave, degree: degree, kind: kind).map { n in
            var m: Int = n
            while m > 127 { m -= 12 }
            return m
        }
    }
}
