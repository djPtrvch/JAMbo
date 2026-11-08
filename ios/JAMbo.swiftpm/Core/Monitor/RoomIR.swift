import Foundation

// Room (Headphone Monitor, фаза 2): бинауральные импульсы комнат — Resources/Room*.wav и rooms.json (генератор —
// ios/tools/generate_rooms.py, HRTF FABIAN, CC BY 4.0; docs/LICENSES-room.md). WAV: 48 кГц, 4 канала — LL, LR, RL,
// RR (колонка → ухо: левая → левое, левая → правое, правая → левое, правая → правое), 16/24/32 бит или float.
// Прямая часть — первые direct отсчётов (128, 2,7 мс): на 0 dB всегда, остальное — хвост, его громкость — Ambience.

/// Комната из rooms.json (без Codable — объём сборки).
public struct RoomInfo {
    public var name: String
    public var file: String
    public var gainDb: Double
    public var direct: Int

    /// Список из rooms.json ({"rooms": […]}); ошибка — пусто.
    public static func list(_ data: Data?) -> [RoomInfo] {
        guard let d = data, let root = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let arr = root["rooms"] as? [[String: Any]] else { return [] }
        var out: [RoomInfo] = []
        for r in arr {
            guard let name = r["name"] as? String, let file = r["file"] as? String else { continue }
            let g: Double = (r["gain_db"] as? NSNumber)?.doubleValue ?? 0
            let dn: Int = (r["direct"] as? NSNumber)?.intValue ?? RoomConv.part
            out.append(RoomInfo(name: name, file: file, gainDb: g, direct: dn))
        }
        return out
    }
}

/// Импульсы комнаты: 4 пути (LL, LR, RL, RR) с громкостью из rooms.json, частота 48 кГц.
public final class RoomIR: @unchecked Sendable {
    public static let maxFrames = 14400
    public let name: String
    public let frames: Int
    public let direct: Int
    /// Пути подряд: [путь · frames + i].
    public let h: [Float]

    public init(name: String, paths: [Float], frames: Int, direct: Int) {
        self.name = name
        self.frames = frames
        self.direct = direct
        h = paths
    }

    /// Из WAV (4 канала, 48 кГц); неверный файл — nil. Длина — не больше maxFrames (300 мс).
    public convenience init?(name: String, wav: Data, gainDb: Double, direct: Int) {
        guard let w = RoomIR.parseWav(wav), w.channels == 4, w.rate == 48000, w.frames > 0 else { return nil }
        let n: Int = Swift.min(w.frames, RoomIR.maxFrames)
        let g: Float = Float(pow(10, gainDb / 20))
        var p = [Float](repeating: 0, count: 4 * n)
        for c in 0..<4 {
            for i in 0..<n { p[c * n + i] = w.samples[i * 4 + c] * g }
        }
        self.init(name: name, paths: p, frames: n, direct: Swift.max(0, direct))
    }

    /// WAV PCM 16/24/32 бит и float 32: каналы, частота, кадры, отсчёты подряд (кадр за кадром); иначе nil.
    public static func parseWav(_ d: Data) -> (channels: Int, rate: Int, frames: Int, samples: [Float])? {
        let b: [UInt8] = [UInt8](d)
        guard b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46 else { return nil }
        func u16(_ i: Int) -> Int { return Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { return u16(i) | u16(i + 2) << 16 }
        var at = 12
        var fmt = 0, ch = 0, rate = 0, bits = 0
        while at + 8 <= b.count {
            let id = String(bytes: b[at..<at + 4], encoding: .ascii) ?? ""
            let size: Int = u32(at + 4)
            let body: Int = at + 8
            if id == "fmt " && body + 16 <= b.count {
                fmt = u16(body)
                ch = u16(body + 2)
                rate = u32(body + 4)
                bits = u16(body + 14)
            } else if id == "data" {
                guard ch > 0, bits % 8 == 0, bits >= 16 else { return nil }
                let bytes: Int = bits / 8
                let end: Int = Swift.min(b.count, body + size)
                let n: Int = (end - body) / (bytes * ch)
                var out = [Float](repeating: 0, count: n * ch)
                var k = 0
                var i: Int = body
                while k < n * ch {
                    var v: Float = 0
                    if fmt == 3 && bytes == 4 {
                        v = Float(bitPattern: UInt32(u32(i)))
                    } else if bytes == 2 {
                        v = Float(Int16(truncatingIfNeeded: u16(i))) / 32768
                    } else if bytes == 3 {
                        let x: Int = Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16
                        v = Float(x >= 0x800000 ? x - 0x1000000 : x) / 8388608
                    } else if bytes == 4 {
                        v = Float(Int32(truncatingIfNeeded: u32(i))) / 2147483648
                    } else {
                        return nil
                    }
                    out[k] = v
                    k += 1
                    i += bytes
                }
                return (ch, rate, n, out)
            }
            at = body + size + (size & 1)
        }
        return nil
    }

    /// Отклик для Level compensation: сигнал в центре (L = R) — левое ухо LL + RL, правое LR + RR; прямая часть и
    /// хвост отдельно (комплексные, на тех же частотах, что MonitorDesign.compensation).
    public func response(sampleRate sr: Double) -> RoomResponse {
        let n: Int = frames
        let pts: Int = MonitorDesign.points
        var out = RoomResponse(count: pts)
        var left = [Double](repeating: 0, count: n)
        var right = [Double](repeating: 0, count: n)
        for i in 0..<n {
            left[i] = Double(h[i] + h[2 * n + i])
            right[i] = Double(h[n + i] + h[3 * n + i])
        }
        for k in 0..<pts {
            let w: Double = 2 * Double.pi * MonitorDesign.pointHz(k) / sr
            var a = (0.0, 0.0, 0.0, 0.0), t = (0.0, 0.0, 0.0, 0.0)
            // Поворот e^(−jwi) — рекуррентно (без cos/sin на каждый отсчёт).
            let cw: Double = cos(w), sw: Double = sin(w)
            var c: Double = 1, s: Double = 0
            for i in 0..<n {
                let lr: Double = left[i] * c, li: Double = -left[i] * s
                let rr: Double = right[i] * c, ri: Double = -right[i] * s
                if i < direct {
                    a.0 += lr; a.1 += li; a.2 += rr; a.3 += ri
                } else {
                    t.0 += lr; t.1 += li; t.2 += rr; t.3 += ri
                }
                let c2: Double = c * cw - s * sw
                s = s * cw + c * sw
                c = c2
            }
            out.d[4 * k] = a.0; out.d[4 * k + 1] = a.1; out.d[4 * k + 2] = a.2; out.d[4 * k + 3] = a.3
            out.t[4 * k] = t.0; out.t[4 * k + 1] = t.1; out.t[4 * k + 2] = t.2; out.t[4 * k + 3] = t.3
        }
        return out
    }
}

/// Отклик комнаты на частотах компенсации: на точку [Re L, Im L, Re R, Im R] прямой части (d) и хвоста (t).
public struct RoomResponse {
    public var d: [Double]
    public var t: [Double]

    public init(count: Int) {
        d = [Double](repeating: 0, count: 4 * count)
        t = [Double](repeating: 0, count: 4 * count)
    }

    /// Мощность в точке k при громкости хвоста amb: среднее ушей |D + amb·T|².
    public func power(_ k: Int, _ amb: Double) -> Double {
        let lr: Double = d[4 * k] + amb * t[4 * k], li: Double = d[4 * k + 1] + amb * t[4 * k + 1]
        let rr: Double = d[4 * k + 2] + amb * t[4 * k + 2], ri: Double = d[4 * k + 3] + amb * t[4 * k + 3]
        return 0.5 * (lr * lr + li * li + rr * rr + ri * ri)
    }
}
