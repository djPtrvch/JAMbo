import Foundation

// Бутерброд → SYNC (S13e): общие для проектов. SYNC QUANTUM — длина фразы в тактах
// (полоса фазы у BPM, выравнивание старта с Ableton Link); MIDI-клок — SEND (отдаём на один или несколько выходов)
// и RECEIVE (принимаем со входа) — по отдельности или вместе (8.11, решение пользователя: принять и раздать дальше);
// настройки Ableton Link пока только хранятся (Link — этап 9).

/// Прежний выбор SEND / RECEIVE (до 8.11) — только для чтения старых настроек.
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
    /// SEND — отдаём клок; RECEIVE — принимаем; можно оба сразу (принятый клок уходит на выходы).
    public var send: Bool = true
    public var receive: Bool = false
    /// Выходы клока при SEND (uniqueID); пусто — ALL OUTPUTS.
    public var clockOuts: [Int32] = []
    /// Вход клока при RECEIVE (S14d): nil — ALL INPUTS, иначе uniqueID; не зависит от входа в MIDI → DEVICES.
    public var clockIn: Int32? = nil
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


    /// Прежние ключи (до 8.11): source — SEND или RECEIVE, clockOut — один выход.

    /// Недостающие и испорченные поля — по умолчанию; квант и сдвиги — в своих пределах.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        let q: Int = c.value(CaseKey("quantum"), 1)
        quantum = SyncSettings.quanta.contains(q) ? q : 1
        clock = c.value(CaseKey("clock"), false)
        let old = try decoder.container(keyedBy: CaseKey.self)
        let src: ClockSource = old.value(CaseKey("source"), .send)
        send = c.value(CaseKey("send"), src == .send)
        receive = c.value(CaseKey("receive"), src == .receive)
        let one: Int32? = old.optional(CaseKey("clockOut"))
        clockOuts = c.value(CaseKey("clockOuts"), one.map { [$0] } ?? [])
        clockIn = c.optional(CaseKey("clockIn"))
        midiStartStop = c.value(CaseKey("midiStartStop"), true)
        midiOffset = SyncSettings.clampOffset(c.value(CaseKey("midiOffset"), 0))
        link = c.value(CaseKey("link"), false)
        linkNotify = c.value(CaseKey("linkNotify"), true)
        linkStartStop = c.value(CaseKey("linkStartStop"), false)
        linkOffset = SyncSettings.clampOffset(c.value(CaseKey("linkOffset"), 0))
    }

    /// Клок, Start, Continue, Stop с источника source принимаются (вход клока — ALL INPUTS или этот).
    public func acceptsClock(source: Int32) -> Bool {
        guard let i = clockIn else { return true }
        return i == source
    }

    /// Выход id в списке CLOCK OUTPUTS: выбран (ALL OUTPUTS — пусто).
    public func sendsTo(_ id: Int32) -> Bool {
        return clockOuts.isEmpty || clockOuts.contains(id)
    }

    /// Выход id добавить в CLOCK OUTPUTS или убрать; убран последний — снова ALL OUTPUTS.
    public mutating func toggleOut(_ id: Int32) {
        if let k = clockOuts.firstIndex(of: id) {
            clockOuts.remove(at: k)
        } else {
            clockOuts.append(id)
        }
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

extension SyncSettings {
    /// Запись — как прежняя синтезированная, по тем же ключам (общий CaseKey; объём сборки, 18.11).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(quantum, forKey: CaseKey("quantum"))
        try c.encode(clock, forKey: CaseKey("clock"))
        try c.encode(send, forKey: CaseKey("send"))
        try c.encode(receive, forKey: CaseKey("receive"))
        try c.encode(clockOuts, forKey: CaseKey("clockOuts"))
        try c.encodeIfPresent(clockIn, forKey: CaseKey("clockIn"))
        try c.encode(midiStartStop, forKey: CaseKey("midiStartStop"))
        try c.encode(midiOffset, forKey: CaseKey("midiOffset"))
        try c.encode(link, forKey: CaseKey("link"))
        try c.encode(linkNotify, forKey: CaseKey("linkNotify"))
        try c.encode(linkStartStop, forKey: CaseKey("linkStartStop"))
        try c.encode(linkOffset, forKey: CaseKey("linkOffset"))
    }
}
