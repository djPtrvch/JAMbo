// Случайный ритм ударных (SHIFT + CHORD на дорожке с KICK, SNARE, HAT, CLAP, PERC): рисунок страницы по
// вероятностям шагов движка в стиле дорожки, вариации средних страниц и сбивка последней (docs/ai/sequencer.md, «Пианоролл»).

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

    /// Стили ритма (у дорожки — Track.drumStyle); подписи — как у типов аккорда (с заглавной).
    public static let styles: [String] = ["House", "Breaks", "D&B", "Trap", "Afro", "Minimal"]

    public static func styleIndex(_ s: Int) -> Int { return Swift.max(0, Swift.min(styles.count - 1, s)) }

    /// Партия движка в стиле: вероятности шагов 0…15 (несколько вариантов — один наугад), призрачные шаги;
    /// или евклидов ритм lo…hi ударов (fromOne — первый удар на шаге 1, иначе случайный сдвиг).
    enum Part {
        case chance([[Double]], ghosts: [Int])
        case euclid(Int, Int, fromOne: Bool)
    }

    /// Velocity (Level): доля 100 %, обычный удар 70–85 %, призрачный 30–45 %.
    static let velFull: Double = 127
    static let velMid: ClosedRange<Double> = 88.9...107.95
    static let velGhost: ClosedRange<Double> = 38.1...57.15

    /// Вероятность шага в списке steps, остальные — rest.
    static func probs(_ steps: [Int: Double], rest: Double = 0) -> [Double] {
        var out: [Double] = [Double](repeating: rest, count: 16)
        for (k, v) in steps { out[k] = v }
        return out
    }

    static let ghostSteps: [Int] = [3, 6, 9, 11, 14, 15]
    static let evens: [Int: Double] = [0: 1, 2: 1, 4: 1, 6: 1, 8: 1, 10: 1, 12: 1, 14: 1]

    static func ghosts(_ steps: [Int], _ p: Double, main: [Int]) -> [Double] {
        var out: [Double] = [Double](repeating: 0, count: 16)
        for k in steps { out[k] = p }
        for k in main { out[k] = 1 }
        return out
    }

    static func scaled(_ a: [Double], _ k: Double) -> [Double] { return a.map { $0 * k } }

    /// Партия движка role в стиле style (номера шагов — с 0).
    static func part(_ style: Int, _ role: Role) -> Part {
        switch (styleIndex(style), role) {
        // HOUSE: бочка на каждую долю.
        case (0, .kick): return .chance([probs([0: 1, 4: 1, 8: 1, 12: 1, 15: 0.25])], ghosts: [])
        case (0, .snare): return .chance([ghosts(ghostSteps, 0.1, main: [4, 12])], ghosts: ghostSteps)
        case (0, .hat): return .chance([probs([2: 1, 6: 1, 10: 1, 14: 1], rest: 0.25)], ghosts: [])
        case (0, .clap): return .chance([probs([4: 1, 12: 1])], ghosts: [])
        // BREAKS: ломаный бит, много призрачных ударов.
        case (1, .kick): return .chance([probs([0: 1, 10: 0.7, 2: 0.35, 7: 0.35, 11: 0.35])], ghosts: [])
        case (1, .snare): return .chance([ghosts([7, 9, 14, 15], 0.45, main: [4, 12])], ghosts: [7, 9, 14, 15])
        case (1, .hat): return .chance([scaled(probs(evens), 0.8)], ghosts: [])
        case (1, .clap): return .chance([probs([4: 1, 12: 1])], ghosts: [])
        // D&B: бочка 1 и 11, малый 5 и 13.
        case (2, .kick): return .chance([probs([0: 1, 10: 1, 7: 0.3, 11: 0.3])], ghosts: [])
        case (2, .snare): return .chance([ghosts(ghostSteps, 0.12, main: [4, 12])], ghosts: ghostSteps)
        case (2, .hat): return .chance([scaled(probs(evens), 0.9)], ghosts: [])
        case (2, .clap): return .chance([probs([4: 1, 12: 1])], ghosts: [])
        // TRAP: половинный темп — малый на 9.
        case (3, .kick): return .chance([probs([0: 1, 7: 0.35, 10: 0.35, 11: 0.35, 14: 0.35])], ghosts: [])
        case (3, .snare): return .chance([ghosts([3, 6, 11, 14, 15], 0.12, main: [8])], ghosts: [3, 6, 11, 14, 15])
        case (3, .hat): return .chance([probs([:], rest: 0.85)], ghosts: [])
        case (3, .clap): return .chance([probs([8: 1])], ghosts: [])
        case (3, .perc): return .euclid(2, 5, fromOne: false)
        // AFRO: все движки — евклидов ритм.
        case (4, .kick): return .euclid(3, 5, fromOne: true)
        case (4, .snare): return .euclid(2, 3, fromOne: false)
        case (4, .hat): return .euclid(5, 11, fromOne: false)
        case (4, .clap): return .euclid(2, 3, fromOne: false)
        // MINIMAL: редкий рисунок с паузами.
        case (5, .kick): return .chance([probs([0: 1, 10: 0.35])], ghosts: [])
        case (5, .snare): return .chance([probs([12: 1])], ghosts: [])
        case (5, .hat): return .chance([probs([0: 0.5, 4: 0.5, 8: 0.5, 12: 0.5])], ghosts: [])
        case (5, .clap): return .chance([probs([12: 1])], ghosts: [])
        case (5, .perc): return .euclid(2, 3, fromOne: false)
        // PERC в остальных стилях.
        default: return .euclid(3, 7, fromOne: false)
        }
    }

    /// Доля шага сбивки с ударом (шаги 13–16 последней страницы).
    static let fillChance: [Double] = [0.4, 0.6, 0.7, 0.45, 0.5]

    private static func hitVel<G: RandomNumberGenerator>(_ role: Role, step: Int, ghost: Bool,
                                                         using g: inout G) -> Double? {
        if role == .kick { return nil }
        if ghost { return Double.random(in: velGhost, using: &g).rounded() }
        if step % 4 == 0 { return velFull }
        return Double.random(in: velMid, using: &g).rounded()
    }

    /// Евклидов ритм: k ударов на n шагах (равномерно, через округление), сдвиг rot.
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

    /// Основа: рисунок страницы длиной len (1…16) по партии движка в стиле; не пустая.
    public static func base<G: RandomNumberGenerator>(_ role: Role, style: Int = 0, len: Int,
                                                      using g: inout G) -> [Hit] {
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        var hits: [Hit] = []
        switch part(style, role) {
        case .chance(let options, let gh):
            let pr: [Double] = options.count == 1 ? options[0] : options[Int.random(in: 0..<options.count, using: &g)]
            for s in 0..<n where pr[s] > 0 && Double.random(in: 0..<1, using: &g) < pr[s] {
                let ghost: Bool = gh.contains(s) && pr[s] < 1
                hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: ghost, using: &g)))
            }
        case .euclid(let lo, let hi, let fromOne):
            let k: Int = Int.random(in: lo...hi, using: &g)
            let rot: Int = fromOne ? 0 : Int.random(in: 0..<n, using: &g)
            for s in euclid(k, n, rot: rot) {
                hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
            }
        }
        if hits.isEmpty {
            // Короткая страница без ударов партии (SNARE, CLAP на 1–4 шагах) или всё выпало: удар на середине.
            let s: Int = n >= 2 ? n / 2 : 0
            hits.append(Hit(step: s, vel: hitVel(role, step: s, ghost: false, using: &g)))
        }
        return hits
    }

    /// Опорные удары, которые вариации не снимают: KICK — шаг 1, SNARE — основные удары стиля (вероятность 1).
    static func anchor(_ role: Role, style: Int, _ s: Int) -> Bool {
        switch role {
        case .kick: return s == 0
        case .snare:
            if case .chance(let options, let gh) = part(style, .snare) {
                return !gh.contains(s) && options.allSatisfy { $0[s] >= 1 }
            }
            return false
        default: return false
        }
    }

    /// Вариация: 1–2 удара добавлено или убрано (опорные не снимаются), в пределах len.
    public static func vary<G: RandomNumberGenerator>(_ hits: [Hit], role: Role, style: Int = 0, len: Int,
                                                      using g: inout G) -> [Hit] {
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        var out: [Hit] = hits.filter { $0.step < n }
        let changes: Int = Int.random(in: 1...2, using: &g)
        for _ in 0..<changes {
            let removable: [Int] = out.indices.filter { !anchor(role, style: style, out[$0].step) }
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
        if out.isEmpty { out = base(role, style: style, len: n, using: &g) }
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
    public static func pattern<G: RandomNumberGenerator>(_ role: Role, style: Int = 0, lens: [Int],
                                                         avoid: [Int]? = nil, using g: inout G) -> [[Hit]] {
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        var out: [[Hit]] = lens.map { _ in [] }
        guard let first = playing.first, let last = playing.last else { return out }
        var b: [Hit] = base(role, style: style, len: lens[first], using: &g)
        var tries: Int = 1
        while b.map({ $0.step }) == avoid && tries < 16 {
            b = base(role, style: style, len: lens[first], using: &g)
            tries += 1
        }
        out[first] = b
        if last == first { return out }
        for p in playing where p != first && p != last {
            out[p] = vary(b, role: role, style: style, len: lens[p], using: &g)
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

extension Track {
    /// Ударная роль звука дорожки (KICK, SNARE, HAT, CLAP, PERC); иначе nil.
    public var drumRole: DrumRhythm.Role? { return DrumRhythm.role(engine: SynthKey.engine(sample)) }

    /// Случайный ритм стиля дорожки на страницы range (по их длинам) нотой note; avoid — шаги прошлой основы.
    /// Возвращает шаги новой основы (для следующего avoid); не ударная дорожка — nil, ничего не пишется.
    public mutating func writeRandomDrums<G: RandomNumberGenerator>(pages range: ClosedRange<Int>, note: Int,
                                                                    avoid: [Int]?, using g: inout G) -> [Int]? {
        guard let role = drumRole else { return nil }
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[DrumRhythm.Hit]] = DrumRhythm.pattern(role, style: drumStyle, lens: lens, avoid: avoid, using: &g)
        writeDrums(pattern, note: note, pages: range)
        return pattern.first(where: { !$0.isEmpty })?.map { $0.step }
    }
}
