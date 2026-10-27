import Foundation

/// Сэмпл в памяти: 48 кГц, float32, моно или стерео (у моно right — тот же буфер, что left).
/// Создаётся вне колбэка; колбэк читает только указатели (снимок звука держит ссылку, пока голоса могут звучать).
public final class SampleData: @unchecked Sendable {
    public let frames: Int
    public let channels: Int
    public let left: UnsafeMutablePointer<Float>
    public let right: UnsafeMutablePointer<Float>

    public convenience init(left l: [Float], right r: [Float]?) {
        self.init(frames: l.count, stereo: r != nil)
        // Копия блоком (поэлементный цикл в отладочной сборке Playgrounds медленный).
        l.withUnsafeBufferPointer { b in if let a = b.baseAddress { left.update(from: a, count: b.count) } }
        if let r = r {
            r.withUnsafeBufferPointer { b in
                if let a = b.baseAddress { right.update(from: a, count: Swift.min(b.count, frames)) }
            }
        }
    }

    /// Пустой сэмпл (тишина) на frames кадров — правки пишут прямо в буферы.
    init(frames n: Int, stereo: Bool) {
        frames = Swift.max(1, n)
        channels = stereo ? 2 : 1
        left = .allocate(capacity: frames)
        left.initialize(repeating: 0, count: frames)
        if stereo {
            right = .allocate(capacity: frames)
            right.initialize(repeating: 0, count: frames)
        } else {
            right = left
        }
    }

    deinit {
        if right != left { right.deallocate() }
        left.deallocate()
    }

    public var duration: Double { return Double(frames) / AudioCore.sampleRate }

    /// Темп лупа для RATE в TSTR (TempoDetect.loopBpm; 0 — не учитывается); считается один раз, в основном потоке.
    public lazy var loopBpm: Double = TempoDetect.loopBpm(self)
    /// Атаки (Onsets.detect) — для таймстретча NORMAL; считаются один раз, в основном потоке.
    public lazy var onsets: OnsetList = OnsetList(Onsets.detect(self))

    public func channel(_ c: Int) -> [Float] {
        let p = c == 0 ? left : right
        return Array(UnsafeBufferPointer(start: p, count: frames))
    }
}

/// Правки сэмпла в редакторе (TRIM, NORMALIZE, MONO) и данные для рисования (как ui/sampleedit.ts веба).
public enum SampleEdit {
    /// TRIM: оставить отрезок a…b (доли длины).
    // Правки — прямо по буферам, циклы while без вызовов функций (отладочная сборка Playgrounds не оптимизирует).

    public static func trim(_ s: SampleData, _ a: Double, _ b: Double) -> SampleData {
        let i0 = Swift.max(0, Swift.min(s.frames - 1, Int((Swift.min(a, b) * Double(s.frames)).rounded())))
        let i1 = Swift.max(i0 + 1, Swift.min(s.frames, Int((Swift.max(a, b) * Double(s.frames)).rounded())))
        let out = SampleData(frames: i1 - i0, stereo: s.channels == 2)
        out.left.update(from: s.left + i0, count: i1 - i0)
        if s.channels == 2 { out.right.update(from: s.right + i0, count: i1 - i0) }
        return out
    }

    /// NORMALIZE: пик −0.1 dBFS.
    public static func normalize(_ s: SampleData) -> SampleData {
        let n: Int = s.frames
        let stereo: Bool = s.channels == 2
        let l = s.left, r = s.right
        var peak: Float = 0
        var i = 0
        while i < n {
            let a: Float = l[i]
            let m: Float = a < 0 ? -a : a
            if m > peak { peak = m }
            i += 1
        }
        if stereo {
            i = 0
            while i < n {
                let a: Float = r[i]
                let m: Float = a < 0 ? -a : a
                if m > peak { peak = m }
                i += 1
            }
        }
        let g: Float = peak > 0 ? Float(pow(10.0, -0.1 / 20)) / peak : 1
        let out = SampleData(frames: n, stereo: stereo)
        let ol = out.left, or = out.right
        i = 0
        while i < n {
            ol[i] = l[i] * g
            i += 1
        }
        if stereo {
            i = 0
            while i < n {
                or[i] = r[i] * g
                i += 1
            }
        }
        return out
    }

    /// MONO: среднее L и R.
    public static func mono(_ s: SampleData) -> SampleData {
        let n: Int = s.frames
        let l = s.left, r = s.right
        let out = SampleData(frames: n, stereo: false)
        let o = out.left
        var i = 0
        while i < n {
            o[i] = (l[i] + r[i]) * 0.5
            i += 1
        }
        return out
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

    /// Столбцы между соседними границами bounds (отсчёты, по возрастанию; WARP — форма волны по карте): наименьшее и
    /// наибольшее значение; вне сэмпла — (0, 0); не больше reads чтений на столбец.
    public static func peaks(_ s: SampleData, channel c: Int, bounds: [Double], reads: Int = 96) -> [(Float, Float)] {
        let p = c == 0 ? s.left : s.right
        let n: Int = Swift.max(0, bounds.count - 1)
        var out = [(Float, Float)](repeating: (0, 0), count: n)
        let fr: Double = Double(s.frames)
        for k in 0..<n {
            let a: Double = Swift.max(0, bounds[k])
            let b: Double = Swift.min(fr, bounds[k + 1])
            if b <= 0 || a >= fr || b < a { continue }
            let i0: Int = Swift.min(s.frames - 1, Int(a))
            let i1: Int = Swift.max(i0 + 1, Swift.min(s.frames, Int(b.rounded(.up))))
            var lo: Float = 0
            var hi: Float = 0
            let stride: Int = Swift.max(1, (i1 - i0) / Swift.max(1, reads))
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
