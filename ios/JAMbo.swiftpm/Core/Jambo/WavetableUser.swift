import Foundation

// Свои таблицы WTABLE из WAV (S11b4, как parseWav, autoFrameSize, wavSpectra веба): PCM 16/24/32 бит или float 32,
// у стерео — левый канал; размер кадра — из метки Serum ('clm ') или выбором 256…2048 / AUTO; до 256 кадров, файл
// до 4 МБ. Байты WAV хранятся как есть (без пересчёта частоты) — Application Support/Tables/<ключ>.wav.

public struct WavTable: Equatable, Sendable {
    public var samples: [Float]
    /// Размер кадра из метки 'clm ' (Serum); nil — нет метки.
    public var clm: Int?
}

public enum WtWav {
    public static let frameSizes = [256, 512, 1024, 2048]
    public static let maxFrames = 256
    public static let maxBytes = 4 * 1024 * 1024

    /// Папка своих таблиц.
    public static func appDir() -> URL {
        let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Tables", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func url(_ key: String, in dir: URL) -> URL {
        return dir.appendingPathComponent(key + ".wav")
    }

    static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }
    static func u32(_ b: [UInt8], _ o: Int) -> Int { u16(b, o) | (u16(b, o + 2) << 16) }

    /// Разбор WAV; не WAV или формат не поддержан — nil.
    public static func parse(_ data: Data) -> WavTable? {
        let b: [UInt8] = [UInt8](data)
        if b.count < 12 { return nil }
        let tag: (Int) -> String = { o in String(decoding: b[o..<(o + 4)], as: UTF8.self) }
        if tag(0) != "RIFF" || tag(8) != "WAVE" { return nil }
        var fmt = 0, ch = 1, bits = 16
        var dataAt = -1, dataLen = 0
        var clm: Int? = nil
        var o = 12
        while o + 8 <= b.count {
            let id: String = tag(o)
            let size: Int = u32(b, o + 4)
            let body = o + 8
            if id == "fmt " && body + 16 <= b.count {
                fmt = u16(b, body)
                ch = Swift.max(1, u16(b, body + 2))
                bits = u16(b, body + 14)
                if fmt == 0xfffe && size >= 26 && body + 26 <= b.count { fmt = u16(b, body + 24) }
            } else if id == "data" {
                dataAt = body
                dataLen = Swift.min(size, b.count - body)
            } else if id == "clm " {
                let end = Swift.min(b.count, body + Swift.min(size, 64))
                clm = clmSize(String(decoding: b[body..<end], as: UTF8.self))
            }
            o = body + size + (size & 1)
        }
        if dataAt < 0 { return nil }
        let bytes = bits / 8
        if bytes < 2 || bytes > 4 { return nil }
        let step = bytes * ch
        let n = dataLen / step
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let p = dataAt + i * step
            if fmt == 3 && bits == 32 {
                out[i] = Float(bitPattern: UInt32(u32(b, p)))
            } else if bits == 16 {
                out[i] = Float(Int16(bitPattern: UInt16(u16(b, p)))) / 32768
            } else if bits == 24 {
                let v: Int32 = Int32(b[p]) | (Int32(b[p + 1]) << 8) | (Int32(Int8(bitPattern: b[p + 2])) << 16)
                out[i] = Float(v) / 8388608
            } else if bits == 32 {
                out[i] = Float(Int32(bitPattern: UInt32(u32(b, p)))) / 2147483648
            } else {
                return nil
            }
        }
        return WavTable(samples: out, clm: clm)
    }

    /// «<!>2048 …» — размер кадра.
    static func clmSize(_ text: String) -> Int? {
        guard let r = text.range(of: "<!>") else { return nil }
        let digits = text[r.upperBound...].drop { $0 == " " }.prefix { $0.isNumber }
        return Int(digits)
    }

    /// AUTO: по метке 'clm ', иначе наибольший из 2048…256, на который длина делится.
    public static func autoFrameSize(_ w: WavTable) -> Int {
        if let c = w.clm, frameSizes.contains(c) { return c }
        for s in [2048, 1024, 512, 256] where w.samples.count % s == 0 && w.samples.count / s <= maxFrames { return s }
        return 2048
    }

    /// Число кадров при размере кадра.
    public static func framesFor(_ w: WavTable, _ size: Int) -> Int {
        return Swift.min(maxFrames, w.samples.count / size)
    }
}

extension WtTable {
    /// Своя таблица: кадры WAV → спектры (в масштабе кадра 2048) → мипмапы, вся таблица к пику 1.0.
    public static func user(_ samples: [Float], frameSize: Int) -> WtTable {
        let frames = Swift.max(1, Swift.min(WtWav.maxFrames, samples.count / frameSize))
        let lim = Swift.min(harmonics, frameSize / 2 - 1)
        var sp = Spectra(frames: frames, re: [], im: [])
        var a = [Double](repeating: 0, count: frameSize)
        var b = [Double](repeating: 0, count: frameSize)
        for f in 0..<frames {
            for j in 0..<frameSize {
                let k = f * frameSize + j
                a[j] = k < samples.count ? Double(samples[k]) : 0
                b[j] = 0
            }
            fft(&a, &b, inverse: false)
            var r = [Double](repeating: 0, count: harmonics + 1)
            var i = [Double](repeating: 0, count: harmonics + 1)
            if lim >= 1 {
                for n in 1...lim {
                    r[n] = a[n] / Double(frameSize)
                    i[n] = b[n] / Double(frameSize)
                }
            }
            sp.re.append(r)
            sp.im.append(i)
        }
        return buildMips(sp, perFrame: false)
    }
}
