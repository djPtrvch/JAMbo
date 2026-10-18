// Правки нот из пианоролла (S8d): шаг index (p·16 + s) открытого клипа, нота — по высоте.

extension Track {
    /// Поставить ноту на шаг (шаг без трига — триг только с этой нотой; p-lock и свой звук шага остаются).
    public mutating func addRollNote(_ index: Int, pitch: Int, len: Int, vel: Double?) {
        withStep(index) { s in
            if !s.on {
                s.notes = []
                s.lens = nil
                s.vels = nil
                s.on = true
            }
            if s.notes.count >= SeqData.maxNotes && !s.notes.contains(pitch) { return }
            s.addNote(pitch, len: len, vel: vel)
        }
    }

    public mutating func removeRollNote(_ index: Int, pitch: Int) {
        withStep(index) { s in
            guard let k = s.notes.firstIndex(of: pitch) else { return }
            s.removeNote(k)
        }
    }

    public mutating func setRollNoteLen(_ index: Int, pitch: Int, len: Int) {
        withStep(index) { s in
            guard let k = s.notes.firstIndex(of: pitch) else { return }
            s.setNoteLen(k, len)
        }
    }

    /// Перенести ноту (с её длиной и velocity) на другой шаг и высоту; p-lock и звук шагов остаются на месте.
    public mutating func moveRollNote(_ index: Int, pitch: Int, to dest: Int, pitch dp: Int) {
        guard let s = step(index), let k = s.notes.firstIndex(of: pitch) else { return }
        if index == dest && pitch == dp { return }
        let len: Int = s.noteLen(k)
        let vel: Double? = s.noteVel(k)
        removeRollNote(index, pitch: pitch)
        addRollNote(dest, pitch: dp, len: len, vel: vel)
    }
}

extension Roll {
    /// Позиция n в начало клетки сетки (GRID шагов).
    public static func snap(_ n: Int, grid: Int) -> Int {
        let g: Int = Swift.max(1, grid)
        return (n / g) * g
    }

    /// Длина по сетке: кратна GRID, не меньше 1, не дальше конца прохода (cols − pos).
    public static func snapLen(steps: Double, grid: Int, pos: Int, cols: Int) -> Int {
        let g: Double = Double(Swift.max(1, grid))
        var n: Int = Int((steps / g).rounded()) * Int(g)
        if n < 1 { n = Int(g) }
        return Swift.max(1, Swift.min(n, cols - pos))
    }
}
