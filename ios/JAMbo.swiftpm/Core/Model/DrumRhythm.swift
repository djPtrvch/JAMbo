// Случайный ритм ударных (SHIFT + CHORD на дорожке с KICK, SNARE, HAT, CLAP, PERC): рисунок страницы по
// вероятностям шагов движка в стиле проекта, вариации средних страниц и сбивка последней (docs/ai/sequencer.md, «Пианоролл»).
// Стиль — один на проект (у всех дорожек); Breaks / D&B и Trap / R&B выбирают вариант по темпу проекта.

public enum DrumRhythm {
    /// Роль ударного движка.
    public enum Role: Int, Sendable { case kick, snare, hat, clap, perc }

    /// Удар: шаг страницы (0…15), velocity — Level 0…127 (nil — без p-lock, у KICK), ratchet — p-lock Ratchet
    /// (1…3 — 2–4 удара; nil — без), chance — p-lock Chance 0…100 (nil — без).
    public struct Hit: Equatable, Sendable {
        public var step: Int
        public var vel: Double?
        public var ratchet: Int?
        public var chance: Double?
        public init(step: Int, vel: Double?, ratchet: Int? = nil, chance: Double? = nil) {
            self.step = step
            self.vel = vel
            self.ratchet = ratchet
            self.chance = chance
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

    /// Слова имени сэмпла (строчными, разбито по не-буквам и не-цифрам).
    public static func words(_ name: String) -> [String] {
        return name.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { String($0) }
    }

    /// Роль ударного сэмпла по имени файла (7.11): kick, bd → KICK; snare, sd, rim → SNARE; clap, cp → CLAP;
    /// hat, hihat, hh, oh, ch, ride → HAT; perc, tom, conga, bongo, shaker, tamb, cowbell, clave → PERC; иначе nil.
    public static func role(name: String) -> Role? {
        let w: [String] = words(name)
        let joined: String = w.joined()
        func has(_ exact: [String], prefix: [String]) -> Bool {
            return w.contains { t in exact.contains(t) || prefix.contains { t.hasPrefix($0) } }
        }
        if joined.contains("kick") || has(["bd", "kik"], prefix: ["kick", "bassdrum"]) || joined.contains("bassdrum") {
            return .kick
        }
        if joined.contains("snare") || has(["sd", "snr", "rim", "rimshot"], prefix: ["snare"]) { return .snare }
        if joined.contains("clap") || has(["cp", "clp"], prefix: ["clap"]) { return .clap }
        if joined.contains("hihat") || has(["hh", "oh", "ch", "ride"], prefix: ["hat"]) { return .hat }
        if has(["perc"], prefix: ["perc", "tom", "conga", "bongo", "shaker", "tamb", "cowbell", "clave"]) { return .perc }
        return nil
    }

    /// Стили (кнопки окна CHORD, Track.drumStyle); подписи — с заглавной. Minimal — внутри Techno (решение 4.11).
    public static let styles: [String] = ["House", "Techno", "Breaks/D&B", "Trap/R&B", "Pop", "Ambient"]

    public static func styleIndex(_ s: Int) -> Int { return Swift.max(0, Swift.min(styles.count - 1, s)) }

    /// Номер стиля до 4.11 (House, Breaks, D&B, Trap, Afro, Minimal) → нынешний.
    public static func migrateStyle(_ old: Int) -> Int {
        let map: [Int] = [0, 2, 2, 3, 0, 1]
        return map[Swift.max(0, Swift.min(map.count - 1, old))]
    }

    /// Рисунок: стиль с вариантом по темпу.
    public enum Groove: Int, Sendable, CaseIterable { case house, techno, breaks, dnb, trap, rnb, pop, ambient }

    /// Подписи вариантов (под словом RANDOM).
    public static let grooveNames: [String] = ["House", "Techno", "Breaks", "D&B", "Trap", "R&B", "Pop", "Ambient"]

    /// Breaks/D&B: с этого темпа — D&B. Trap/R&B: с этого темпа — Trap (половинный темп), ниже — R&B.
    public static let dnbBpm: Double = 150
    public static let trapBpm: Double = 115

    public static func groove(_ style: Int, bpm: Double) -> Groove {
        switch styleIndex(style) {
        case 0: return .house
        case 1: return .techno
        case 2: return bpm >= dnbBpm ? .dnb : .breaks
        case 3: return bpm >= trapBpm ? .trap : .rnb
        case 4: return .pop
        default: return .ambient
        }
    }

    /// Swing дорожки по рисунку (SETTINGS → RANDOM → AUTO SWING), 50 — без swing.
    public static let swings: [Double] = [54, 50, 56, 52, 50, 60, 52, 50]

    public static func swing(_ style: Int, bpm: Double) -> Double { return swings[groove(style, bpm: bpm).rawValue] }

    /// Партия движка: вероятности шагов 0…15 (несколько вариантов — один наугад), призрачные шаги;
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
    static let fours: [Int: Double] = [0: 1, 4: 1, 8: 1, 12: 1]
    static let offbeats: [Int: Double] = [2: 1, 6: 1, 10: 1, 14: 1]
    static let evens: [Int: Double] = [0: 1, 2: 1, 4: 1, 6: 1, 8: 1, 10: 1, 12: 1, 14: 1]

    static func ghosts(_ steps: [Int], _ p: Double, main: [Int]) -> [Double] {
        var out: [Double] = [Double](repeating: 0, count: 16)
        for k in steps { out[k] = p }
        for k in main { out[k] = 1 }
        return out
    }

    static func with(_ base: [Int: Double], _ extra: [Int: Double], rest: Double = 0) -> [Double] {
        return probs(base.merging(extra) { a, _ in a }, rest: rest)
    }

    /// Партия роли в рисунке (номера шагов — с 0). CLAP — тот же рисунок, что SNARE (решение 4.11).
    static func part(_ gr: Groove, _ role: Role) -> Part {
        let r: Role = role == .clap ? .snare : role
        switch (gr, r) {
        // HOUSE (118–126): бочка на каждую долю, хлопок на 2 и 4, открытый хэт на офбитах.
        case (.house, .kick): return .chance([with(fours, [15: 0.2]), with(fours, [3: 0.15, 10: 0.15])], ghosts: [])
        case (.house, .snare): return .chance([ghosts(ghostSteps, 0.1, main: [4, 12])], ghosts: ghostSteps)
        case (.house, .hat): return .chance([probs(offbeats, rest: 0.25), with(offbeats, [:], rest: 0.6)], ghosts: [])
        case (.house, .perc): return .euclid(3, 5, fromOne: false)
        // TECHNO (125–140, с Minimal): бочка на каждую долю, хлопок на 2 и 4 или только на 4, хэт 16-ми.
        case (.techno, .kick): return .chance([probs(fours), with(fours, [14: 0.25]), with(fours, [3: 0.15, 11: 0.15])], ghosts: [])
        case (.techno, .snare): return .chance([ghosts([7, 15], 0.08, main: [12]), ghosts([7, 15], 0.08, main: [4, 12])], ghosts: [7, 15])
        case (.techno, .hat): return .chance([probs(offbeats, rest: 0.5), with(offbeats, [:], rest: 0.85), scaled(probs(offbeats), 0.7)], ghosts: [])
        case (.techno, .perc): return .euclid(3, 5, fromOne: false)
        // BREAKS (< 150): ломаный бит — бочка 1, 3, 11, 12, малый 5 и 13, призрачные удары.
        case (.breaks, .kick): return .chance([probs([0: 1, 2: 0.6, 10: 1, 11: 0.5]), probs([0: 1, 7: 0.35, 10: 0.7, 2: 0.35])], ghosts: [])
        case (.breaks, .snare): return .chance([ghosts([7, 9, 14, 15], 0.45, main: [4, 12])], ghosts: [7, 9, 14, 15])
        case (.breaks, .hat): return .chance([scaled(probs(evens, rest: 0.2), 0.85)], ghosts: [])
        case (.breaks, .perc): return .euclid(3, 7, fromOne: false)
        // D&B (от 150): two-step — бочка 1 и 11, малый 5 и 13.
        case (.dnb, .kick): return .chance([probs([0: 1, 10: 1, 7: 0.25, 13: 0.2]), probs([0: 1, 10: 1, 2: 0.3])], ghosts: [])
        case (.dnb, .snare): return .chance([ghosts([7, 9, 14, 15], 0.15, main: [4, 12])], ghosts: [7, 9, 14, 15])
        case (.dnb, .hat): return .chance([scaled(probs(evens, rest: 0.2), 0.9)], ghosts: [])
        case (.dnb, .perc): return .euclid(3, 7, fromOne: false)
        // TRAP (от 115): половинный темп — малый на 9, хэт 8-ми и 16-ми с роллами (Ratchet).
        case (.trap, .kick): return .chance([probs([0: 1, 7: 0.4, 10: 0.5, 11: 0.3, 14: 0.3]), probs([0: 1, 6: 0.4, 7: 0.5, 11: 0.5])], ghosts: [])
        case (.trap, .snare): return .chance([ghosts([3, 6, 11, 14, 15], 0.12, main: [8])], ghosts: [3, 6, 11, 14, 15])
        case (.trap, .hat): return .chance([probs(evens, rest: 0.45)], ghosts: [])
        case (.trap, .perc): return .euclid(2, 5, fromOne: false)
        // R&B (< 115): малый 5 и 13, много призрачных ударов, хэт 16-ми, swing.
        case (.rnb, .kick): return .chance([probs([0: 1, 3: 0.25, 7: 0.4, 10: 0.6]), probs([0: 1, 8: 0.5, 10: 0.5])], ghosts: [])
        case (.rnb, .snare): return .chance([ghosts([3, 7, 9, 11, 14, 15], 0.3, main: [4, 12])], ghosts: [3, 7, 9, 11, 14, 15])
        case (.rnb, .hat): return .chance([probs(evens, rest: 0.5)], ghosts: [])
        case (.rnb, .perc): return .euclid(3, 7, fromOne: false)
        // POP (95–128): бочка 1 и 9 (или на каждую долю), малый 5 и 13, хэт 8-ми.
        case (.pop, .kick): return .chance([probs([0: 1, 8: 1, 10: 0.4, 7: 0.2]), probs(fours), probs([0: 1, 6: 0.5, 8: 1])], ghosts: [])
        case (.pop, .snare): return .chance([ghosts(ghostSteps, 0.06, main: [4, 12])], ghosts: ghostSteps)
        case (.pop, .hat): return .chance([probs(evens, rest: 0.15)], ghosts: [])
        case (.pop, .perc): return .euclid(2, 4, fromOne: false)
        // AMBIENT: редкие удары, у всех, кроме бочки, — Chance.
        case (.ambient, .kick): return .chance([probs([0: 1, 10: 0.2]), probs([0: 1])], ghosts: [])
        case (.ambient, .snare): return .chance([probs([12: 1])], ghosts: [])
        case (.ambient, .hat): return .chance([probs([:], rest: 0.3)], ghosts: [])
        default: return .euclid(2, 5, fromOne: false)
        }
    }

    static func scaled(_ a: [Double], _ k: Double) -> [Double] { return a.map { $0 * k } }

    /// Доля ударов HAT с роллом (p-lock Ratchet 2–4 удара).
    static func rollChance(_ gr: Groove, _ role: Role) -> Double {
        if role != .hat { return 0 }
        switch gr {
        case .trap: return 0.2
        case .rnb: return 0.08
        default: return 0
        }
    }

    /// p-lock Chance ударов (не на шаге 1): живой рисунок — у Ambient всех, кроме бочки, у Techno — хэта не на офбитах.
    static func liveChance(_ gr: Groove, _ role: Role, step: Int) -> Double? {
        switch gr {
        case .ambient: return role == .kick ? nil : 50
        case .techno: return role == .hat && step % 4 != 2 ? 75 : nil
        default: return nil
        }
    }

    /// Доля шага сбивки с ударом (шаги 13–16 последней страницы).
    static let fillChance: [Double] = [0.4, 0.6, 0.7, 0.6, 0.5]

    private static func hitVel<G: RandomNumberGenerator>(_ role: Role, step: Int, ghost: Bool,
                                                         using g: inout G) -> Double? {
        if role == .kick { return nil }
        if ghost { return Double.random(in: velGhost, using: &g).rounded() }
        if step % 4 == 0 { return velFull }
        return Double.random(in: velMid, using: &g).rounded()
    }

    /// Удар роли: velocity, ролл и Chance по рисунку.
    static func hit<G: RandomNumberGenerator>(_ gr: Groove, _ role: Role, step: Int, ghost: Bool,
                                              using g: inout G) -> Hit {
        var h = Hit(step: step, vel: hitVel(role, step: step, ghost: ghost, using: &g))
        let rc: Double = rollChance(gr, role)
        if rc > 0 && step % 4 != 0 && Double.random(in: 0..<1, using: &g) < rc {
            h.ratchet = Int.random(in: 1...3, using: &g)
        }
        if step > 0 { h.chance = liveChance(gr, role, step: step) }
        return h
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

    /// Основа: рисунок страницы длиной len (1…16) по партии движка в стиле (вариант — по bpm); не пустая.
    public static func base<G: RandomNumberGenerator>(_ role: Role, style: Int = 0, bpm: Double = 120, len: Int,
                                                      using g: inout G) -> [Hit] {
        let gr: Groove = groove(style, bpm: bpm)
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        var hits: [Hit] = []
        switch part(gr, role) {
        case .chance(let options, let gh):
            let pr: [Double] = options.count == 1 ? options[0] : options[Int.random(in: 0..<options.count, using: &g)]
            for s in 0..<n where pr[s] > 0 && Double.random(in: 0..<1, using: &g) < pr[s] {
                let ghost: Bool = gh.contains(s) && pr[s] < 1
                hits.append(hit(gr, role, step: s, ghost: ghost, using: &g))
            }
        case .euclid(let lo, let hi, let fromOne):
            let k: Int = Int.random(in: lo...hi, using: &g)
            let rot: Int = fromOne ? 0 : Int.random(in: 0..<n, using: &g)
            for s in euclid(k, n, rot: rot) {
                hits.append(hit(gr, role, step: s, ghost: false, using: &g))
            }
        }
        if hits.isEmpty {
            // Короткая страница без ударов партии (SNARE, CLAP на 1–4 шагах) или всё выпало: удар на середине.
            let s: Int = n >= 2 ? n / 2 : 0
            hits.append(hit(gr, role, step: s, ghost: false, using: &g))
        }
        return hits
    }

    /// Опорные удары, которые вариации не снимают: KICK — шаг 1, SNARE и CLAP — основные удары стиля (вероятность 1).
    static func anchor(_ role: Role, groove gr: Groove, _ s: Int) -> Bool {
        switch role {
        case .kick: return s == 0
        case .snare, .clap:
            if case .chance(let options, let gh) = part(gr, .snare) {
                return !gh.contains(s) && options.allSatisfy { $0[s] >= 1 }
            }
            return false
        default: return false
        }
    }

    /// Вариация: 1–2 удара добавлено или убрано (опорные не снимаются), в пределах len.
    public static func vary<G: RandomNumberGenerator>(_ hits: [Hit], role: Role, style: Int = 0, bpm: Double = 120,
                                                      len: Int, using g: inout G) -> [Hit] {
        let gr: Groove = groove(style, bpm: bpm)
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        var out: [Hit] = hits.filter { $0.step < n }
        let changes: Int = Int.random(in: 1...2, using: &g)
        for _ in 0..<changes {
            let removable: [Int] = out.indices.filter { !anchor(role, groove: gr, out[$0].step) }
            let used: Set<Int> = Set(out.map { $0.step })
            let free: [Int] = (0..<n).filter { !used.contains($0) }
            let remove: Bool = !removable.isEmpty && (free.isEmpty || Bool.random(using: &g))
            if remove, let i = removable.randomElement(using: &g), out.count > 1 {
                out.remove(at: i)
            } else if let s = free.randomElement(using: &g) {
                let ghost: Bool = (role == .snare || role == .clap) && s % 4 != 0
                out.append(hit(gr, role, step: s, ghost: ghost, using: &g))
            }
        }
        if out.isEmpty { out = base(role, style: style, bpm: bpm, len: n, using: &g) }
        return out.sorted { $0.step < $1.step }
    }

    /// Сбивка: последние 4 шага (из len) заново, хоть один удар.
    public static func fill<G: RandomNumberGenerator>(_ hits: [Hit], role: Role, style: Int = 0, bpm: Double = 120,
                                                      len: Int, using g: inout G) -> [Hit] {
        let gr: Groove = groove(style, bpm: bpm)
        let n: Int = Swift.max(1, Swift.min(Params.stepsPerPage, len))
        let from: Int = Swift.max(0, n - 4)
        var out: [Hit] = hits.filter { $0.step < from }
        let p: Double = fillChance[role.rawValue]
        var added: Int = 0
        for s in from..<n where Double.random(in: 0..<1, using: &g) < p {
            out.append(hit(gr, role, step: s, ghost: false, using: &g))
            added += 1
        }
        if added == 0 {
            let s: Int = Int.random(in: from..<n, using: &g)
            out.append(hit(gr, role, step: s, ghost: false, using: &g))
        }
        return out.sorted { $0.step < $1.step }
    }

    /// Ритм на страницы с длинами lens (шагов на странице, 0 — страница не играет): первая — основа (по своей
    /// длине), средние — вариации, последняя играющая — основа со сбивкой; одна страница — только основа.
    /// Основа не совпадает с avoid (шаги прошлого рисунка), если получится за 16 попыток.
    public static func pattern<G: RandomNumberGenerator>(_ role: Role, style: Int = 0, bpm: Double = 120, lens: [Int],
                                                         avoid: [Int]? = nil, using g: inout G) -> [[Hit]] {
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        var out: [[Hit]] = lens.map { _ in [] }
        guard let first = playing.first, let last = playing.last else { return out }
        var b: [Hit] = base(role, style: style, bpm: bpm, len: lens[first], using: &g)
        var tries: Int = 1
        while b.map({ $0.step }) == avoid && tries < 16 {
            b = base(role, style: style, bpm: bpm, len: lens[first], using: &g)
            tries += 1
        }
        out[first] = b
        if last == first { return out }
        for p in playing where p != first && p != last {
            out[p] = vary(b, role: role, style: style, bpm: bpm, len: lens[p], using: &g)
        }
        let lastBase: [Hit] = lens[last] >= lens[first] ? b : b.filter { $0.step < lens[last] }
        out[last] = fill(lastBase, role: role, style: style, bpm: bpm, len: lens[last], using: &g)
        return out
    }
}

extension Track {
    /// Ритм на страницы range открытого паттерна: прежние шаги этих страниц стираются (как у прогрессии), удары —
    /// нотой note длиной 1 шаг, velocity — p-lock Level шага, ролл — p-lock Ratchet, Chance — p-lock Chance.
    /// Страницы вне range не трогаются.
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
                if let r = h.ratchet { setLock(base + h.step, "ratchet", Double(r)) }
                if let c = h.chance { setLock(base + h.step, "prob", c) }
            }
        }
    }
}

extension Track {
    /// Ударная роль звука дорожки (KICK, SNARE, HAT, CLAP, PERC); иначе nil.
    public var drumRole: DrumRhythm.Role? { return DrumRhythm.role(engine: SynthKey.engine(sample)) }

    /// Ударная роль с учётом сэмпла (7.11): движок — как drumRole; сэмпл без маркеров нарезки — по имени файла
    /// name (DrumRhythm.role(name:)); нарезанный сэмпл — нарезка, не ударная.
    public func drumRole(name: String?) -> DrumRhythm.Role? {
        if let r = drumRole { return r }
        if sample.isEmpty || SynthKey.engine(sample) != nil || hasCuts { return nil }
        guard let n = name else { return nil }
        return DrumRhythm.role(name: n)
    }

    /// Случайный ритм стиля дорожки на страницы range (по их длинам) нотой note; вариант стиля — по bpm; avoid —
    /// шаги прошлой основы; r — роль (ударный сэмпл по имени), иначе по движку. Возвращает шаги новой основы (для
    /// следующего avoid); не ударная — nil, ничего не пишется.
    public mutating func writeRandomDrums<G: RandomNumberGenerator>(pages range: ClosedRange<Int>, note: Int,
                                                                    bpm: Double = 120, avoid: [Int]?,
                                                                    role r: DrumRhythm.Role? = nil,
                                                                    using g: inout G) -> [Int]? {
        guard let role = r ?? drumRole else { return nil }
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[DrumRhythm.Hit]] = DrumRhythm.pattern(role, style: drumStyle, bpm: bpm, lens: lens,
                                                             avoid: avoid, using: &g)
        writeDrums(pattern, note: note, pages: range)
        return pattern.first(where: { !$0.isEmpty })?.map { $0.step }
    }
}
