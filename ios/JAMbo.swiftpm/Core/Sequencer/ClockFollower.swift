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
    public static let minTicks: Int = 4
    /// Интервал больше стольких обычных — пауза (тики опоздали или пропали).
    public static let gapRatio: Double = 2.5
    public static let gapMin: Double = 0.06
    /// Тик раньше половины интервала — из пачки (USB отдал задержанные тики разом): в темп не идёт.
    public static let burstRatio: Double = 0.5
    /// Столько тиков подряд не в темп — темп сменился (Digitakt и т. п.): окно заново.
    public static let rejectLimit: Int = 6

    /// Окно темпа: номер тика (счёт от появления клока) и время — прямая «время от номера» наименьшими квадратами.
    /// Тики пачки и опоздавшие в окно не идут, но считаются — привязка шагов не сдвигается.
    private var xs: [Double] = [Double](repeating: 0, count: ClockFollower.fitTicks)
    private var times: [Double] = [Double](repeating: 0, count: ClockFollower.fitTicks)
    private var n: Int = 0
    /// Время прихода последнего тика, интервал тика (с) — наклон прямой, тиков от появления клока, тик клока шага 0.
    public private(set) var last: Double = 0
    public private(set) var interval: Double = 0
    private var count: Int = 0
    private var origin: Int = 0
    private var armed: Bool = false
    /// Шаг 0 транспорта привязан к тику клока (started). После пропажи клока привязки нет: счёт тиков стоял, пока
    /// транспорт шёл, — шаги надо привязать заново к ближайшему тику.
    public private(set) var anchored: Bool = false
    /// Прямая: время тика с номером x — fitA + fitB·(x − fitX).
    private var fitA: Double = 0
    private var fitX: Double = 0
    /// После паузы: сколько тиков должно было прийти за неё (опоздавшие придут пачкой — их не досчитывать).
    private var debt: Int = 0
    private var rejected: Int = 0

    public init() {}

    /// Тик 0xF8 в момент at. Возвращает старт, если ждали первого тика после Start.
    public mutating func tick(at: Double) -> Action? {
        // USB отдаёт тики то с задержкой, то пачкой: пауза больше 2,5 интервала — тики опоздали или пропали (долг),
        // тик пачки (раньше половины интервала) гасит долг; обычный тик после паузы — недошедшие тики пропали,
        // досчитываются. Опоздавшие и пачка — в счёт, но не в темп (по ним темп скакал в разы — секвенсор вставал).
        let ref: Double = interval
        var fits: Bool = true
        if last > 0 && ref > 0 {
            let gap: Double = at - last
            let limit: Double = Swift.max(ref * ClockFollower.gapRatio, ClockFollower.gapMin)
            if gap > limit {
                debt += Swift.max(0, Int((gap / ref).rounded()) - 1)
                fits = false
            } else if gap < ref * ClockFollower.burstRatio {
                if debt > 0 { debt -= 1 }
                fits = false
            } else if gap > ref * 1.5 {
                fits = false
            } else if debt > 0 {
                count += debt
                debt = 0
            }
        }
        last = at
        count += 1
        if fits {
            rejected = 0
            add(at)
        } else {
            rejected += 1
            if rejected >= ClockFollower.rejectLimit {
                // Темп сменился (или пачки не кончаются): окно — заново с этого тика, долг — забыт.
                n = 0
                debt = 0
                rejected = 0
                add(at)
            }
        }
        if armed {
            armed = false
            origin = count - 1
            return .start(at: at)
        }
        return nil
    }

    private mutating func add(_ at: Double) {
        let k: Int = n % ClockFollower.fitTicks
        xs[k] = Double(count - 1)
        times[k] = at
        n += 1
        fit()
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
        return tempo != nil && now - last <= ClockFollower.timeout
    }

    /// Клок пропал: темп и счёт забываются.
    public mutating func lose() {
        n = 0
        last = 0
        interval = 0
        count = 0
        debt = 0
        rejected = 0
        armed = false
        anchored = false
    }

    /// Темп клока, BPM (nil — неизвестен). Первые тики после появления клока (меньше minTicks) — без темпа: интервал
    /// по одному-двум тикам дрожит (USB), звук бы дёргался.
    public var tempo: Double? {
        return last > 0 && interval > 0 && n >= ClockFollower.minTicks ? 60 / (interval * 24) : nil
    }

    /// Транспорт стартовал (своей кнопкой, Continue или по Start) с шагом 0 в момент at: тик клока шага 0 — ближайший.
    public mutating func started(at: Double) {
        guard interval > 0 else { return }
        origin = Int((fitX + (at - fitA) / interval).rounded())
        anchored = true
    }

    /// Момент шага step транспорта по клоку (без MIDI OFFSET) — по прямой окна; nil — темп неизвестен.
    public func stepTime(_ step: Int) -> Double? {
        guard tempo != nil else { return nil }
        let clockTick: Int = origin + step * ClockPlan.ticksPerStep
        return fitA + (Double(clockTick) - fitX) * interval
    }

    /// Прямая по окну (до fitTicks тиков): наклон — интервал тика, точка — середина окна.
    private mutating func fit() {
        let size: Int = ClockFollower.fitTicks
        let m: Int = Swift.min(n, size)
        var mx: Double = 0
        var my: Double = 0
        var k: Int = 0
        while k < m {
            let i: Int = (n - m + k) % size
            mx += xs[i]
            my += times[i]
            k += 1
        }
        mx /= Double(m)
        my /= Double(m)
        var sxx: Double = 0
        var sxy: Double = 0
        k = 0
        while k < m {
            let i: Int = (n - m + k) % size
            let dx: Double = xs[i] - mx
            sxx += dx * dx
            sxy += dx * (times[i] - my)
            k += 1
        }
        fitX = mx
        fitA = my
        if m >= 2 && sxx > 0 {
            interval = sxy / sxx
        } else if m < 2 {
            interval = 0
        }
    }
}
