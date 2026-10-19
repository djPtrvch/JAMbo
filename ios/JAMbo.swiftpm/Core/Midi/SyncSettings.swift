import Foundation

// Бутерброд → SYNC (S13e, как settings.sync веба): общие для проектов. SYNC QUANTUM — длина фразы в тактах
// (полоса фазы у BPM, выравнивание старта с Ableton Link); MIDI-клок — SEND (отдаём) или RECEIVE (принимаем со входа
// из MIDI → DEVICES); настройки Ableton Link пока только хранятся (Link — этап 9).

public enum ClockSource: String, Codable, Sendable {
    case send
    case receive
}

public struct SyncSettings: Codable, Equatable, Sendable {
    public static let quanta: [Int] = [1, 2, 4, 8]
    /// Пределы OFFSET, мс.
    public static let offsetMax: Int = 200

    /// Тактов во фразе: 1, 2, 4 или 8.
    public var quantum: Int = 1
    /// MIDI CLOCK SYNC.
    public var clock: Bool = false
    public var source: ClockSource = .send
    /// Выход клока при SEND: nil — ALL OUTPUTS, иначе uniqueID.
    public var clockOut: Int32? = nil
    /// SYNC START/STOP клока: SEND — Start и Stop с PLAY; RECEIVE — Start, Continue, Stop управляют игрой.
    public var midiStartStop: Bool = true
    /// Сдвиг клока, мс (−200…+200): плюс — отдаваемый клок позже, при приёме — свои шаги позже тиков.
    public var midiOffset: Int = 0
    /// Ableton Link (этап 9): включение, уведомления о участниках, SYNC START/STOP, сдвиг — только хранятся.
    public var link: Bool = false
    public var linkNotify: Bool = true
    public var linkStartStop: Bool = false
    public var linkOffset: Int = 0

    public init() {}

    private enum Keys: String, CodingKey {
        case quantum, clock, source, clockOut, midiStartStop, midiOffset, link, linkNotify, linkStartStop, linkOffset
    }

    /// Недостающие и испорченные поля — по умолчанию; квант и сдвиги — в своих пределах.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let q: Int = (try? c.decode(Int.self, forKey: .quantum)) ?? 1
        quantum = SyncSettings.quanta.contains(q) ? q : 1
        clock = (try? c.decode(Bool.self, forKey: .clock)) ?? false
        source = (try? c.decode(ClockSource.self, forKey: .source)) ?? .send
        clockOut = try? c.decode(Int32.self, forKey: .clockOut)
        midiStartStop = (try? c.decode(Bool.self, forKey: .midiStartStop)) ?? true
        midiOffset = SyncSettings.clampOffset((try? c.decode(Int.self, forKey: .midiOffset)) ?? 0)
        link = (try? c.decode(Bool.self, forKey: .link)) ?? false
        linkNotify = (try? c.decode(Bool.self, forKey: .linkNotify)) ?? true
        linkStartStop = (try? c.decode(Bool.self, forKey: .linkStartStop)) ?? false
        linkOffset = SyncSettings.clampOffset((try? c.decode(Int.self, forKey: .linkOffset)) ?? 0)
    }

    public static func clampOffset(_ v: Int) -> Int {
        return Swift.max(-offsetMax, Swift.min(offsetMax, v))
    }

    /// Отрезков полосы фазы: 4 доли на такт × квант.
    public var phaseSegments: Int { return 4 * quantum }

    /// Горящих отрезков полосы фазы на доле beat от старта (−1 — стоп): до текущей доли фразы включительно.
    public func phaseLit(beat: Int) -> Int {
        if beat < 0 { return 0 }
        return beat % phaseSegments + 1
    }
}
