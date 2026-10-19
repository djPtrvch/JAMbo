import Foundation

// Настройки MIDI (бутерброд → MIDI, S13a; как settings.midiIn, noteChannel, noteRoute веба): в AppSettings,
// общие для проектов. Устройства — по uniqueID CoreMIDI (не меняется при переподключении).

/// Куда идут ноты с входов: на выбранную дорожку или канал N → дорожка N.
public enum MidiNoteRoute: String, Codable, Sendable {
    case selected
    case channel
}

public struct MidiSettings: Codable, Equatable, Sendable {
    /// Вход: nil — ALL INPUTS, иначе uniqueID источника.
    public var input: Int32? = nil
    /// Выход обратной связи по умолчанию: nil — NONE (S13d).
    public var feedback: Int32? = nil
    /// Канал нот: 0 — ALL, 1–16.
    public var noteChannel: Int = 0
    public var noteRoute: MidiNoteRoute = .selected
    /// Маппинги (S13b; MidiMapper.swift — условия и правка).
    public var mappings: [MidiMapping] = []
    /// Пресет маппингов, загруженный или сохранённый последним ("" — нет; S13c).
    public var preset: String = ""

    public init() {}

    private enum Keys: String, CodingKey { case input, feedback, noteChannel, noteRoute, mappings, preset }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        input = try? c.decode(Int32.self, forKey: .input)
        feedback = try? c.decode(Int32.self, forKey: .feedback)
        let ch: Int = (try? c.decode(Int.self, forKey: .noteChannel)) ?? 0
        noteChannel = ch >= 0 && ch <= 16 ? ch : 0
        noteRoute = (try? c.decode(MidiNoteRoute.self, forKey: .noteRoute)) ?? .selected
        let maps: [LossyMapping] = (try? c.decode([LossyMapping].self, forKey: .mappings)) ?? []
        mappings = maps.compactMap { $0.value }
        preset = (try? c.decode(String.self, forKey: .preset)) ?? ""
    }

    /// Слушать ли источник (uniqueID).
    public func accepts(source: Int32) -> Bool {
        guard let i = input else { return true }
        return i == source
    }

    /// Дорожка для ноты (Note On или Off): чужой канал или канал без дорожки — nil.
    public func noteTrack(_ m: MidiMessage, selected: Int, tracks: Int) -> Int? {
        guard m.kind == .noteOn || m.kind == .noteOff else { return nil }
        if noteChannel > 0 && m.channel != noteChannel - 1 { return nil }
        if noteRoute == .selected { return selected }
        return m.channel < tracks ? m.channel : nil
    }

    /// Касание клавиши для ноты с MIDI (id клавиши в модели): отрицательные, не пересекаются с касаниями пальцев.
    public static func keyId(channel: Int, note: Int) -> Int {
        return Int.min + 1 + channel * 128 + note
    }

    /// Сила ноты 0…1 (с VELOCITY; без него — полная, как в вебе).
    public static func velocity(_ v: Int, sensitive: Bool) -> Double {
        return sensitive ? Double(max(1, min(127, v))) / 127 : 1
    }
}
