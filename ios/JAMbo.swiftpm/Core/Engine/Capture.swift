// REC в редакторе сэмпла (S11e, как sampleedit.ts веба): запись входа, выхода дорожки или мастера, не дольше 60 с.
// Дорожка и мастер пишутся из колбэка (канал StemRing.capture), вход — с узла входа AVAudioEngine (Audio/).

public enum Capture {
    /// Наибольшая длина записи, с и кадры.
    public static let maxSeconds = 60
    public static let maxFrames: Int64 = 2_880_000
    /// Отсчётов на точку формы волны во время записи.
    public static let peakBlock = 128
    /// Наименьшая ширина формы волны во время записи — 5 с (в точках).
    public static let minSpan = 1875

    /// Время записи «м:сс».
    public static func time(_ seconds: Double) -> String {
        let s: Int = Swift.max(0, Int(seconds.rounded(.down)))
        let ss: Int = s % 60
        return "\(s / 60):" + (ss < 10 ? "0\(ss)" : "\(ss)")
    }
}

/// Пики записи по блокам Capture.peakBlock (L и R) — форма волны во время записи; неполный блок ждёт продолжения.
public struct RecPeaks: Equatable, Sendable {
    public private(set) var lo: [[Float]] = [[], []]
    public private(set) var hi: [[Float]] = [[], []]
    /// Обработано кадров записи.
    public private(set) var frames = 0

    public init() {}

    /// Точек формы волны.
    public var count: Int { return lo[0].count }

    /// Ширина поля в точках: записанное, не меньше 5 с.
    public var span: Int { return Swift.max(count, Capture.minSpan) }

    /// Дописать пики по записанному (left и right — вся запись с начала; новые кадры — с frames).
    public mutating func update(left: [Float], right: [Float]) {
        let n: Int = Swift.min(left.count, right.count)
        let b: Int = Capture.peakBlock
        while frames + b <= n {
            for c in 0..<2 {
                let d: [Float] = c == 0 ? left : right
                var l: Float = 0
                var h: Float = 0
                var i: Int = frames
                while i < frames + b {
                    let v: Float = d[i]
                    if v < l { l = v }
                    if v > h { h = v }
                    i += 1
                }
                lo[c].append(l)
                hi[c].append(h)
            }
            frames += b
        }
    }

    /// Пики точек k0..<k1 канала c (для столбца экрана).
    public func range(_ c: Int, _ k0: Int, _ k1: Int) -> (lo: Float, hi: Float) {
        var l: Float = 0
        var h: Float = 0
        var k: Int = Swift.max(0, k0)
        let e: Int = Swift.min(k1, count)
        while k < e {
            if lo[c][k] < l { l = lo[c][k] }
            if hi[c][k] > h { h = hi[c][k] }
            k += 1
        }
        return (l, h)
    }
}
