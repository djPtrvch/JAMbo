// Случайный ритм ударных (SHIFT + CHORD на дорожке с KICK, SNARE, HAT, CLAP, PERC): рисунок страницы по
// вероятностям шагов движка, вариации средних страниц и сбивка последней (docs/ai/sequencer.md, «Пианоролл»).

public enum DrumRhythm {
    /// Роль ударного движка.
    public enum Role: Int, Sendable { case kick, snare, hat, clap, perc }

    /// Удар: шаг страницы (0…15) и velocity — Level 0…127 (nil — без p-lock, у KICK).
    public struct Hit: Equatable, Sendable {
        public var step: Int
        public var vel: Double?
        public init(step: Int, vel: Double?) {
            self.step = step
            self.vel = vel
        }
    }

    /// Роль по номеру движка; не ударный — nil.
    public static func role(engine: Int?) -> Role? {
        guard let e = engine else { return nil }
        switch e {
        case Jambo.drum: return .kick
        case Jambo.snare: return .snare
        case Jambo.hat: return .hat
        case Jambo.clap: return .clap
        case Jambo.perc: return .perc
        default: return nil
        }
    }

    /// Velocity (Level): доля 100 %, обычный удар 70–85 %, призрачный 30–45 %.
    static let velFull: Double = 127
    static let velMid: ClosedRange<Double> = 88.9...107.95
    static let velGhost: ClosedRange<Double> = 38.1...57.15

    /// Вероятности шагов KICK (0…15): 1 всегда, 9 почти всегда, 5 и 13 часто, синкопы 11, 15, 16 иногда.
    static let kickChance: [Double] = [1, 0, 0, 0, 0.55, 0, 0, 0, 0.9, 0, 0.35, 0, 0.55, 0, 0.3, 0.25]
    /// Призрачные удары SNARE (шаги 4, 7, 10, 12, 15, 16) и их вероятность.
    static let snareGhosts: [Int] = [3, 6, 9, 11, 14, 15]
    static let snareGhostChance: Double = 0.15
    /// Пропуск удара HAT.
    static let hatSkip: Double = 0.12
    /// Удар CLAP на шестнадцатую позже.
    static let clapShift: Double = 0.3
    /// Доля шага сбивки с ударом (шаги 13–16 последней страницы).
    static let fillChance: [Double] = [0.4, 0.6, 0.7, 0.45, 0.5]

    private static func hitVel<G: RandomNumberGenerator>(_ role: Role, step: Int, ghost: Bool,
                                                         using g: inout G) -> Double? {
        if role == .kick { return nil }
        if ghost { return Double.random(in: velGhost, using: &g).rounded() }
        if step % 4 == 0 { return velFull }
        return Double.random(in: velMid, using: &g).rounded()
    }

    /// Евклидов ритм: k ударов на n шагах (по Бьёрклунду через округление), сдвиг rot.
    public static func euclid(_ k: Int, _ n: Int, rot: Int) -> [Int] {
        if n <= 0 || k <= 0 { return [] }
        let kk: Int = Swift.min(k, n)
        var out: [Int] = []
        for i in 0..<kk {
            let s: Int = (i * n) / kk
            out.append(((s + rot) % n + n) % n)
        }
        return out.sorted()
    }

    /// Основа: рисунок страницы длиной len (1…16) по вероятностям шагов движка; не пустая.
    public static func base<G: RandomNumberGenerator>(_ role: Role, len: Int, using g: inout G) -> [Hit] {
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        var hits: [Hit] = []
        switch role {
        case .kick:
            for s in 0..<n where Double.random(in: 0..<1, using: &g) < kickChance[s] {
                hits.append(Hit(step: s, vel: nil))
            }
        case .snare:
            for s in 0..<n {
                if s == 4 || s == 12 {
                    hits.append(Hit(step: s, vel: velFull))
                } else if snareGhosts.contains(s) && Double.random(in: 0..<1, using: &g) < snareGhostChance {
                    hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: true, using: &g)))
                }
            }
        case .hat:
            let sixteenths: Bool = Bool.random(using: &g)
            for s in 0..<n where sixteenths || s % 2 == 0 {
                if Double.random(in: 0..<1, using: &g) < hatSkip { continue }
                hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
            }
        case .clap:
            var steps: [Int] = Bool.random(using: &g) ? [4, 12] : [12]
            if Double.random(in: 0..<1, using: &g) < clapShift {
                let i: Int = Int.random(in: 0..<steps.count, using: &g)
                steps[i] += 1
            }
            for s in steps where s < n {
                hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
            }
        case .perc:
            let k: Int = Int.random(in: 3...7, using: &g)
            let rot: Int = Int.random(in: 0..<n, using: &g)
            for s in euclid(k, n, rot: rot) {
                hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
            }
        }
        if hits.isEmpty {
            // Короткая страница без ударов движка (SNARE, CLAP на 1–4 шагах): удар на середине.
            let s: Int = n >= 2 ? n / 2 : 0
            hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
        }
        return hits
    }

    /// Опорные удары, которые вариации не снимают: KICK — шаг 1, SNARE — 5 и 13.
    static func anchor(_ role: Role, _ s: Int) -> Bool {
        switch role {
        case .kick: return s == 0
        case .snare: return s == 4 || s == 12
        default: return false
        }
    }

    /// Вариация: 1–2 удара добавлено или убрано (опорные не снимаются), в пределах len.
    public static func vary<G: RandomNumberGenerator>(_ hits: [Hit], role: Role, len: Int,
                                                      using g: inout G) -> [Hit] {
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        var out: [Hit] = hits.filter { $0.step < n }
        let changes: Int = Int.random(in: 1...2, using: &g)
        for _ in 0..<changes {
            let removable: [Int] = out.indices.filter { !anchor(role, out[$0].step) }
            let used: Set<Int> = Set(out.map { $0.step })
            let free: [Int] = (0..<n).filter { !used.contains($0) }
            let remove: Bool = !removable.isEmpty && (free.isEmpty || Bool.random(using: &g))
            if remove, let i = removable.randomElement(using: &g), out.count > 1 {
                out.remove(at: i)
            } else if let s = free.randomElement(using: &g) {
                let ghost: Bool = role == .snare && s % 4 != 0
                out.append(Hit(step: s, vel: hitVel(role, step: s, ghost: ghost, using: &g)))
            }
        }
        if out.isEmpty { out = base(role, len: n, using: &g) }
        return out.sorted { $0.step < $1.step }
    }

    /// Сбивка: последние 4 шага (из len) заново, хоть один удар.
    public static func fill<G: RandomNumberGenerator>(_ hits: [Hit], role: Role, len: Int,
                                                      using g: inout G) -> [Hit] {
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        let from: Int = Swift.max(0, n - 4)
        var out: [Hit] = hits.filter { $0.step < from }
        let p: Double = fillChance[role.rawValue]
        var added: Int = 0
        for s in from..<n where Double.random(in: 0..<1, using: &g) < p {
            out.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
            added += 1
        }
        if added == 0 {
            let s: Int = Int.random(in: from..<n, using: &g)
            out.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
        }
        return out.sorted { $0.step < $1.step }
    }

    /// Ритм на страницы с длинами lens (шагов на странице, 0 — страница не играет): первая — основа (по своей
    /// длине), средние — вариации, последняя играющая — основа со сбивкой; одна страница — только основа.
    /// Основа не совпадает с avoid (шаги прошлого рисунка), если получится за 16 попыток.
    public static func pattern<G: RandomNumberGenerator>(_ role: Role, lens: [Int], avoid: [Int]? = nil,
                                                         using g: inout G) -> [[Hit]] {
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        var out: [[Hit]] = lens.map { _ in [] }
        guard let first = playing.first, let last = playing.last else { return out }
        var b: [Hit] = base(role, len: lens[first], using: &g)
        var tries: Int = 1
        while b.map({ $0.step }) == avoid && tries < 16 {
            b = base(role, len: lens[first], using: &g)
            tries += 1
        }
        out[first] = b
        if last == first { return out }
        for p in playing where p != first && p != last {
            out[p] = vary(b, role: role, len: lens[p], using: &g)
        }
        let lastBase: [Hit] = lens[last] >= lens[first] ? b : b.filter { $0.step < lens[last] }
        out[last] = fill(lastBase, role: role, len: lens[last], using: &g)
        return out
    }
}

extension Track {
    /// Ритм на страницы range открытого паттерна: прежние шаги этих страниц стираются (как у прогрессии), удары —
    /// нотой note длиной 1 шаг, velocity — p-lock Level шага. Страницы вне range не трогаются.
    public mutating func writeDrums(_ pattern: [[DrumRhythm.Hit]], note: Int, pages range: ClosedRange<Int>) {
        let lo: Int = Swift.max(0, range.lowerBound)
        let hi: Int = Swift.min(pages.count - 1, range.upperBound)
        if lo > hi { return }
        changePages { ps in
            for p in lo...hi { ps[p] = Track.emptyPage() }
        }
        for (i, hits) in pattern.enumerated() where lo + i <= hi {
            let base: Int = (lo + i) * Params.stepsPerPage
            for h in hits {
                withStep(base + h.step) { s in
                    s.on = true
                    s.notes = [note]
                    s.setAllLen(1)
                }
                if let v = h.vel { setLock(base + h.step, "level", v) }
            }
        }
    }
}
