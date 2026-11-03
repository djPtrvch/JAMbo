// Случайный рисунок нарезанного сэмпла (SHIFT + CHORD на дорожке с маркерами нарезки, SETTINGS → RANDOM → SAMPLES;
// docs/ai/sequencer.md, «Случайная нарезка»). Роли кусков назначаются вручную (удержание флажка в редакторе):
// LOW, MID, HIGH ставятся на места KICK, SNARE, HAT стиля дорожки (DrumRhythm) нотами в 1 шаг, LONG — редко и без наложения;
// без ролей LOW/MID/HIGH — перетасовка брейка: куски по порядку, часть заменена, в конце — сбивка.

public enum SliceRhythm {
    /// Роль куска нарезки (SliceMark.role).
    public enum Role: Int, Sendable, CaseIterable { case low, mid, high, long }

    /// Подписи ролей (строка редактора при удержании флажка) и короткие — у флажка.
    public static let roleNames: [String] = ["LOW", "MID", "HIGH", "LONG"]

    public static func role(_ v: Int?) -> Role? {
        guard let k = v else { return nil }
        return Role(rawValue: k)
    }

    /// Кусок: нота маркера, длина в шагах (от маркера до следующего, в темпе), роль.
    public struct Piece: Equatable, Sendable {
        public var note: Int
        public var len: Double
        public var role: Role?
        public init(note: Int, len: Double, role: Role?) {
            self.note = note
            self.len = len
            self.role = role
        }

        /// Длина в целых шагах (не меньше 1).
        var steps: Int { return Swift.max(1, Int(len.rounded(.up))) }
    }

    /// Кусок метки без ноты: отрезок сэмпла a…b (доли длины).
    public struct Cut: Equatable, Sendable {
        public var a: Double
        public var b: Double
        public init(a: Double, b: Double) {
            self.a = a
            self.b = b
        }
    }

    /// «Ноты» кусков меток без ноты в рисунке (от этого номера по порядку; в шаг пишется Params.sampleRoot).
    public static let cutNote: Int = 1000

    /// Куски нарезки: marks — маркеры сэмпла, notes — их ноты (Slices.notes), lens — длина куска в шагах по
    /// маркеру (до следующего своего вида). Есть маркеры с нотой — куски по ним (метки без ноты не участвуют);
    /// нет — по меткам без ноты, «ноты» — cutNote + номер, отрезки — в cuts.
    public static func pieces(_ marks: [SliceMark], notes: [Int], len: (Double, Double) -> Double)
        -> (pieces: [Piece], cuts: [Int: Cut]) {
        let noted: Bool = marks.contains { !$0.isFree }
        var idx: [Int] = []
        for (k, m) in marks.enumerated() where m.isFree != noted && k < notes.count { idx.append(k) }
        idx.sort { marks[$0].at < marks[$1].at }
        var out: [Piece] = []
        var cuts: [Int: Cut] = [:]
        for (j, k) in idx.enumerated() {
            let a: Double = marks[k].at
            let b: Double = j + 1 < idx.count ? marks[idx[j + 1]].at : 1
            let l: Double = Swift.max(0, len(a, b))
            if noted {
                out.append(Piece(note: notes[k], len: l, role: role(marks[k].role)))
            } else {
                let n: Int = cutNote + j
                cuts[n] = Cut(a: a, b: b)
                out.append(Piece(note: n, len: l, role: role(marks[k].role)))
            }
        }
        return (out, cuts)
    }

    /// Нота на странице: шаг (0…15), нота куска, длина в шагах, velocity — Level ноты 0…127 (nil — без своей).
    public struct Event: Equatable, Sendable {
        public var step: Int
        public var note: Int
        public var len: Int
        public var vel: Double?
        public init(step: Int, note: Int, len: Int, vel: Double?) {
            self.step = step
            self.note = note
            self.len = len
            self.vel = vel
        }
    }

    /// Доля кусков брейка, заменённых случайными.
    static let swapChance: Double = 0.3
    /// Доля шагов сбивки (последние 4 шага последней страницы) с ударом.
    static let fillChance: Double = 0.6

    static func vel<G: RandomNumberGenerator>(_ step: Int, using g: inout G) -> Double {
        if step % 4 == 0 { return DrumRhythm.velFull }
        return Double.random(in: DrumRhythm.velMid, using: &g).rounded()
    }

    /// Роль ударного движка, на места которого встают куски роли.
    static func drumRole(_ r: Role) -> DrumRhythm.Role {
        switch r {
        case .low: return .kick
        case .mid: return .snare
        default: return .hat
        }
    }

    /// Длина каждой ноты — до следующей ноты той же группы (или до конца страницы), не длиннее куска.
    static func clip(_ evs: [Event], pieces: [Piece], len n: Int) -> [Event] {
        let sorted: [Event] = evs.sorted { $0.step < $1.step }
        var out: [Event] = []
        for (i, e) in sorted.enumerated() {
            let next: Int = i + 1 < sorted.count ? sorted[i + 1].step : n
            var x: Event = e
            x.len = Swift.max(1, Swift.min(e.len, next - e.step))
            out.append(x)
        }
        return out
    }

    // MARK: — роли LOW, MID, HIGH (кит)

    /// Ноты ролей LOW, MID, HIGH на страницах lens по партиям KICK, SNARE, HAT стиля (основа, вариации, сбивка).
    static func kit<G: RandomNumberGenerator>(_ pieces: [Piece], style: Int, lens: [Int],
                                             using g: inout G) -> [[Event]] {
        var out: [[Event]] = lens.map { _ in [] }
        for r in [Role.low, Role.mid, Role.high] {
            let own: [Piece] = pieces.filter { $0.role == r }
            if own.isEmpty { continue }
            let hits: [[DrumRhythm.Hit]] = DrumRhythm.pattern(drumRole(r), style: style, lens: lens, using: &g)
            for (p, page) in hits.enumerated() {
                var evs: [Event] = []
                for h in page {
                    guard let pc = own.randomElement(using: &g) else { continue }
                    // Нота в 1 шаг (решение пользователя 3.11): хвост куска — ручкой Decay, как у ударной дорожки.
                    evs.append(Event(step: h.step, note: pc.note, len: 1, vel: h.vel ?? DrumRhythm.velFull))
                }
                out[p] += evs
            }
        }
        return out
    }

    // MARK: — брейк (кусков без ролей)

    /// Основа брейка длиной n: куски по порядку от первого (шаг 1 — всегда первый кусок), каждый своей длиной;
    /// часть (swapChance) заменена случайным куском.
    static func breakBase<G: RandomNumberGenerator>(_ u: [Piece], len n: Int, using g: inout G) -> [Event] {
        var out: [Event] = []
        var s: Int = 0
        var k: Int = 0
        while s < n {
            var i: Int = k % u.count
            if s > 0 && u.count > 1 && Double.random(in: 0..<1, using: &g) < swapChance {
                i = Int.random(in: 0..<u.count, using: &g)
            }
            let l: Int = Swift.min(u[i].steps, n - s)
            out.append(Event(step: s, note: u[i].note, len: l, vel: vel(s, using: &g)))
            s += l
            k = i + 1
        }
        return out
    }

    /// Вариация: 1–2 куска (не первый) заменены другими, каждый — в своём месте и не длиннее его.
    static func breakVary<G: RandomNumberGenerator>(_ base: [Event], _ u: [Piece], len n: Int,
                                                    using g: inout G) -> [Event] {
        var out: [Event] = base.filter { $0.step < n }
        if out.count < 2 || u.count < 2 { return clip(out, pieces: u, len: n) }
        let changes: Int = Int.random(in: 1...2, using: &g)
        for _ in 0..<changes {
            let i: Int = Int.random(in: 1..<out.count, using: &g)
            let others: [Piece] = u.filter { $0.note != out[i].note }
            guard let pc = others.randomElement(using: &g) else { continue }
            out[i].note = pc.note
            out[i].len = Swift.min(out[i].len, pc.steps)
        }
        return clip(out, pieces: u, len: n)
    }

    /// Сбивка: последние 4 шага заново — повтор одного куска (чаще) или случайные куски по шагу; хоть один удар.
    static func breakFill<G: RandomNumberGenerator>(_ base: [Event], _ u: [Piece], len n: Int,
                                                    using g: inout G) -> [Event] {
        let from: Int = Swift.max(0, n - 4)
        var out: [Event] = base.filter { $0.step < from }.map { e in
            var x: Event = e
            x.len = Swift.min(e.len, from - e.step)
            return x
        }
        let rep: Piece = u[Int.random(in: 0..<u.count, using: &g)]
        var added: Int = 0
        for s in from..<n where Double.random(in: 0..<1, using: &g) < fillChance {
            let pc: Piece = Double.random(in: 0..<1, using: &g) < 0.6 ? rep : u[Int.random(in: 0..<u.count, using: &g)]
            out.append(Event(step: s, note: pc.note, len: 1, vel: vel(s, using: &g)))
            added += 1
        }
        if added == 0 {
            let s: Int = Int.random(in: from..<n, using: &g)
            out.append(Event(step: s, note: rep.note, len: 1, vel: vel(s, using: &g)))
        }
        return clip(out, pieces: u, len: n)
    }

    // MARK: — LONG

    /// Длинные куски: с шага 1, следующий — через 8 шагов (кусок до 8 шагов) или через страницу; нота — до
    /// следующей, не длиннее куска: длинные не накладываются друг на друга.
    static func longs<G: RandomNumberGenerator>(_ l: [Piece], len n: Int, using g: inout G) -> [Event] {
        var out: [Event] = []
        var s: Int = 0
        while s < n {
            guard let pc = l.randomElement(using: &g) else { break }
            let gap: Int = pc.steps <= 8 ? 8 : Params.stepsPerPage
            out.append(Event(step: s, note: pc.note, len: Swift.min(pc.steps, gap, n - s),
                             vel: DrumRhythm.velFull))
            s += gap
        }
        return out
    }

    // MARK: — рисунок

    /// Рисунок на страницы lens (шагов на странице, 0 — не играет): LOW, MID, HIGH — по стилю; без них — брейк из
    /// кусков без роли; LONG — поверх. Первая страница брейка не повторяет avoid (код прошлой основы), если
    /// получится за 16 попыток. Нет кусков — пусто.
    public static func pattern<G: RandomNumberGenerator>(_ pieces: [Piece], style: Int = 0, lens: [Int],
                                                         avoid: [Int]? = nil, using g: inout G) -> [[Event]] {
        var out: [[Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        guard let first = playing.first, let last = playing.last else { return out }
        let kitMode: Bool = pieces.contains { $0.role != nil && $0.role != .long }
        if kitMode {
            out = kit(pieces, style: style, lens: lens, using: &g)
        } else {
            let u: [Piece] = pieces.filter { $0.role == nil }
            if !u.isEmpty {
                var b: [Event] = breakBase(u, len: lens[first], using: &g)
                var tries: Int = 1
                while code(b) == avoid && tries < 16 {
                    b = breakBase(u, len: lens[first], using: &g)
                    tries += 1
                }
                out[first] = b
                for p in playing where p != first && p != last {
                    out[p] = breakVary(b, u, len: lens[p], using: &g)
                }
                if last != first { out[last] = breakFill(b, u, len: lens[last], using: &g) }
            }
        }
        let l: [Piece] = pieces.filter { $0.role == .long }
        if !l.isEmpty {
            for p in playing { out[p] += longs(l, len: lens[p], using: &g) }
        }
        return out.map { $0.sorted { ($0.step, $0.note) < ($1.step, $1.note) } }
    }

    /// Код рисунка (для avoid): шаг · 128 + нота.
    public static func code(_ evs: [Event]) -> [Int] {
        return evs.map { $0.step * 128 + $0.note }
    }
}

extension Track {
    /// Звук дорожки — сэмпл (не синт) с маркерами нарезки (с нотой: клавиши играют куски).
    public var sliced: Bool {
        if sample.isEmpty || SynthKey.engine(sample) != nil { return false }
        return sliceMarks(sample).contains { !$0.isFree }
    }

    /// Звук дорожки — сэмпл с любыми маркерами (и метками без ноты): случайная нарезка (RANDOM).
    public var hasCuts: Bool {
        if sample.isEmpty || SynthKey.engine(sample) != nil { return false }
        return !sliceMarks(sample).isEmpty
    }

    /// Роль маркера нарезки idx (nil — снять).
    public mutating func setSliceRole(_ key: String, _ idx: Int, role: SliceRhythm.Role?) {
        var m = sliceMarks(key)
        guard idx >= 0 && idx < m.count else { return }
        m[idx].role = role?.rawValue
        putMarks(key, m)
    }

    /// Рисунок на страницы range открытого паттерна: прежние шаги этих страниц стираются, ноты — со своей длиной
    /// и velocity (Level ноты). Страницы вне range не трогаются. cuts — куски меток без ноты (по «ноте» куска —
    /// отрезок сэмпла, доли длины): шаг играет исходную высоту (Params.sampleRoot) с p-lock Start и End; на шаге —
    /// не больше одного такого куска (первый).
    public mutating func writeSlices(_ pattern: [[SliceRhythm.Event]], pages range: ClosedRange<Int>,
                                     cuts: [Int: SliceRhythm.Cut] = [:]) {
        let lo: Int = Swift.max(0, range.lowerBound)
        let hi: Int = Swift.min(pages.count - 1, range.upperBound)
        if lo > hi { return }
        changePages { ps in
            for p in lo...hi { ps[p] = Track.emptyPage() }
        }
        for (i, evs) in pattern.enumerated() where lo + i <= hi {
            let base: Int = (lo + i) * Params.stepsPerPage
            var cutSteps = Set<Int>()
            for e in evs {
                if let c = cuts[e.note] {
                    if cutSteps.contains(e.step) { continue }
                    cutSteps.insert(e.step)
                    withStep(base + e.step) { s in
                        s.on = true
                        s.addNote(Params.sampleRoot, len: e.len, vel: e.vel)
                        s.locks["start"] = c.a * 100
                        s.locks["end"] = c.b * 100
                    }
                    continue
                }
                withStep(base + e.step) { s in
                    s.on = true
                    s.addNote(e.note, len: e.len, vel: e.vel)
                }
            }
            // p-lock Level шага — самая сильная нота (как у пианоролла); у каждой ноты своя velocity.
            for st in Set(evs.map { $0.step }) {
                let top: Double? = evs.filter { $0.step == st }.compactMap { $0.vel }.max()
                // Напрямую, не через setLock: тот снимает velocity нот.
                if let v = top { withStep(base + st) { s in s.locks["level"] = v } }
            }
        }
    }

    /// Случайный рисунок нарезки на страницы range (по их длинам) в стиле дорожки; avoid — код прошлой основы.
    /// Возвращает код новой основы; нет кусков — nil, ничего не пишется.
    public mutating func writeRandomSlices<G: RandomNumberGenerator>(_ pieces: [SliceRhythm.Piece],
                                                                     pages range: ClosedRange<Int>, avoid: [Int]?,
                                                                     cuts: [Int: SliceRhythm.Cut] = [:],
                                                                     using g: inout G) -> [Int]? {
        if pieces.isEmpty { return nil }
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[SliceRhythm.Event]] = SliceRhythm.pattern(pieces, style: drumStyle, lens: lens, avoid: avoid,
                                                                 using: &g)
        writeSlices(pattern, pages: range, cuts: cuts)
        return SliceRhythm.code(pattern.first(where: { !$0.isEmpty }) ?? [])
    }
}
