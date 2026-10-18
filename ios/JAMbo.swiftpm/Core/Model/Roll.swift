// Пианоролл (S8): строки — ноты гаммы, столбцы — шаги прохода по выбранным страницам клипа, ноты клипа.

/// Нота на пианоролле: позиция в проходе, шаг клипа (p·16 + s), номер ноты в шаге, высота, длина, velocity.
public struct RollNote: Equatable, Sendable {
    public let pos: Int
    public let index: Int
    public let k: Int
    public let pitch: Int
    public let len: Int
    public let vel: Double?
}

public enum Roll {
    /// GRID: шагов в клетке сетки (1/16, 1/8, 1/4).
    public static let grids: [Int] = [1, 2, 4]
    public static let gridNames: [String] = ["1/16", "1/8", "1/4"]
    public static let gridDef = 1

    /// Ноты гаммы 0…127 снизу вверх.
    public static func rows(scale: Int, root: Int) -> [Int] {
        let steps: [Int] = Scales.all[Scales.wrap(scale, Scales.all.count)].steps
        var out: [Int] = []
        for n in 0...127 where steps.contains(Scales.wrap(n - root, 12)) { out.append(n) }
        return out
    }

    /// Диез (чёрная клавиша).
    public static func isSharp(_ n: Int) -> Bool {
        let c: Int = Scales.wrap(n, 12)
        return c == 1 || c == 3 || c == 6 || c == 8 || c == 10
    }

    public static func isRoot(_ n: Int, root: Int) -> Bool {
        return Scales.wrap(n - root, 12) == 0
    }

    /// Шаг клипа на каждой позиции прохода (выбранные страницы подряд, без шагов за длиной).
    public static func positions(_ clip: Clip) -> [Int] {
        let n: Int = clip.playLen
        var out: [Int] = []
        out.reserveCapacity(n)
        for i in 0..<n { out.append(clip.playIndex(i)) }
        return out
    }

    /// Ноты прохода по порядку позиций.
    public static func notes(_ clip: Clip) -> [RollNote] {
        var out: [RollNote] = []
        for (pos, index) in positions(clip).enumerated() {
            guard let s = clip.step(index), s.on else { continue }
            for k in 0..<s.notes.count {
                out.append(RollNote(pos: pos, index: index, k: k, pitch: s.notes[k], len: s.noteLen(k), vel: s.noteVel(k)))
            }
        }
        return out
    }

    /// Подпись доли: такт.доля (16 шагов в такте, 4 в доле), с 1.
    public static func beatLabel(_ pos: Int) -> String {
        return "\(pos / 16 + 1).\((pos % 16) / 4 + 1)"
    }
}
