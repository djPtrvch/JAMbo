// Ноты шага с длиной и velocity у каждой (S8, пианоролл): lens и vels параллельны notes.

extension Step {
    /// Длина ноты k в шагах.
    public func noteLen(_ k: Int) -> Int {
        if let l = lens, k >= 0, k < l.count { return l[k] }
        return len
    }

    /// Своя velocity ноты k (Level 0…127); nil — Level шага или дорожки.
    public func noteVel(_ k: Int) -> Double? {
        guard let v = vels, k >= 0, k < v.count, v[k] >= 0 else { return nil }
        return v[k]
    }

    /// Хоть у одной ноты своя velocity (шаг с точкой p-lock).
    public var hasVel: Bool { return vels != nil }

    /// Длина всех нот шага (тап и протягивание в секвенсоре, запись) — поштучные длины забываются.
    public mutating func setAllLen(_ n: Int) {
        len = Swift.max(1, n)
        lens = nil
    }

    /// Новый набор нот: у оставшихся нот — прежние длины и velocity, у новых — len шага и без своей velocity.
    public mutating func setNotes(_ new: [Int]) {
        var l: [Int] = []
        var v: [Double] = []
        for n in new {
            let k: Int = notes.firstIndex(of: n) ?? -1
            l.append(k >= 0 ? noteLen(k) : len)
            v.append(k >= 0 ? (noteVel(k) ?? -1) : -1)
        }
        notes = new
        lens = l
        vels = v
        normalize()
    }

    /// Добавить ноту (или сменить длину и velocity, если такая уже есть).
    public mutating func addNote(_ n: Int, len l: Int, vel: Double?) {
        if notes.firstIndex(of: n) == nil {
            var all: [Int] = notes
            all.append(n)
            setNotes(all.sorted())
        }
        guard let k = notes.firstIndex(of: n) else { return }
        setNoteLen(k, l)
        setNoteVel(k, vel)
    }

    /// Убрать ноту k; шаг без нот — без трига.
    public mutating func removeNote(_ k: Int) {
        guard k >= 0, k < notes.count else { return }
        var all: [Int] = notes
        all.remove(at: k)
        setNotes(all)
        if notes.isEmpty { on = false }
    }

    public mutating func setNoteLen(_ k: Int, _ n: Int) {
        guard k >= 0, k < notes.count else { return }
        var l: [Int] = (0..<notes.count).map { noteLen($0) }
        l[k] = Swift.max(1, n)
        lens = l
        normalize()
    }

    /// nil — снять свою velocity.
    public mutating func setNoteVel(_ k: Int, _ v: Double?) {
        guard k >= 0, k < notes.count else { return }
        var all: [Double] = (0..<notes.count).map { noteVel($0) ?? -1 }
        all[k] = v.map { Swift.max(0, Swift.min(127, $0)) } ?? -1
        vels = all
        normalize()
    }

    /// Velocity ноты k, связанная с p-lock Level шага: p-lock — самая сильная нота; ноты без своей velocity
    /// получают прежний Level шага (fallback), чтобы их звук не менялся.
    public mutating func setVelLinked(_ k: Int, _ v: Double, fallback: Double) {
        guard k >= 0, k < notes.count else { return }
        let old: Double = locks["level"] ?? fallback
        for j in 0..<notes.count where j != k && noteVel(j) == nil { setNoteVel(j, old) }
        setNoteVel(k, v)
        if let all = vels, let m = all.max(), m >= 0 { locks["level"] = m }
        if let sl = soundLocks { soundLocks = sl.filter { $0 != "level" } }
    }

    /// Снять velocity всех нот.
    public mutating func clearVels() {
        vels = nil
    }

    /// Одинаковые длины — одна len; без своих velocity — vels nil; len — самая длинная нота.
    public mutating func normalize() {
        if let l = lens {
            if l.count != notes.count {
                lens = nil
            } else if let m = l.max() {
                len = m
                if l.allSatisfy({ $0 == m }) { lens = nil }
            } else {
                lens = nil
            }
        }
        if let v = vels, v.count != notes.count || v.allSatisfy({ $0 < 0 }) { vels = nil }
    }
}
