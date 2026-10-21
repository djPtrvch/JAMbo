import Foundation

// MIDI дорожки (меню звука → MIDI): откуда дорожка принимает ноты и куда их отдаёт. Хранится в проекте, у каждой
// дорожки своё (заменило общую вкладку NOTES меню MIDI). Устройства — по uniqueID CoreMIDI; имя — чтобы показывать
// отключённое устройство.

public struct TrackMidi: Codable, Equatable, Sendable {
    /// Вход: принимать ли ноты, устройство (nil — ANY) и канал (0 — ALL: дорожка играет, только когда выбрана;
    /// 1–16 — играет всегда).
    public var inOn: Bool = true
    public var inDevice: Int32? = nil
    public var inName: String = ""
    public var inChannel: Int = 0
    /// Выход: устройство (nil — NONE: дорожка звучит сама) и канал 1–16. С выходом свой звук дорожки молчит —
    /// ноты уходят на устройство.
    public var outDevice: Int32? = nil
    public var outName: String = ""
    public var outChannel: Int = 1

    public init() {}

    private enum Keys: String, CodingKey { case inOn, inDevice, inName, inChannel, outDevice, outName, outChannel }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        inOn = c.value(.inOn, true)
        inDevice = c.optional(.inDevice)
        inName = c.value(.inName, "")
        let ic: Int = c.value(.inChannel, 0)
        inChannel = ic >= 0 && ic <= 16 ? ic : 0
        outDevice = c.optional(.outDevice)
        outName = c.value(.outName, "")
        let oc: Int = c.value(.outChannel, 1)
        outChannel = oc >= 1 && oc <= 16 ? oc : 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(inOn, forKey: .inOn)
        try c.encodeIfPresent(inDevice, forKey: .inDevice)
        try c.encode(inName, forKey: .inName)
        try c.encode(inChannel, forKey: .inChannel)
        try c.encodeIfPresent(outDevice, forKey: .outDevice)
        try c.encode(outName, forKey: .outName)
        try c.encode(outChannel, forKey: .outChannel)
    }

    /// Ноты уходят на устройство (свой звук молчит).
    public var sends: Bool { return outDevice != nil }

    /// Принимает ли дорожка ноту канала channel (0–15) с источника source; selected — дорожка выбрана.
    public func accepts(source: Int32, channel: Int, selected: Bool) -> Bool {
        if !inOn { return false }
        if let d = inDevice, d != source { return false }
        if inChannel == 0 { return selected }
        return channel == inChannel - 1
    }

    /// Дорожки, которые играют ноту (Note On) канала channel с источника source.
    public static func tracks(_ project: Project, source: Int32, channel: Int, selected: Int) -> [Int] {
        var out: [Int] = []
        for (t, tr) in project.tracks.enumerated() where tr.midi.accepts(source: source, channel: channel, selected: t == selected) {
            out.append(t)
        }
        return out
    }
}
