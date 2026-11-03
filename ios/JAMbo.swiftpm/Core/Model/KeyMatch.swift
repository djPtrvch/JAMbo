import Foundation

// Близость тональностей по квинтовому кругу (решение пользователя 3.11): в списке PROJECTS тональность проекта
// окрашена по тому, насколько она подходит к тональности открытого проекта.

public enum KeyMatch {
    /// Мажорные тональности (тоника 0…11), ноты которых больше всего совпадают с нотами гаммы scale от root
    /// (у ладов — свой мажор: E Phrygian → C; у пентатоник — несколько).
    public static func majors(scale: Int, root: Int) -> [Int] {
        let s: Scale = Scales.all[Scales.wrap(scale, Scales.all.count)]
        let r: Int = ((root % 12) + 12) % 12
        var pcs: Set<Int> = []
        for st in s.steps { pcs.insert((r + st) % 12) }
        let major: [Int] = Scales.all[0].steps
        var best: Int = -1
        var out: [Int] = []
        for k in 0..<12 {
            var n: Int = 0
            for st in major where pcs.contains((k + st) % 12) { n += 1 }
            if n > best {
                best = n
                out = [k]
            } else if n == best {
                out.append(k)
            }
        }
        return out
    }

    /// Шагов по квинтовому кругу между тональностями (0…6); nil — у одной из гамм тональности нет (Chromatic).
    public static func distance(scale a: Int, root ra: Int, scale b: Int, root rb: Int) -> Int? {
        let ma: [Int] = majors(scale: a, root: ra)
        let mb: [Int] = majors(scale: b, root: rb)
        // Chromatic подходит ко всем двенадцати — тональности нет.
        if ma.count == 12 || mb.count == 12 { return nil }
        var best: Int = 6
        for x in ma {
            for y in mb {
                let d: Int = (((y - x) * 7) % 12 + 12) % 12
                best = Swift.min(best, Swift.min(d, 12 - d))
            }
        }
        return best
    }

    /// Степень: 0 — ближайшие (та же или соседняя на круге), 1 — менее близкие (2–3 шага), 2 — далёкие (4–6).
    public static func grade(_ d: Int) -> Int {
        return d <= 1 ? 0 : (d <= 3 ? 1 : 2)
    }
}
