import Foundation

// Бутерброд → SYNC (S13e, как settings.sync веба): общие для проектов. SYNC QUANTUM — длина фразы в тактах
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
    /// Ноты с входа клока (8.11, решение пользователя): по умолчанию при приёме клока не играют дорожки (у ведущего
    /// устройства свои ноты); ON — принимаются, как с любого входа.
    public var clockNotes: Bool = false
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

    private enum CodingKeys: String, CodingKey {
        case quantum, clock, send, receive, clockOuts, clockIn, clockNotes, midiStartStop, midiOffset, link, linkNotify, linkStartStop,
             linkOffset
    }

    /// Прежние ключи (до 8.11): source — SEND или RECEIVE, clockOut — один выход.
    private enum LegacyKeys: String, CodingKey { case source, clockOut }

    /// Недостающие и испорченные поля — по умолчанию; квант и сдвиги — в своих пределах.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let q: Int = c.value(.quantum, 1)
        quantum = SyncSettings.quanta.contains(q) ? q : 1
        clock = c.value(.clock, false)
        let old = try decoder.container(keyedBy: LegacyKeys.self)
        let src: ClockSource = old.value(.source, .send)
        send = c.value(.send, src == .send)
        receive = c.value(.receive, src == .receive)
        let one: Int32? = old.optional(.clockOut)
        clockOuts = c.value(.clockOuts, one.map { [$0] } ?? [])
        clockIn = c.optional(.clockIn)
        clockNotes = c.value(.clockNotes, false)
        midiStartStop = c.value(.midiStartStop, true)
        midiOffset = SyncSettings.clampOffset(c.value(.midiOffset, 0))
        link = c.value(.link, false)
        linkNotify = c.value(.linkNotify, true)
        linkStartStop = c.value(.linkStartStop, false)
        linkOffset = SyncSettings.clampOffset(c.value(.linkOffset, 0))
    }

    /// Клок, Start, Continue, Stop с источника source принимаются (вход клока — ALL INPUTS или этот).
    public func acceptsClock(source: Int32) -> Bool {
        guard let i = clockIn else { return true }
        return i == source
    }

    /// Ноты с входа source не играют: идёт приём клока, ноты с входа клока выключены, и source — вход клока
    /// (выбранный; при ALL INPUTS — тот, с которого пришёл последний тик, clockSource; 0 — клока ещё не было).
    public func blocksNotes(source: Int32, clockSource: Int32) -> Bool {
        if !clock || !receive || clockNotes { return false }
        if let i = clockIn { return i == source }
        return clockSource != 0 && clockSource == source
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
