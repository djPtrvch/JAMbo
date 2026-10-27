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

    /// Velocity ноты (Level 0…127), связанная с p-lock Level шага (Step.setVelLinked).
    public mutating func setRollNoteVel(_ index: Int, pitch: Int, vel: Double) {
        let fallback: Double = params["level"] ?? 127
        withStep(index) { s in
            guard let k = s.notes.firstIndex(of: pitch) else { return }
            s.setVelLinked(k, vel, fallback: fallback)
        }
    }

    /// Velocity ноты для показа: своя, иначе Level шага (p-lock) или дорожки.
    public func rollNoteLevel(_ n: RollNote) -> Double {
        if let v = n.vel { return v }
        return value("level", step: step(n.index))
    }

    /// P-lock и свой звук шага, которые едут с нотой (rollCarry): нота была на шаге одна — шаг переезжает целиком.
    public func rollCarry(_ index: Int, pitch: Int) -> StepCarry? {
        guard let s = step(index), s.on, s.notes == [pitch] else { return nil }
        return StepCarry(locks: s.locks, sound: s.sound, soundLocks: s.soundLocks, at: index)
    }

    /// Перенести ноту (с её длиной и velocity) на другой шаг и высоту. carry (rollCarry в начале перетаскивания;
    /// nil — нота была в аккорде: p-lock и звук остаются у шага) — p-lock и свой звук шага едут с нотой: уходят со
    /// шага, где лежат, когда он пустеет, и встают на пустой шаг (без трига, своих p-lock и звука); у шага с другими
    /// нотами или своими p-lock — его p-lock, а эти ждут следующего пустого шага (отпустили там — пропадают; отмена —
    /// UNDO).
    public mutating func moveRollNote(_ index: Int, pitch: Int, to dest: Int, pitch dp: Int, carry: inout StepCarry?) {
        guard let s = step(index), let k = s.notes.firstIndex(of: pitch) else { return }
        if index == dest && pitch == dp { return }
        let len: Int = s.noteLen(k)
        let vel: Double? = s.noteVel(k)
        removeRollNote(index, pitch: pitch)
        if var c = carry, c.at == index, index != dest, step(index)?.on == false {
            withStep(index) { st in
                st.locks = [:]
                st.sound = nil
                st.soundLocks = nil
            }
            c.at = nil
            carry = c
        }
        let ds: Step? = step(dest)
        let free: Bool = ds.map { !$0.on && $0.locks.isEmpty && $0.sound == nil } ?? false
        addRollNote(dest, pitch: dp, len: len, vel: vel)
        if var c = carry, c.at == nil, free {
            withStep(dest) { st in
                st.locks = c.locks
                st.sound = c.sound
                st.soundLocks = c.soundLocks
            }
            c.at = dest
            carry = c
        }
    }

    /// Перенос без p-lock шага (они остаются на месте).
    public mutating func moveRollNote(_ index: Int, pitch: Int, to dest: Int, pitch dp: Int) {
        var none: StepCarry? = nil
        moveRollNote(index, pitch: pitch, to: dest, pitch: dp, carry: &none)
    }
}

/// P-lock и свой звук шага в пути с нотой пианоролла; at — шаг, где они сейчас (nil — «в руке»).
public struct StepCarry: Equatable, Sendable {
    public var locks: [String: Double]
    public var sound: String?
    public var soundLocks: [String]?
    public var at: Int?
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
