import Foundation

// Настройки MIDI (бутерброд → MIDI, S13a; как settings.midiIn веба): в AppSettings, общие для проектов.
// Устройства — по uniqueID CoreMIDI (не меняется при переподключении). Канал и маршрут нот — у каждой дорожки
// (TrackMidi; прежние noteChannel и noteRoute при чтении пропускаются).

public struct MidiSettings: Codable, Equatable, Sendable {
    /// Вход: nil — ALL INPUTS, иначе uniqueID источника.
    public var input: Int32? = nil
    /// Выход обратной связи по умолчанию: nil — NONE (S13d).
    public var feedback: Int32? = nil
    /// Маппинги (S13b; MidiMapper.swift — условия и правка).
    public var mappings: [MidiMapping] = []
    /// Пресет маппингов, загруженный или сохранённый последним ("" — нет; S13c).
    public var preset: String = ""
    /// Нажатие ручки (KNOB c.r PRESS) — как палец на ручке: нажатие — касание, двойное — двойной тап (по умолчанию);
    /// OFF — действие из окна MIDI MAP (Action). Решение пользователя.
    public var pressTouch: Bool = true

    public init() {}

    private enum Keys: String, CodingKey { case input, feedback, mappings, preset, pressTouch }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        input = try? c.decode(Int32.self, forKey: .input)
        feedback = try? c.decode(Int32.self, forKey: .feedback)
        let maps: [LossyMapping] = (try? c.decode([LossyMapping].self, forKey: .mappings)) ?? []
        mappings = maps.compactMap { $0.value }
        preset = (try? c.decode(String.self, forKey: .preset)) ?? ""
        pressTouch = (try? c.decode(Bool.self, forKey: .pressTouch)) ?? true
    }

    /// Слушать ли источник (uniqueID).
    public func accepts(source: Int32) -> Bool {
        guard let i = input else { return true }
        return i == source
    }

    /// Касание клавиши для ноты с MIDI на дорожке track (id клавиши в модели): отрицательные, не пересекаются
    /// с касаниями пальцев; одна нота может играть на нескольких дорожках.
    public static func keyId(track: Int, channel: Int, note: Int) -> Int {
        return Int.min + 1 + (track * 16 + channel) * 128 + note
    }

    /// Сила ноты 0…1 (с VELOCITY; без него — полная, как в вебе).
    public static func velocity(_ v: Int, sensitive: Bool) -> Double {
        return sensitive ? Double(max(1, min(127, v))) / 127 : 1
    }
}
