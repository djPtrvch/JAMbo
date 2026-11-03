// Арпеджиатор (docs/ai/sequencer.md, «Арпеджиатор»): настройки дорожки и порядок нот. Звук — Sequencer/Arpeggiator.

/// Настройки арпеджиатора дорожки (хранятся в проекте). mode — режим кнопки CHORD: false — CHORD, true — ARP.
public struct TrackArp: Codable, Equatable, Sendable {
    public var mode: Bool = false
    public var on: Bool = false
    /// Направление (Arp.dirs).
    public var dir: Int = 0
    /// Скорость (Arp.rates), по умолчанию 1/16.
    public var rate: Int = 2
    /// Октавы 1…4.
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
    public static let maxOctaves: Int = 4
    public static let gateMin: Double = 0.1

    public static func clampDir(_ d: Int) -> Int { return Swift.max(0, Swift.min(dirs.count - 1, d)) }
    public static func clampRate(_ r: Int) -> Int { return Swift.max(0, Swift.min(rates.count - 1, r)) }
    public static func clampOctaves(_ o: Int) -> Int { return Swift.max(1, Swift.min(maxOctaves, o)) }
    public static func clampGate(_ g: Double) -> Double { return Swift.max(gateMin, Swift.min(1, g)) }

    /// Ряд нот арпеджио: notes — в порядке нажатия (повторы убираются), направление dir (Random — как Up, выбор
    /// наугад — у движка), octaves — ряд выше на 1…3 октавы (ноты выше 127 не берутся). Up-Down и Down-Up не
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
