import Foundation

/// Сверка TEXTURE и GRANULAR с веб-прототипом (ios/tools/texture/proto.mjs → proto.json): RMS и третьоктавные полосы
/// (25 Гц–16 кГц) так же, как в proto.mjs; WAV контрольных положений — в каталог TEXGRAN_WAV (если задан).
enum ProtoCompare {
    struct Ref {
        let k: [Double]
        let rms: Double
        let peak: Double
        let bands: [Double]
    }

    static let file: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("tools/texture/proto.json")

    static func load() -> [String: Ref] {
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        var out: [String: Ref] = [:]
        for (name, v) in obj {
            let k = v["k"] as? [Double] ?? []
            let l = v["rmsL"] as? Double ?? 0, r = v["rmsR"] as? Double ?? 0
            let b = (v["bands"] as? [[String: Any]] ?? []).map { $0["db"] as? Double ?? -300 }
            out[name] = Ref(k: k, rms: (l + r) / 2, peak: v["peak"] as? Double ?? 0, bands: b)
        }
        return out
    }

    /// RMS (среднее каналов), пик и полосы, dB.
    static func stats(_ l: [Float], _ r: [Float], sr: Double = 48000) -> (rms: Double, peak: Double, bands: [Double]) {
        var sl = 0.0, sr2 = 0.0, peak = 0.0
        for i in 0..<l.count {
            sl += Double(l[i]) * Double(l[i])
            sr2 += Double(r[i]) * Double(r[i])
            peak = max(peak, abs(Double(l[i])), abs(Double(r[i])))
        }
        let rms = (sqrt(sl / Double(l.count)) + sqrt(sr2 / Double(r.count))) / 2
        let n = 8192
        var bins = [Double](repeating: 0, count: n / 2)
        var frames = 0
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        var s = 0
        while s + n <= l.count {
            for i in 0..<n {
                let w = 0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n - 1)))
                re[i] = (Double(l[s + i]) + Double(r[s + i])) * 0.5 * w
                im[i] = 0
            }
            fft(&re, &im)
            for k in 0..<(n / 2) { bins[k] += re[k] * re[k] + im[k] * im[k] }
            frames += 1
            s += n / 2
        }
        var bands: [Double] = []
        for b in -16...12 {
            let fc = 1000 * pow(2, Double(b) / 3)
            let lo = fc * pow(2, -1.0 / 6), hi = fc * pow(2, 1.0 / 6)
            var p = 0.0
            var k = Int((lo * Double(n) / sr).rounded(.up))
            while k <= Int((hi * Double(n) / sr).rounded(.down)) && k < n / 2 {
                p += bins[k]
                k += 1
            }
            bands.append(10 * log10(p / Double(max(1, frames)) + 1e-30))
        }
        return (rms, peak, bands)
    }

    /// Статистика runs прогонов: RMS и полосы — среднее по мощности, пик — наибольший (как в proto.mjs).
    static func average(_ runs: Int, _ body: (Int) -> ([Float], [Float])) -> (rms: Double, peak: Double, bands: [Double]) {
        var p = 0.0, peak = 0.0
        var bands: [Double] = []
        for k in 0..<runs {
            let (l, r) = body(k)
            let s = stats(l, r)
            p += s.rms * s.rms
            peak = max(peak, s.peak)
            if bands.isEmpty { bands = [Double](repeating: 0, count: s.bands.count) }
            for i in 0..<s.bands.count { bands[i] += pow(10, s.bands[i] / 10) }
        }
        return (sqrt(p / Double(runs)), peak, bands.map { 10 * log10($0 / Double(runs)) })
    }

    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var len = 2
        while len <= n {
            let a = -2 * Double.pi / Double(len)
            let wr = cos(a), wi = sin(a)
            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0
                for q in 0..<(len / 2) {
                    let ur = re[i + q], ui = im[i + q]
                    let xr = re[i + q + len / 2], xi = im[i + q + len / 2]
                    let vr = xr * cr - xi * ci, vi = xr * ci + xi * cr
                    re[i + q] = ur + vr
                    im[i + q] = ui + vi
                    re[i + q + len / 2] = ur - vr
                    im[i + q + len / 2] = ui - vi
                    let t = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = t
                }
                i += len
            }
            len <<= 1
        }
    }

    /// WAV 16 бит стерео в каталог TEXGRAN_WAV (для прослушивания рядом с proto_<имя>.wav).
    static func wav(_ name: String, _ l: [Float], _ r: [Float], sr: Int = 48000) {
        guard let dir = ProcessInfo.processInfo.environment["TEXGRAN_WAV"] else { return }
        var d = Data()
        func u32(_ x: Int) { var v = UInt32(x).littleEndian; d.append(Data(bytes: &v, count: 4)) }
        func u16(_ x: Int) { var v = UInt16(x).littleEndian; d.append(Data(bytes: &v, count: 2)) }
        d.append("RIFF".data(using: .ascii)!)
        u32(36 + l.count * 4)
        d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(2); u32(sr); u32(sr * 4); u16(4); u16(16)
        d.append("data".data(using: .ascii)!)
        u32(l.count * 4)
        for i in 0..<l.count {
            u16(Int(Int16(max(-1, min(1, l[i])) * 32767)) & 0xFFFF)
            u16(Int(Int16(max(-1, min(1, r[i])) * 32767)) & 0xFFFF)
        }
        try? d.write(to: URL(fileURLWithPath: dir).appendingPathComponent("swift_\(name).wav"))
    }
}
