import Foundation

// MIDI-клок SEND (S13e, как sync.ts веба): 24 тика на четверть — 6 на шаг 1/16. Планировщик считает моменты тиков,
// Start и Stop (секунды хоста, когда слышен звук) на lookahead вперёд; отправляет MidiHost с метками времени CoreMIDI
// (вне колбэка, по таймеру UI). Без игры клок идёт с темпом проекта; при PLAY — Start в момент первого шага и первый
// тик тогда же (сетка тиков встаёт на старт), дальше тики — по сетке шагов секвенсора; стоп — Stop, клок идёт дальше.

public struct ClockPlan: Sendable {
    /// Сетка шагов при игре: следующий шаг step звучит в момент time, длина шага stepDur (с).
    public struct Grid: Equatable, Sendable {
        public var step: Int
        public var time: Double
        public var stepDur: Double

        public init(step: Int, time: Double, stepDur: Double) {
            self.step = step
            self.time = time
            self.stepDur = stepDur
        }
    }

    public enum Kind: Equatable, Sendable {
        case tick
        case start
        case stop

        /// Байт статуса MIDI.
        public var status: Int {
            switch self {
            case .tick: return 0xF8
            case .start: return 0xFA
            case .stop: return 0xFC
            }
        }
    }

    public struct Event: Equatable, Sendable {
        public var time: Double
        public var kind: Kind
    }

    public static let ticksPerStep: Int = 6

    /// Момент последнего запланированного тика; номер тика от старта (при игре).
    public private(set) var last: Double? = nil
    private var index: Int = 0
    public private(set) var playing: Bool = false

    public init() {}

    /// Клок выключили: при включении сетка начнётся заново.
    public mutating func reset() {
        last = nil
        playing = false
        index = 0
    }

    /// Новые события до now + lookahead. flush — отменить уже отправленные, но не прозвучавшие (старт: сетка
    /// тиков встаёт на первый шаг; уцелевшие тики свободного хода до старта отправлены заново в events).
    public mutating func update(now: Double, bpm: Double, play: Grid?, startStop: Bool,
                                lookahead: Double = 0.1) -> (flush: Bool, events: [Event]) {
        var out: [Event] = []
        var flush: Bool = false
        let until: Double = now + lookahead
        let period: Double = 60 / (bpm * 24)
        if let g = play {
            let tickDur: Double = g.stepDur / Double(ClockPlan.ticksPerStep)
            if !playing {
                playing = true
                let t0: Double = g.time - Double(g.step) * g.stepDur
                flush = true
                // Тики свободного хода, которые ещё не прозвучали и стоят раньше старта (не вплотную), — заново.
                if let l = last {
                    var free: [Event] = []
                    var t: Double = l
                    while t > now {
                        if t < t0 - period / 2 { free.append(Event(time: t, kind: .tick)) }
                        t -= period
                    }
                    out.append(contentsOf: free.reversed())
                }
                if startStop { out.append(Event(time: t0, kind: .start)) }
                out.append(Event(time: t0, kind: .tick))
                index = 0
                last = t0
            }
            while true {
                let m: Int = index + 1
                let t: Double = g.time + Double(m - g.step * ClockPlan.ticksPerStep) * tickDur
                if t > until { break }
                index = m
                // Отстали (приложение стояло) или сетка сдвинулась назад — тик пропускается.
                if t < now - tickDur || t <= (last ?? -Double.infinity) { continue }
                out.append(Event(time: t, kind: .tick))
                last = t
            }
            return (flush, out)
        }
        if playing {
            playing = false
            if startStop { out.append(Event(time: now, kind: .stop)) }
        }
        var next: Double = (last ?? now - period) + period
        if next < now - period { next = now }
        while next <= until {
            out.append(Event(time: next, kind: .tick))
            last = next
            next += period
        }
        return (flush, out)
    }
}
