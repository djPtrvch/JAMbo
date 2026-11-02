// Названия аккордов по интервалам, римские ступени и случайная прогрессия (режим CHORD, SHIFT + CHORD).

public enum Chords {
    /// Аккордов в прогрессии.
    public static let count: Int = 4

    /// Начала и длины аккордов прогрессии на выбранных страницах (pages страниц по 16 шагов): 4 аккорда поровну —
    /// одна страница — шаги 1, 5, 9, 13 по 4 шага; четыре страницы — по странице на аккорд.
    public static func places(pages: Int) -> [(start: Int, len: Int)] {
        let len: Int = Swift.max(1, pages) * Params.stepsPerPage / count
        return (0..<count).map { (start: $0 * len, len: len) }
    }

    /// Индекс ступени гаммы (0…n−1) для номера ступени (1…7; гамма короче — по модулю).
    public static func degreeIndex(_ degree: Int, scale: Int) -> Int {
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        return Scales.wrap(degree - 1, n)
    }

    private static let romans: [String] = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]

    /// Название аккорда по интервалам от нижней ноты (kind — тип, которым он построен): Em, F, B°, Cmaj7, Dm7b5, G9…
    /// Не удалось — корень и тип, например «E(sus2)».
    public static func name(_ notes: [Int], kind: Int) -> String {
        guard let root = notes.first else { return "" }
        let base: String = Params.noteNames[Scales.wrap(root, 12)]
        let iv: [Int] = notes.map { Scales.wrap($0 - root, 12) }
        if let q = quality(iv, kind: kind) { return base + q }
        let k: Int = min(Scales.chordKinds.count - 1, max(0, kind))
        return base + "(" + Scales.chordKinds[k].lowercased() + ")"
    }

    /// Суффикс названия по интервалам: позиции нот — как в Scales.chordDegrees[kind].
    static func quality(_ iv: [Int], kind: Int) -> String? {
        func at(_ i: Int) -> Int { return i < iv.count ? iv[i] : -1 }
        let triad: String? = triadName(at(1), at(2))
        switch kind {
        case 0:
            return triad
        case 1:
            return seventhName(at(1), at(2), at(3))
        case 2:
            guard let s = seventhName(at(1), at(2), at(3)) else { return nil }
            return ninthName(s, at(4))
        case 3:
            return at(1) == 2 && at(2) == 7 ? "sus2" : nil
        case 4:
            return at(1) == 5 && at(2) == 7 ? "sus4" : nil
        case 5:
            guard let t = triad, at(3) == 2 else { return nil }
            if t == "" { return "add9" }
            if t == "m" { return "m(add9)" }
            return t + "(add9)"
        default:
            return nil
        }
    }

    static func triadName(_ third: Int, _ fifth: Int) -> String? {
        switch (third, fifth) {
        case (4, 7): return ""
        case (3, 7): return "m"
        case (3, 6): return "°"
        case (4, 8): return "+"
        default: return nil
        }
    }

    static func seventhName(_ third: Int, _ fifth: Int, _ seventh: Int) -> String? {
        switch (third, fifth, seventh) {
        case (4, 7, 11): return "maj7"
        case (4, 7, 10): return "7"
        case (3, 7, 10): return "m7"
        case (3, 6, 10): return "m7b5"
        case (3, 6, 9): return "°7"
        case (3, 7, 11): return "mMaj7"
        case (4, 8, 11): return "+maj7"
        case (4, 8, 10): return "+7"
        default: return nil
        }
    }

    static func ninthName(_ seventh: String, _ ninth: Int) -> String? {
        if ninth == 2 {
            switch seventh {
            case "maj7": return "maj9"
            case "7": return "9"
            case "m7": return "m9"
            case "mMaj7": return "mMaj9"
            default: return seventh + "(9)"
            }
        }
        if ninth == 1 { return seventh + "(b9)" }
        if ninth == 3 { return seventh + "(#9)" }
        return nil
    }

    /// Римская ступень (degree — индекс в гамме, 0…n−1): большая терция или без терции — заглавные, малая — строчные;
    /// уменьшённое — «°», увеличенное — «+».
    public static func numeral(degree: Int, notes: [Int]) -> String {
        let r: String = romans[Scales.wrap(degree, romans.count)]
        guard let root = notes.first, notes.count > 2 else { return r }
        let third: Int = Scales.wrap(notes[1] - root, 12)
        let fifth: Int = Scales.wrap(notes[2] - root, 12)
        if third == 3 { return r.lowercased() + (fifth == 6 ? "°" : "") }
        return r + (third == 4 && fifth == 8 ? "+" : "")
    }

    /// Подпись клавиши в режиме CHORD: «Em · i», «F · II», «B° · v°».
    public static func keyLabel(scale: Int, root: Int, octave: Int, degree: Int, kind: Int) -> String {
        let notes: [Int] = Scales.chord(scale: scale, root: root, octave: octave, degree: degree, kind: kind)
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        return name(notes, kind: kind) + " · " + numeral(degree: Scales.wrap(degree, n), notes: notes)
    }

    /// Аккорды ступеней (номера 1…7) для гаммы, корня и октавы клавиатуры.
    public static func chords(_ degrees: [Int], scale: Int, root: Int, octave: Int, kind: Int) -> [[Int]] {
        return degrees.map { d in
            Scales.chord(scale: scale, root: root, octave: octave, degree: degreeIndex(d, scale: scale), kind: kind)
        }
    }

    /// Случайная прогрессия из 4 ступеней (номера 1…n): первая — тоника, дальше случайные ступени гаммы, без двух
    /// одинаковых подряд; не совпадает с прежней (avoid), если есть другие.
    public static func random<G: RandomNumberGenerator>(scale: Int, avoid: [Int]? = nil, using g: inout G) -> [Int] {
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let top: Int = min(7, max(2, n))
        var out: [Int] = [1]
        var tries: Int = 0
        repeat {
            out = [1]
            while out.count < 4 {
                let d: Int = Int.random(in: 1...top, using: &g)
                if d != out[out.count - 1] { out.append(d) }
            }
            tries += 1
        } while out == avoid && tries < 16
        return out
    }
}
