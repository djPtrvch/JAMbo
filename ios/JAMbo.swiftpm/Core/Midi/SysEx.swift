import Foundation

// SysEx в универсальных пакетах CoreMIDI (UMP, тип 0x3 — 7-битные данные по 64 бита): до 6 байт в сообщении,
// статус 0 — целиком, 1 — начало, 2 — продолжение, 3 — конец. Байты — без F0 и F7. Без CoreMIDI — для тестов.

public enum SysEx7 {
    /// Слова UMP для отправки (по 2 на сообщение).
    public static func words(_ bytes: [UInt8], group: Int = 0) -> [UInt32] {
        var out: [UInt32] = []
        let total: Int = bytes.count
        var i: Int = 0
        repeat {
            let n: Int = min(6, total - i)
            let first: Bool = i == 0
            let last: Bool = i + n >= total
            let status: UInt32 = first && last ? 0 : (first ? 1 : (last ? 3 : 2))
            var b: [UInt32] = [0, 0, 0, 0, 0, 0]
            var k: Int = 0
            while k < n {
                b[k] = UInt32(bytes[i + k] & 0x7F)
                k += 1
            }
            let g: UInt32 = UInt32(group & 0xF)
            let w0: UInt32 = (0x3 << 28) | (g << 24) | (status << 20) | (UInt32(n) << 16) | (b[0] << 8) | b[1]
            let w1: UInt32 = (b[2] << 24) | (b[3] << 16) | (b[4] << 8) | b[5]
            out.append(w0)
            out.append(w1)
            i += n
        } while i < total
        return out
    }
}

/// Сборка входящего SysEx одного входа из сообщений UMP типа 0x3.
public struct SysExReader: Sendable {
    private var buf: [UInt8] = []
    private var open: Bool = false
    /// Длиннее — не наше (дампы и т. п.): отбрасывается.
    public static let maxBytes = 1024

    public init() {}

    /// Сообщение (два слова); готовый SysEx — байты без F0 и F7, иначе nil.
    public mutating func feed(_ w0: UInt32, _ w1: UInt32) -> [UInt8]? {
        guard w0 >> 28 == 0x3 else { return nil }
        let status: UInt32 = (w0 >> 20) & 0xF
        let n: Int = min(6, Int((w0 >> 16) & 0xF))
        let all: [UInt32] = [(w0 >> 8) & 0x7F, w0 & 0x7F, (w1 >> 24) & 0x7F, (w1 >> 16) & 0x7F, (w1 >> 8) & 0x7F, w1 & 0x7F]
        if status == 0 || status == 1 {
            buf = []
            open = true
        } else if !open {
            return nil
        }
        var k: Int = 0
        while k < n {
            buf.append(UInt8(all[k]))
            k += 1
        }
        if buf.count > SysExReader.maxBytes {
            buf = []
            open = false
            return nil
        }
        if status == 0 || status == 3 {
            open = false
            let done: [UInt8] = buf
            buf = []
            return done
        }
        return nil
    }
}
