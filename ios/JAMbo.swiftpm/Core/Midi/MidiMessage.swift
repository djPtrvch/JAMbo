import Foundation

// Сообщения MIDI (S13a): разбор универсальных пакетов CoreMIDI (UMP, протокол MIDI 1.0) — без CoreMIDI, чтобы
// проверять тестами на Linux. Нужны ноты, CC и системные реального времени (клок, Start, Continue, Stop).

public enum MidiKind: Equatable, Sendable {
    case noteOn
    case noteOff
    case cc
    case clock
    case start
    case cont
    case stop
}

public struct MidiMessage: Equatable, Sendable {
    public var kind: MidiKind
    /// Канал 0–15 (у системных — 0).
    public var channel: Int
    /// Нота или номер CC.
    public var data1: Int
    /// Сила ноты или значение CC.
    public var data2: Int

    public init(kind: MidiKind, channel: Int = 0, data1: Int = 0, data2: Int = 0) {
        self.kind = kind
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
    }

    /// Реального времени (клок, Start, Continue, Stop) — идут мимо маппингов (как в вебе).
    public var isRealtime: Bool {
        return kind == .clock || kind == .start || kind == .cont || kind == .stop
    }

    /// Слов в сообщении UMP по его типу (старшие 4 бита первого слова).
    public static func wordCount(_ word: UInt32) -> Int {
        let mt: Int = Int(word >> 28)
        let sizes: [Int] = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
        return sizes[mt]
    }

    /// Одно сообщение из первого слова UMP: тип 0x2 — канальные MIDI 1.0, 0x1 — системные; остальное — nil.
    /// Note On с силой 0 — Note Off (как в MIDI 1.0).
    public static func parse(_ word: UInt32) -> MidiMessage? {
        let mt: UInt32 = word >> 28
        let status: Int = Int((word >> 16) & 0xFF)
        if mt == 0x1 {
            switch status {
            case 0xF8: return MidiMessage(kind: .clock)
            case 0xFA: return MidiMessage(kind: .start)
            case 0xFB: return MidiMessage(kind: .cont)
            case 0xFC: return MidiMessage(kind: .stop)
            default: return nil
            }
        }
        guard mt == 0x2 else { return nil }
        let type: Int = status & 0xF0
        let ch: Int = status & 0x0F
        let d1: Int = Int((word >> 8) & 0x7F)
        let d2: Int = Int(word & 0x7F)
        switch type {
        case 0x90: return MidiMessage(kind: d2 > 0 ? .noteOn : .noteOff, channel: ch, data1: d1, data2: d2)
        case 0x80: return MidiMessage(kind: .noteOff, channel: ch, data1: d1, data2: d2)
        case 0xB0: return MidiMessage(kind: .cc, channel: ch, data1: d1, data2: d2)
        default: return nil
        }
    }

    /// Все сообщения пакета (слова подряд; длинные — SysEx и MIDI 2.0 — пропускаются по своей длине).
    public static func parse(words: UnsafeBufferPointer<UInt32>) -> [MidiMessage] {
        var out: [MidiMessage] = []
        var i: Int = 0
        while i < words.count {
            let w: UInt32 = words[i]
            if let m = parse(w) { out.append(m) }
            i += wordCount(w)
        }
        return out
    }

    /// Слово UMP MIDI 1.0 (для тестов и обратной связи): статус, данные 1 и 2.
    public static func ump(status: Int, _ d1: Int, _ d2: Int, group: Int = 0) -> UInt32 {
        let mt: UInt32 = status >= 0xF0 ? 0x1 : 0x2
        let g: UInt32 = UInt32(group & 0xF)
        let s: UInt32 = UInt32(status & 0xFF)
        let a: UInt32 = UInt32(d1 & 0x7F)
        let b: UInt32 = UInt32(d2 & 0x7F)
        return (mt << 28) | (g << 24) | (s << 16) | (a << 8) | b
    }
}
