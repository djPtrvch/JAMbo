import Foundation

// Настройки MIDI (бутерброд → MIDI, S13a): в AppSettings, общие для проектов.
// Устройства — по uniqueID CoreMIDI (не меняется при переподключении). Канал и маршрут нот — у каждой дорожки
// (TrackMidi; прежние noteChannel и noteRoute при чтении пропускаются).

public struct MidiSettings: Codable, Equatable, Sendable {
    /// Устройства со своими маппингами (MidiDevices.swift; 18.11 — вместо общего списка маппингов, выхода обратной
    /// связи по умолчанию и пресетов: прежние при чтении пропускаются, решение пользователя).
    public var devices: [MidiDevice] = []
    /// Нажатие ручки (KNOB c.r PRESS) — как палец на ручке: нажатие — касание, двойное — двойной тап (по умолчанию);
    /// OFF — действие из окна MIDI MAP (Action). Решение пользователя.
    public var pressTouch: Bool = true
    /// JAMboPAD, разъём MIDI OUT (SET_MIDI_OUT): 0 OFF, 1 CLOCK (по умолчанию в пэде), 2 ALL; сообщения пэдов — туда же.
    public var padThru: Int = 1
    public var padControls: Bool = false

    public init() {
        addBuiltIns()
    }

    /// Прежний общий вход нот (input, до 8.11) при чтении пропускается: ноты — только у дорожек (TrackMidi), маппинги —
    /// со своего входа (MidiMapping).

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        devices = c.value(CaseKey("devices"), [])
        pressTouch = c.value(CaseKey("pressTouch"), true)
        padThru = c.value(CaseKey("padThru"), 1)
        padControls = c.value(CaseKey("padControls"), false)
        addBuiltIns()
    }

    /// Касание клавиши для ноты с MIDI на дорожке track (id клавиши в модели): отрицательные, не пересекаются
    /// с касаниями пальцев; одна нота может играть на нескольких дорожках.
    public static func keyId(track: Int, channel: Int, note: Int) -> Int {
        return Int.min + 1 + (track * 16 + channel) * 128 + note
    }

    /// Сила ноты 0…1 (с VELOCITY; без него — полная).
    public static func velocity(_ v: Int, sensitive: Bool) -> Double {
        return sensitive ? Double(max(1, min(127, v))) / 127 : 1
    }
}

extension MidiSettings {
    /// Запись — как прежняя синтезированная, по тем же ключам (общий CaseKey; объём сборки, 18.11).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(devices, forKey: CaseKey("devices"))
        try c.encode(pressTouch, forKey: CaseKey("pressTouch"))
        try c.encode(padThru, forKey: CaseKey("padThru"))
        try c.encode(padControls, forKey: CaseKey("padControls"))
    }
}
