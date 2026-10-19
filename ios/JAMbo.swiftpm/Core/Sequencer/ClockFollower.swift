import Foundation

// MIDI-клок RECEIVE (S13e, как sync.ts веба): время входящих тиков (секунды хоста) → темп по наклону последних 48
// тиков (наименьшие квадраты) и время каждого шага транспорта (шаг 1/16 = 6 тиков). С SYNC START/STOP: Start — игра
// с первого тика после Start, Continue — продолжить, Stop — стоп. Клока нет дольше 0,5 с — свой темп.

public struct ClockFollower: Sendable {
    public enum Action: Equatable, Sendable {
        /// Начать игру: шаг 0 — в момент at.
        case start(at: Double)
        case stop
    }

    public static let fitTicks: Int = 48
    public static let timeout: Double = 0.5

    private var times: [Double] = [Double](repeating: 0, count: ClockFollower.fitTicks)
    private var n: Int = 0
    /// Последний тик, интервал тика (с), тиков от Start, тик клока шага 0 транспорта.
    public private(set) var last: Double = 0
    public private(set) var interval: Double = 0
    private var count: Int = 0
    private var origin: Int = 0
    private var armed: Bool = false

    public init() {}

    /// Тик 0xF8 в момент at. Возвращает старт, если ждали первого тика после Start.
    public mutating func tick(at: Double) -> Action? {
        times[n % ClockFollower.fitTicks] = at
        n += 1
        last = at
        count += 1
        fit()
        if armed {
            armed = false
            count = 0
            origin = 0
            return .start(at: at)
        }
        return nil
    }

    /// Start, Continue, Stop (только с SYNC START/STOP — решает вызывающий).
    public mutating func transport(_ kind: MidiKind, at: Double, playing: Bool) -> Action? {
        switch kind {
        case .start:
            armed = true
            return playing ? .stop : nil
        case .cont:
            return playing ? nil : .start(at: at)
        case .stop:
            armed = false
            return playing ? .stop : nil
        default:
            return nil
        }
    }

    /// Клок идёт (последний тик не старше 0,5 с) и темп известен.
    public func alive(now: Double) -> Bool {
        return last > 0 && interval > 0 && now - last <= ClockFollower.timeout
    }

    /// Клок пропал: темп и счёт забываются.
    public mutating func lose() {
        n = 0
        last = 0
        interval = 0
        armed = false
    }

    /// Темп клока, BPM (nil — неизвестен).
    public var tempo: Double? {
        return last > 0 && interval > 0 ? 60 / (interval * 24) : nil
    }

    /// Транспорт стартовал (своей кнопкой, Continue или по Start) с шагом 0 в момент at: тик клока шага 0 — ближайший.
    public mutating func started(at: Double) {
        guard interval > 0 else { return }
        origin = count + Int(((at - last) / interval).rounded())
    }

    /// Момент шага step транспорта по клоку (без MIDI OFFSET); nil — темп неизвестен.
    public func stepTime(_ step: Int) -> Double? {
        guard tempo != nil else { return nil }
        let clockTick: Int = origin + step * ClockPlan.ticksPerStep
        return last + Double(clockTick - count) * interval
    }

    /// Наклон времени тиков по последним fitTicks — интервал тика.
    private mutating func fit() {
        let size: Int = ClockFollower.fitTicks
        let m: Int = Swift.min(n, size)
        if m < 4 {
            interval = n > 1 ? last - times[(n - 2) % size] : 0
            return
        }
        let base: Double = times[(n - m) % size]
        var sx: Double = 0
        var sy: Double = 0
        var sxx: Double = 0
        var sxy: Double = 0
        var k: Int = 0
        while k < m {
            let x: Double = Double(k)
            let y: Double = times[(n - m + k) % size] - base
            sx += x
            sy += y
            sxx += x * x
            sxy += x * y
            k += 1
        }
        let md: Double = Double(m)
        interval = (md * sxy - sx * sy) / (md * sxx - sx * sx)
    }
}
