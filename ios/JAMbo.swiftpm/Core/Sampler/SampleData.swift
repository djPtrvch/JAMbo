import Foundation

/// Сэмпл в памяти: 48 кГц, float32, моно или стерео (у моно right — тот же буфер, что left).
/// Создаётся вне колбэка; колбэк читает только указатели (снимок звука держит ссылку, пока голоса могут звучать).
public final class SampleData: @unchecked Sendable {
    public let frames: Int
    public let channels: Int
    public let left: UnsafeMutablePointer<Float>
    public let right: UnsafeMutablePointer<Float>

    public init(left l: [Float], right r: [Float]?) {
        frames = Swift.max(1, l.count)
        channels = r == nil ? 1 : 2
        left = .allocate(capacity: frames)
        left.initialize(repeating: 0, count: frames)
        for i in 0..<l.count { left[i] = l[i] }
        if let r = r {
            right = .allocate(capacity: frames)
            right.initialize(repeating: 0, count: frames)
            for i in 0..<Swift.min(r.count, frames) { right[i] = r[i] }
        } else {
            right = left
        }
    }

    deinit {
        if right != left { right.deallocate() }
        left.deallocate()
    }

    public var duration: Double { return Double(frames) / AudioCore.sampleRate }

    public func channel(_ c: Int) -> [Float] {
        let p = c == 0 ? left : right
        return Array(UnsafeBufferPointer(start: p, count: frames))
    }
}

/// Правки сэмпла в редакторе (TRIM, NORMALIZE, MONO) и данные для рисования (как ui/sampleedit.ts веба).
public enum SampleEdit {
    /// TRIM: оставить отрезок a…b (доли длины).
    public static func trim(_ s: SampleData, _ a: Double, _ b: Double) -> SampleData {
        let i0 = Swift.max(0, Swift.min(s.frames - 1, Int((Swift.min(a, b) * Double(s.frames)).rounded())))
        let i1 = Swift.max(i0 + 1, Swift.min(s.frames, Int((Swift.max(a, b) * Double(s.frames)).rounded())))
        let l = Array(UnsafeBufferPointer(start: s.left + i0, count: i1 - i0))
        let r: [Float]? = s.channels == 2 ? Array(UnsafeBufferPointer(start: s.right + i0, count: i1 - i0)) : nil
        return SampleData(left: l, right: r)
    }

    /// NORMALIZE: пик −0.1 dBFS.
    public static func normalize(_ s: SampleData) -> SampleData {
        var peak: Float = 0
        for i in 0..<s.frames {
            peak = Swift.max(peak, abs(s.left[i]), abs(s.right[i]))
        }
        let g: Float = peak > 0 ? Float(pow(10.0, -0.1 / 20)) / peak : 1
        let l = s.channel(0).map { $0 * g }
        let r: [Float]? = s.channels == 2 ? s.channel(1).map { $0 * g } : nil
        return SampleData(left: l, right: r)
    }

    /// MONO: среднее L и R.
    public static func mono(_ s: SampleData) -> SampleData {
        var l = [Float](repeating: 0, count: s.frames)
        for i in 0..<s.frames { l[i] = (s.left[i] + s.right[i]) * 0.5 }
        return SampleData(left: l, right: nil)
    }

    /// Огибающая для рисования: n столбцов на отрезке кадров from…to — наименьшее и наибольшее значение канала.
    public static func peaks(_ s: SampleData, channel c: Int, from: Double, to: Double, n: Int) -> [(Float, Float)] {
        let p = c == 0 ? s.left : s.right
        let count = Swift.max(1, n)
        var out = [(Float, Float)](repeating: (0, 0), count: count)
        let span: Double = Swift.max(1e-9, to - from)
        for k in 0..<count {
            let a = Int(from + span * Double(k) / Double(count))
            let b = Int(from + span * Double(k + 1) / Double(count))
            let i0 = Swift.max(0, Swift.min(s.frames - 1, a))
            let i1 = Swift.max(i0 + 1, Swift.min(s.frames, Swift.max(b, a + 1)))
            var lo: Float = 0
            var hi: Float = 0
            // Длинный отрезок — прореживание (не больше 256 чтений на столбец).
            let stride = Swift.max(1, (i1 - i0) / 256)
            var i = i0
            while i < i1 {
                let v = p[i]
                if v < lo { lo = v }
                if v > hi { hi = v }
                i += stride
            }
            out[k] = (lo, hi)
        }
        return out
    }
}

/// Ключ звука в снимках для колбэка: FNV-1a 64 от строки (0 — нет звука).
public enum SoundKey {
    public static func hash(_ s: String) -> UInt64 {
        if s.isEmpty { return 0 }
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h == 0 ? 1 : h
    }
}
