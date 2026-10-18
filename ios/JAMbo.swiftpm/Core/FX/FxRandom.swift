import Foundation

/// Генератор случайных чисел эффектов — mulberry32 (как Math.random в эталонах ios/tools/fx/golden.mjs):
/// с тем же seed модуляция (wow, flutter, LFO линий реверба) совпадает с вебом по отсчётам.
public struct FxRandom {
    private var s: UInt32

    public init(_ seed: UInt32) { s = seed }

    /// Случайный seed для эффекта в приложении.
    public static func seed() -> UInt32 { return UInt32.random(in: 1...UInt32.max) }

    /// 0 ≤ x < 1.
    public mutating func next() -> Double {
        s &+= 0x6D2B79F5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296
    }
}
