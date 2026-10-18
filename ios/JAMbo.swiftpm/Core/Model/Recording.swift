// Запись нот с REC (как recordNotes, recordLength, recPassStep в state.ts веба) — правки шагов дорожки.

extension Track {
    /// Ноты на шаг index. merge — добавить к записанным на этом шаге в том же дубле; overdub — к стоящим.
    /// velocity (0.2…1) — velocity нот (Level ноты = Level дорожки × сила, S8; та же нота в дубле — по самой сильной).
    public mutating func recordNotes(_ index: Int, _ notes: [Int], merge: Bool, overdub: Bool, velocity: Double?) {
        let level: Double = params["level"] ?? 127
        withStep(index) { s in
            let merged: Bool = (merge || overdub) && s.on
            if !merged {
                s.lens = nil
                s.vels = nil
            }
            s.setNotes(merged ? Array(Set(s.notes + notes)).sorted() : notes)
            s.on = true
            s.setAllLen(1)
            if let v = velocity {
                let lv: Double = (level * v).rounded()
                for n in notes {
                    guard let k = s.notes.firstIndex(of: n) else { continue }
                    let old: Double = merged ? (s.noteVel(k) ?? 0) : 0
                    s.setNoteVel(k, Swift.max(old, lv))
                }
            }
        }
    }

    /// Отпустили клавишу: длина записанной ноты (в шагах, не меньше 1, не дальше конца паттерна).
    public mutating func recordLength(_ index: Int, _ len: Int) {
        let maxLen = length - index
        withStep(index) { s in
            if !s.on { return }
            s.setAllLen(Swift.max(s.len, Swift.min(len, maxLen)))
        }
    }

    /// OVERDUB OFF: шаг, по которому проходит запись, очищается (триг, ноты, p-lock, свой звук).
    /// false — шаг и так пустой.
    @discardableResult
    public mutating func clearPassStep(_ index: Int) -> Bool {
        guard let s = step(index), s.on || s.sound != nil || !s.locks.isEmpty else { return false }
        withStep(index) { $0 = Step() }
        return true
    }
}

/// Шаг записи по времени: k = tick + (кадр − кадр следующего шага) / длина шага, с округлением (QUANTIZE)
/// или вниз — на шаг, в котором нажали.
public enum RecordClock {
    public static func tick(frame: Double, nextTick: Int, nextFrame: Double, stepFrames: Double, quantize: Bool) -> Int {
        let d: Double = (frame - nextFrame) / stepFrames
        let k: Double = quantize ? d.rounded() : d.rounded(.down)
        return Swift.max(0, nextTick + Int(k))
    }

    /// Длина ноты в шагах по времени удержания.
    public static func length(seconds: Double, stepSeconds: Double) -> Int {
        return Swift.max(1, Int((seconds / stepSeconds).rounded()))
    }
}
