// Арпеджиатор (docs/ai/sequencer.md, «Арпеджиатор»): настройки дорожки и порядок нот. Звук — Sequencer/Arpeggiator.

/// Настройки арпеджиатора дорожки (хранятся в проекте). mode — режим кнопки CHORD: false — CHORD, true — ARP.
public struct TrackArp: Codable, Equatable, Sendable {
    public var mode: Bool = false
    public var on: Bool = false
    /// Направление (Arp.dirs).
    public var dir: Int = 0
    /// Скорость (Arp.rates), по умолчанию 1/16.
    public var rate: Int = 2
    /// Октавы 1…3.
    public var octaves: Int = 1
    /// Длина ноты, доля шага арпеджио 0.1…1.
    public var gate: Double = 0.5
    public var latch: Bool = false

    public init() {}

    enum CodingKeys: String, CodingKey, CaseIterable { case mode, on, dir, rate, octaves, gate, latch }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.value(.mode, false)
        on = c.value(.on, false)
        dir = Arp.clampDir(c.value(.dir, 0))
        rate = Arp.clampRate(c.value(.rate, 2))
        octaves = Arp.clampOctaves(c.value(.octaves, 1))
        gate = Arp.clampGate(c.value(.gate, 0.5))
        latch = c.value(.latch, false)
    }

    /// Арпеджио играет: режим ARP и включён.
    public var active: Bool { return mode && on }
}

public enum Arp {
    /// Направления (окно CHORD в режиме ARP; MIDI CHORD TYPE 1…6).
    public static let dirs: [String] = ["Up", "Down", "Up-Down", "Down-Up", "Random", "Order"]
    public static let up = 0, down = 1, upDown = 2, downUp = 3, random = 4, order = 5
    /// Скорости и их длина в шагах (шестнадцатых).
    public static let rates: [String] = ["1/8", "1/8T", "1/16", "1/16T", "1/32"]
    public static let rateSteps: [Double] = [2, 1.3333333333333333, 1, 0.6666666666666666, 0.5]
    public static let maxOctaves: Int = 3
    public static let gateMin: Double = 0.1

    public static func clampDir(_ d: Int) -> Int { return Swift.max(0, Swift.min(dirs.count - 1, d)) }
    public static func clampRate(_ r: Int) -> Int { return Swift.max(0, Swift.min(rates.count - 1, r)) }
    public static func clampOctaves(_ o: Int) -> Int { return Swift.max(1, Swift.min(maxOctaves, o)) }
    public static func clampGate(_ g: Double) -> Double { return Swift.max(gateMin, Swift.min(1, g)) }

    /// Ряд нот арпеджио: notes — в порядке нажатия (повторы убираются), направление dir (Random — как Up, выбор
    /// наугад — у движка), octaves — ряд выше на 1…2 октавы (ноты выше 127 не берутся). Up-Down и Down-Up не
    /// повторяют крайние ноты.
    public static func sequence(_ notes: [Int], dir: Int, octaves: Int) -> [Int] {
        var base: [Int] = []
        for n in notes where !base.contains(n) { base.append(n) }
        if dir != order { base.sort() }
        var row: [Int] = []
        let oc: Int = clampOctaves(octaves)
        for o in 0..<oc {
            for n in base {
                let m: Int = n + 12 * o
                if m <= 127 { row.append(m) }
            }
        }
        if row.count < 2 { return row }
        switch dir {
        case down:
            return row.reversed()
        case upDown:
            return row + row.dropFirst().dropLast().reversed()
        case downUp:
            let rev: [Int] = row.reversed()
            return rev + rev.dropFirst().dropLast().reversed()
        default:
            return row
        }
    }
}

/// Нота случайного арпеджио на шагах (SHIFT + тап в режиме ARP): шаг от начала выбранных страниц, нота, длина в шагах.
public struct ArpStepNote: Equatable, Sendable {
    public var step: Int
    public var note: Int
    public var len: Int
    /// Velocity — p-lock Level шага 0…127 (nil — без p-lock).
    public var vel: Double? = nil
}

extension Arp {
    /// Шаг сетки (шестнадцатых) для RATE: 1/8 и 1/8T — через шаг, 1/16, 1/16T, 1/32 — каждый шаг.
    public static let gridSteps: [Int] = [2, 2, 1, 1, 1]

    /// Аккорды в одну октаву от base (обращение: ноты выше — на октаву вниз, повторы убираются, по высоте):
    /// случайное арпеджио с OCTAVES 1 не выходит за октаву клавиатуры, OCTAVES 2–3 — ряд выше.
    public static func fold(_ chords: [[Int]], base: Int) -> [[Int]] {
        return chords.map { c in
            var out: [Int] = []
            for n in c {
                let m: Int = base + ((n - base) % 12 + 12) % 12
                if !out.contains(m) { out.append(m) }
            }
            return out.sorted()
        }
    }

    /// Аккорды поровну на steps шагов (четверть на аккорд при 4 аккордах), каждый — по направлению dir, с октавами,
    /// шагом по RATE и длиной по GATE (не меньше шага); Random — ноты аккорда наугад.
    public static func steps<G: RandomNumberGenerator>(_ chords: [[Int]], steps total: Int, dir: Int, octaves: Int,
                                                       rate: Int, gate: Double, using g: inout G) -> [ArpStepNote] {
        if chords.isEmpty || total <= 0 { return [] }
        let every: Int = gridSteps[clampRate(rate)]
        let len: Int = Swift.max(1, Int((clampGate(gate) * Double(every)).rounded()))
        let part: Int = Swift.max(1, total / chords.count)
        var out: [ArpStepNote] = []
        for (i, chord) in chords.enumerated() {
            let row: [Int] = sequence(chord, dir: dir, octaves: octaves)
            if row.isEmpty { continue }
            let start: Int = i * part
            let end: Int = i == chords.count - 1 ? total : Swift.min(total, start + part)
            var k: Int = 0
            var s: Int = start
            while s < end {
                let n: Int = dir == random ? row[Int.random(in: 0..<row.count, using: &g)] : row[k % row.count]
                out.append(ArpStepNote(step: s, note: n, len: Swift.min(len, end - s)))
                k += 1
                s += every
            }
        }
        return out
    }
}

extension Track {
    /// Случайное арпеджио на страницы range открытого паттерна: прежние шаги этих страниц стираются (как у
    /// прогрессии), ноты — по одной на шаг. Страницы вне range не трогаются.
    public mutating func writeArpSteps(_ notes: [ArpStepNote], pages range: ClosedRange<Int>) {
        let lo: Int = Swift.max(0, range.lowerBound)
        let hi: Int = Swift.min(pages.count - 1, range.upperBound)
        if lo > hi { return }
        changePages { ps in
            for p in lo...hi { ps[p] = Track.emptyPage() }
        }
        let base: Int = lo * Params.stepsPerPage
        let limit: Int = (hi - lo + 1) * Params.stepsPerPage
        for a in notes where a.step >= 0 && a.step < limit {
            withStep(base + a.step) { s in
                s.on = true
                s.notes = [a.note]
                s.setAllLen(a.len)
            }
            if let v = a.vel { setLock(base + a.step, "level", v) }
        }
    }
}
