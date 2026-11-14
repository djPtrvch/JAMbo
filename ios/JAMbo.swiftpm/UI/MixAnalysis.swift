import SwiftUI

/// Спектр мощности по 4096 отсчётам (окно Ханна) — вне колбэка; для FREQ.
final class PowerFFT {
    static let size = 4096
    static let bins = size / 2
    /// Ширина бина, Гц.
    static let hz: Float = 48000.0 / 4096.0
    let window: UnsafeMutablePointer<Float>
    let input: UnsafeMutablePointer<Float>
    let re: UnsafeMutablePointer<Float>
    let im: UnsafeMutablePointer<Float>
    let fft = RealFFT(size: PowerFFT.size)

    init() {
        let n: Int = PowerFFT.size
        window = .allocate(capacity: n)
        for i in 0..<n {
            let x: Double = 2 * Double.pi * Double(i) / Double(n)
            window[i] = Float(0.5 - 0.5 * cos(x))
        }
        input = .allocate(capacity: n)
        re = .allocate(capacity: PowerFFT.bins)
        im = .allocate(capacity: PowerFFT.bins)
    }

    deinit { for p in [window, input, re, im] { p.deallocate() } }

    /// Мощности бинов сигнала x (4096 отсчётов) — сложить в полосы: band[k] — номер полосы бина (−1 — мимо).
    func bands(_ x: UnsafePointer<Float>, _ band: [Int], into out: inout [Float]) {
        let n: Int = PowerFFT.size
        var i = 0
        while i < n {
            input[i] = x[i] * window[i]
            i += 1
        }
        fft.forward(UnsafePointer(input), re, im)
        for j in 0..<out.count { out[j] = 0 }
        var k = 1
        while k < PowerFFT.bins {
            let b: Int = band[k]
            if b >= 0 { out[b] += re[k] * re[k] + im[k] * im[k] }
            k += 1
        }
    }

    /// Номера полос бинов по границам edges (Гц, по возрастанию).
    static func bandMap(_ edges: [Float]) -> [Int] {
        var m = [Int](repeating: -1, count: PowerFFT.bins)
        for k in 1..<PowerFFT.bins {
            let f: Float = Float(k) * PowerFFT.hz
            var j = 0
            while j + 1 < edges.count {
                if f >= edges[j] && f < edges[j + 1] { m[k] = j }
                j += 1
            }
        }
        return m
    }
}

/// FREQ при MIX (10.11): по кадру — две дорожки по кругу; мощность в 30 полосах (по 1/3 октавы, 20 Гц…20 кГц),
/// среднее за ~4 с (тишина между ударами не обнуляет — полоса не мерцает); диапазон дорожки — полосы не ниже
/// наибольшей на 20 dB, пик — наибольшая. Полоса гаснет, когда средний уровень дорожки ниже −66 dBFS.
final class MixAnalysis {
    static let bands = 30
    static let range: Float = 20
    let fftp = PowerFFT()
    let map: [Int]
    let raw = UnsafeMutablePointer<Float>.allocate(capacity: PowerFFT.size)
    private var power = [[Float]](repeating: [Float](repeating: 0, count: MixAnalysis.bands), count: TrackTaps.tracks)
    private var fresh = [Float](repeating: 0, count: MixAnalysis.bands)
    /// Средний RMS дорожки (за ~4 с).
    private var rms = [Float](repeating: 0, count: TrackTaps.tracks)
    private var next = 0

    init() {
        var e: [Float] = []
        for j in 0...MixAnalysis.bands { e.append(20 * pow(1000, Float(j) / Float(MixAnalysis.bands))) }
        map = PowerFFT.bandMap(e)
        raw.initialize(repeating: 0, count: PowerFFT.size)
    }

    deinit { raw.deallocate() }

    func reset() {
        for t in 0..<TrackTaps.tracks {
            rms[t] = 0
            for j in 0..<MixAnalysis.bands { power[t][j] = 0 }
        }
    }

    /// Кадр: две дорожки из count.
    func tick(_ taps: TrackTaps, count: Int) {
        if count <= 0 { return }
        // Среднее за ~4 с: дорожка обновляется раз в count/2 кадров (60 в секунду).
        let a: Float = exp(-Float(count) / 480)
        for _ in 0..<2 {
            let t: Int = next % count
            next = (t + 1) % count
            analyze(taps, t, a)
        }
    }

    private func analyze(_ taps: TrackTaps, _ t: Int, _ a: Float) {
        let n: Int = PowerFFT.size
        taps.read(t, into: raw, count: n)
        var sq: Float = 0
        var i = 0
        while i < n {
            sq += raw[i] * raw[i]
            i += 1
        }
        let r: Float = (sq / Float(n)).squareRoot()
        rms[t] = rms[t] * a + r * (1 - a)
        // Тишина между ударами — спектр не трогаем (среднее держится).
        if r < 0.001 { return }
        fftp.bands(UnsafePointer(raw), map, into: &fresh)
        for j in 0..<MixAnalysis.bands { power[t][j] = power[t][j] == 0 ? fresh[j] : power[t][j] * a + fresh[j] * (1 - a) }
    }

    /// Диапазон дорожки t: доли оси (0 — 20 Гц, 1 — 20 кГц) низа, верха и пика; nil — тишина.
    func span(_ t: Int) -> (lo: CGFloat, hi: CGFloat, peak: CGFloat)? {
        guard t >= 0 && t < TrackTaps.tracks, rms[t] >= 0.0005 else { return nil }
        let p: [Float] = power[t]
        var best = 0
        for j in 0..<p.count where p[j] > p[best] { best = j }
        if p[best] <= 0 { return nil }
        let thr: Float = p[best] * pow(10, -MixAnalysis.range / 10)
        var lo: Int = best, hi: Int = best
        for j in 0..<p.count where p[j] >= thr {
            lo = min(lo, j)
            hi = max(hi, j)
        }
        let nb = CGFloat(MixAnalysis.bands)
        return (CGFloat(lo) / nb, CGFloat(hi + 1) / nb, (CGFloat(best) + 0.5) / nb)
    }
}
