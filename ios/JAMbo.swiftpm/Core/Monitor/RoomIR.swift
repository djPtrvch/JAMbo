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
    public static let maxFrames = 52800
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

    /// Из WAV (4 канала, 48 кГц); неверный файл — nil. Длина — не больше maxFrames (1,1 с — клуб).
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
    /// хвост отдельно. Мощность — средняя по каждой полосе 1/12 октавы вокруг точек MonitorDesign (по бинам БПФ), а не
    /// в одной точке: частая гребёнка ранних отражений (салон) иначе проваливается между точками.
    public func response(sampleRate sr: Double) -> RoomResponse {
        let n: Int = frames
        let pts: Int = MonitorDesign.points
        var out = RoomResponse(count: pts)
        var size = 256
        while size < n { size *= 2 }
        let fft = PvFFT(size: size)
        let bins: Int = size / 2 + 1
        let x = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let re = UnsafeMutablePointer<Float>.allocate(capacity: 4 * bins)
        let im = UnsafeMutablePointer<Float>.allocate(capacity: 4 * bins)
        defer { x.deallocate(); re.deallocate(); im.deallocate() }
        // Масштаб БПФ — по единичному импульсу (|X| = 1 на всех частотах).
        x.initialize(repeating: 0, count: size)
        x[0] = 1
        fft.forward(x, re, im)
        let unit: Double = Double(re[1] * re[1] + im[1] * im[1])
        // 0 — прямая часть, 1 — хвост; левое и правое ухо.
        for part in 0..<2 {
            for ear in 0..<2 {
                x.update(repeating: 0, count: size)
                for i in 0..<n where (i < direct) == (part == 0) {
                    x[i] = h[ear * n + i] + h[(2 + ear) * n + i]
                }
                let at: Int = (part * 2 + ear) * bins
                fft.forward(x, re + at, im + at)
            }
        }
        let hzPerBin: Double = sr / Double(size)
        for k in 0..<pts {
            let lo: Double = 20 * pow(1000, Double(k) / Double(pts)) / hzPerBin
            let hi: Double = 20 * pow(1000, Double(k + 1) / Double(pts)) / hzPerBin
            var j0: Int = Int(lo.rounded(.up))
            var j1: Int = Int(hi.rounded(.up))
            if j1 <= j0 {
                j0 = Swift.min(bins - 1, Int((MonitorDesign.pointHz(k) / hzPerBin).rounded()))
                j1 = j0 + 1
            }
            j1 = Swift.min(j1, bins)
            var dd: Double = 0, dt: Double = 0, tt: Double = 0
            var j: Int = j0
            while j < j1 {
                for ear in 0..<2 {
                    let a: Int = ear * bins + j, b: Int = (2 + ear) * bins + j
                    let dr: Double = Double(re[a]), di: Double = Double(im[a])
                    let tr: Double = Double(re[b]), ti: Double = Double(im[b])
                    dd += dr * dr + di * di
                    dt += dr * tr + di * ti
                    tt += tr * tr + ti * ti
                }
                j += 1
            }
            let m: Double = 1 / (2 * Double(j1 - j0) * unit)
            out.dd[k] = dd * m
            out.dt[k] = dt * m
            out.tt[k] = tt * m
        }
        return out
    }
}

/// Отклик комнаты на частотах компенсации (средние по полосе, среднее ушей): |D|², Re(D·T*), |T|² прямой части D и
/// хвоста T.
public struct RoomResponse {
    public var dd: [Double]
    public var dt: [Double]
    public var tt: [Double]

    public init(count: Int) {
        dd = [Double](repeating: 0, count: count)
        dt = [Double](repeating: 0, count: count)
        tt = [Double](repeating: 0, count: count)
    }

    /// Мощность в полосе k при громкости хвоста amb: |D + amb·T|² в среднем.
    public func power(_ k: Int, _ amb: Double) -> Double {
        return dd[k] + 2 * amb * dt[k] + amb * amb * tt[k]
    }
}
