// Случайный ритм ударных (SHIFT + CHORD на дорожке с KICK, SNARE, HAT, CLAP, PERC): рисунок страницы по
// вероятностям шагов движка в стиле проекта, вариации средних страниц и сбивка последней (docs/ai/sequencer.md, «Пианоролл»).
// Стиль — один на проект (у всех дорожек); Breaks / D&B и Trap / R&B выбирают вариант по темпу проекта.

/// Генератор случайных партий (без обобщений, 7.11).
public typealias Rng = SystemRandomNumberGenerator

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
    public static func roleByName(_ name: String) -> Role? {
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

    static let ghostSteps: [Int] = [3, 6, 9, 11, 14, 15]

    /// Шаги из строки (16 знаков, шаг 1 — слева): «x» — 1, «1»…«9» — 0,1…0,9, «.» — 0. Строки вместо литералов
    /// массивов — меньше кода в сборке Playgrounds (7.11).
    public static func pat(_ s: String) -> [Double] {
        var out: [Double] = []
        for c in s.utf8 {
            if c == 120 { out.append(1) } else if c >= 49 && c <= 57 { out.append(Double(c - 48) / 10) } else { out.append(0) }
        }
        while out.count < 16 { out.append(0) }
        return out
    }

    static func chance(_ opts: String, ghosts: [Int] = []) -> Part {
        let ps: [[Double]] = opts.split(separator: " ").map { pat(String($0)) }
        return .chance(ps, ghosts: ghosts)
    }

    /// Рисунки (номер Groove): KICK, SNARE (и CLAP), HAT — варианты через пробел.
    static let kicks: [String] = [
        "x...x...x...x..2 x..2x...x.2.x...",                       // house: на каждую долю
        "x...x...x...x... x...x...x...x.2. x..1x...x..1x...",      // techno
        "x.6.......x5.... x.3....3..7.....",                       // breaks: 1, 3, 11, 12
        "x......2..x..2.. x.3.......x.....",                       // dnb: two-step 1 и 11
        "x......4..53..3. x.....45...5....",                       // trap
        "x..2...4..6..... x.......5.5.....",                       // rnb
        "x......2x.4..... x...x...x...x... x.....5.x.......",      // pop: 1 и 9 или на каждую долю
        "x.........2..... x...............",                       // ambient
    ]
    static let snares: [String] = [
        "...1x.1..1.1x.11", "....x..1....x..1 .......1....x..1", "....x..4.4..x.44", "....x..2.2..x.22",
        "...1..1.x..1..11", "...3x..3.3.3x.33", "...1x.1..1.1x.11", "............x...",
    ]
    static let hats: [String] = [
        "22x222x222x222x2 66x666x666x666x6",                       // house: офбиты
        "55x555x555x555x5 88x888x888x888x8 ..7...7...7...7.",      // techno
        "8282828282828282", "9292929292929292",                    // breaks, dnb: восьмые
        "x4x4x4x4x4x4x4x4", "x5x5x5x5x5x5x5x5", "x1x1x1x1x1x1x1x1", // trap, rnb, pop
        "3333333333333333",                                        // ambient
    ]

    /// Призрачные шаги SNARE по рисунку.
    static func snareGhosts(_ gr: Groove) -> [Int] {
        switch gr {
        case .house, .pop: return ghostSteps
        case .techno: return [7, 15]
        case .breaks, .dnb: return [7, 9, 14, 15]
        case .trap: return [3, 6, 11, 14, 15]
        case .rnb: return [3, 7, 9, 11, 14, 15]
        case .ambient: return []
        }
    }

    /// Партия роли в рисунке (номера шагов — с 0). CLAP — тот же рисунок, что SNARE (решение 4.11); PERC — евклид.
    static func part(_ gr: Groove, _ role: Role) -> Part {
        let g: Int = gr.rawValue
        switch role {
        case .kick: return chance(kicks[g])
        case .snare, .clap: return chance(snares[g], ghosts: snareGhosts(gr))
        case .hat: return chance(hats[g])
        case .perc:
            switch gr {
            case .house, .techno: return .euclid(3, 5, fromOne: false)
            case .trap, .ambient: return .euclid(2, 5, fromOne: false)
            case .pop: return .euclid(2, 4, fromOne: false)
            default: return .euclid(3, 7, fromOne: false)
            }
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

    private static func hitVel(_ role: Role, step: Int, ghost: Bool,
                                                         using g: inout Rng) -> Double? {
        if role == .kick { return nil }
        if ghost { return Double.random(in: velGhost, using: &g).rounded() }
        if step % 4 == 0 { return velFull }
        return Double.random(in: velMid, using: &g).rounded()
    }

    /// Удар роли: velocity, ролл и Chance по рисунку.
    static func hit(_ gr: Groove, _ role: Role, step: Int, ghost: Bool,
                                              using g: inout Rng) -> Hit {
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
    public static func base(_ role: Role, style: Int = 0, bpm: Double = 120, len: Int,
                                                      using g: inout Rng) -> [Hit] {
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
    public static func vary(_ hits: [Hit], role: Role, style: Int = 0, bpm: Double = 120,
                                                      len: Int, using g: inout Rng) -> [Hit] {
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
    public static func fill(_ hits: [Hit], role: Role, style: Int = 0, bpm: Double = 120,
                                                      len: Int, using g: inout Rng) -> [Hit] {
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
    public static func pattern(_ role: Role, style: Int = 0, bpm: Double = 120, lens: [Int],
                                                         avoid: [Int]? = nil, using g: inout Rng) -> [[Hit]] {
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
    /// name (DrumRhythm.roleByName); нарезанный сэмпл — нарезка, не ударная.
    public func drumRoleBy(name: String?) -> DrumRhythm.Role? {
        if let r = drumRole { return r }
        if sample.isEmpty || SynthKey.engine(sample) != nil || hasCuts { return nil }
        guard let n = name else { return nil }
        return DrumRhythm.roleByName(n)
    }

    /// Случайный ритм стиля дорожки на страницы range (по их длинам) нотой note; вариант стиля — по bpm; avoid —
    /// шаги прошлой основы; r — роль (ударный сэмпл по имени), иначе по движку. Возвращает шаги новой основы (для
    /// следующего avoid); не ударная — nil, ничего не пишется.
    public mutating func writeRandomDrums(pages range: ClosedRange<Int>, note: Int,
                                                                    bpm: Double = 120, avoid: [Int]?,
                                                                    role r: DrumRhythm.Role? = nil,
                                                                    using g: inout Rng) -> [Int]? {
        guard let role = r ?? drumRole else { return nil }
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[DrumRhythm.Hit]] = DrumRhythm.pattern(role, style: drumStyle, bpm: bpm, lens: lens,
                                                             avoid: avoid, using: &g)
        writeDrums(pattern, note: note, pages: range)
        return pattern.first(where: { !$0.isEmpty })?.map { $0.step }
    }
}
