import Foundation

// Телеметрия модулей мастера для индикации COMP / CLIP / LIM (как compTele, clipTele, limTele веба): кадр раз
// в 256 отсчётов — пик входа и выхода (линейно), GR (dB ≥ 0), уровень детектора (dB, у компрессора). Колбэк
// пишет кадры в кольцо (DynTele.capacity кадров — хватит и окнам модулей на S9), интерфейс читает новые.

public final class DynTele: @unchecked Sendable {
    public static let capacity = 2048
    static let mask = capacity - 1
    public let inPeak: UnsafeMutablePointer<Float>
    public let gr: UnsafeMutablePointer<Float>
    public let outPeak: UnsafeMutablePointer<Float>
    public let det: UnsafeMutablePointer<Float>
    /// Всего записано кадров.
    public let written = AtomicCounter()
    /// Счётчик кадров модуля при прошлой записи (колбэк).
    var seen = 0

    public init() {
        let n = DynTele.capacity
        inPeak = .allocate(capacity: n)
        gr = .allocate(capacity: n)
        outPeak = .allocate(capacity: n)
        det = .allocate(capacity: n)
        for p in [inPeak, gr, outPeak, det] { p.initialize(repeating: 0, count: n) }
    }

    deinit {
        for p in [inPeak, gr, outPeak, det] { p.deallocate() }
    }

    /// Колбэк: новый кадр модуля (frames — его счётчик кадров; тот же — ничего не пишет).
    @inline(__always)
    func push(frames: Int, inPeak i: Double, gr g: Double, outPeak o: Double, det d: Double) {
        if frames == seen { return }
        seen = frames
        let w = written.load()
        let k = w & DynTele.mask
        inPeak[k] = Float(i)
        gr[k] = Float(g)
        outPeak[k] = Float(o)
        det[k] = Float(d)
        written.store(w + 1)
    }

    /// Интерфейс: наибольшие вход, GR и выход в кадрах после since (не больше capacity); новый счётчик.
    public func peaks(since: Int) -> (count: Int, inPeak: Float, gr: Float, outPeak: Float, frames: Int) {
        let w = written.load()
        var k = Swift.max(since, w - DynTele.capacity + 1)
        var i: Float = 0, g: Float = 0, o: Float = 0
        let got = w - k
        while k < w {
            let q = k & DynTele.mask
            i = Swift.max(i, inPeak[q])
            g = Swift.max(g, gr[q])
            o = Swift.max(o, outPeak[q])
            k += 1
        }
        return (w, i, g, o, Swift.max(0, got))
    }
}
