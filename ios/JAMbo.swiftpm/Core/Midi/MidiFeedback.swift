import Foundation

// Обратная связь MIDI (S13d, как sendFeedback в midi.ts веба): значения ручек и состояние кнопок уходят на выход
// маппинга — кольца и подсветка энкодеров повторяют экран. Только действующие маппинги, только изменения.
// Без CoreMIDI — проверяется тестами; отправка — MidiHost.

/// Последние отправленные значения по выходу и источнику.
public struct MidiFeedback: Sendable {
    private var sent: [String: Int] = [:]

    public init() {}

    /// Забыть отправленное (выходы переподключились — шлём всё заново).
    public mutating func reset() {
        sent = [:]
    }

    public static func key(dest: Int32, src: MidiSource) -> String {
        return "\(dest):\(src.type.rawValue):\(src.ch):\(src.num)"
    }

    /// Значение изменилось — слать (и запомнить).
    public mutating func change(dest: Int32, src: MidiSource, value: Int) -> Bool {
        let k: String = MidiFeedback.key(dest: dest, src: src)
        if sent[k] == value { return false }
        sent[k] = value
        return true
    }

    /// Слово UMP MIDI 1.0: CC или Note On (сила — значение; 0 — гаснет) на канале источника.
    public static func word(_ src: MidiSource, value: Int) -> UInt32 {
        let status: Int = (src.type == .cc ? 0xB0 : 0x90) | (src.ch & 0x0F)
        return MidiMessage.ump(status: status, src.num, value)
    }
}

extension MidiMapping {
    /// Значение 0–1 цели → 0–127 в диапазоне маппинга (Range; Invert — наоборот); пустой диапазон — 0.
    public func feedbackValue(_ norm: Double) -> Int {
        let span: Double = max - min
        if span == 0 { return 0 }
        let x: Double = Swift.min(1, Swift.max(0, (norm - min) / span))
        return Int((x * 127).rounded())
    }

    /// Выход обратной связи: Default — выход из DEVICES (feedback), None — нет, иначе свой.
    public func feedbackDest(default def: Int32?) -> Int32? {
        switch port {
        case .standard: return def
        case .none: return nil
        case .device(let id): return id
        }
    }
}

extension MidiSettings {
    /// Действующие маппинги для обратной связи: у источника (с входом) — самое точное из действующих условий.
    /// Нажатие ручки (PRESS) не шлёт ничего: у энкодеров с кнопкой (Twister) этот источник задаёт цвет подсветки.
    public func feedbackMappings(_ ctx: MidiContext) -> [MidiMapping] {
        let conds: [String] = ctx.conds
        var best: [String: (rank: Int, m: MidiMapping)] = [:]
        var order: [String] = []
        for m in mappings {
            if case .press = m.target { continue }
            guard let r = conds.firstIndex(of: m.condKey) else { continue }
            let input: String = m.input.map { String($0) } ?? "*"
            let k: String = input + ":" + MidiFeedback.key(dest: 0, src: m.src)
            if let b = best[k] {
                if r < b.rank { best[k] = (r, m) }
            } else {
                best[k] = (r, m)
                order.append(k)
            }
        }
        return order.compactMap { best[$0]?.m }
    }
}
