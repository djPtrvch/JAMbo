import SwiftUI

/// Спектр мощности по 4096 отсчётам (окно Ханна) — вне колбэка; общий для FREQ и TONAL.
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

/// FREQ и DYN при MIX (10.11): по кадру — две дорожки по кругу. FREQ — мощность в 30 полосах (по 1/3 октавы,
/// 20 Гц…20 кГц); диапазон дорожки — полосы не ниже наибольшей на 20 dB, пик — наибольшая. DYN — пик к RMS
/// (crest factor, dB) за последние 8192 отсчёта (~170 мс). Тишина (RMS ниже −60 dBFS) — нет данных.
final class MixAnalysis {
    static let bands = 30
    static let range: Float = 20
    let fftp = PowerFFT()
    let map: [Int]
    let raw = UnsafeMutablePointer<Float>.allocate(capacity: TrackTaps.capacity)
    private var power = [[Float]](repeating: [Float](repeating: 0, count: MixAnalysis.bands), count: TrackTaps.tracks)
    private var fresh = [Float](repeating: 0, count: MixAnalysis.bands)
    private(set) var crest = [Float](repeating: -1, count: TrackTaps.tracks)
    private(set) var rms = [Float](repeating: 0, count: TrackTaps.tracks)
    private var next = 0

    init() {
        var e: [Float] = []
        for j in 0...MixAnalysis.bands { e.append(20 * pow(1000, Float(j) / Float(MixAnalysis.bands))) }
        map = PowerFFT.bandMap(e)
        raw.initialize(repeating: 0, count: TrackTaps.capacity)
    }

    deinit { raw.deallocate() }

    func reset() {
        for t in 0..<TrackTaps.tracks {
            crest[t] = -1
            rms[t] = 0
            for j in 0..<MixAnalysis.bands { power[t][j] = 0 }
        }
    }

    /// Кадр: две дорожки из count; freq — считать и спектр.
    func tick(_ taps: TrackTaps, count: Int, freq: Bool) {
        if count <= 0 { return }
        for _ in 0..<2 {
            let t: Int = next % count
            next = (t + 1) % count
            analyze(taps, t, freq: freq)
        }
    }

    private func analyze(_ taps: TrackTaps, _ t: Int, freq: Bool) {
        let n: Int = TrackTaps.capacity
        taps.read(t, into: raw, count: n)
        var pk: Float = 0, sq: Float = 0
        var i = 0
        while i < n {
            let v: Float = raw[i]
            let a: Float = v < 0 ? -v : v
            if a > pk { pk = a }
            sq += v * v
            i += 1
        }
        let r: Float = (sq / Float(n)).squareRoot()
        rms[t] = r
        if r < 0.001 {
            crest[t] = -1
            return
        }
        let c: Float = 20 * log10(pk / r)
        crest[t] = crest[t] < 0 ? c : crest[t] * 0.6 + c * 0.4
        if !freq { return }
        fftp.bands(UnsafePointer(raw + (n - PowerFFT.size)), map, into: &fresh)
        for j in 0..<MixAnalysis.bands { power[t][j] = power[t][j] * 0.5 + fresh[j] * 0.5 }
    }

    /// Диапазон дорожки t: доли оси (0 — 20 Гц, 1 — 20 кГц) низа, верха и пика; nil — тишина.
    func span(_ t: Int) -> (lo: CGFloat, hi: CGFloat, peak: CGFloat)? {
        guard t >= 0 && t < TrackTaps.tracks, rms[t] >= 0.001 else { return nil }
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

/// Тональный баланс мастера (TONAL при MIX, 10.11): мощность выхода мастера (окно гониометра) в 4 полосах — LOW
/// 20–250 Гц, LOW MID 250 Гц–2 кГц, HIGH MID 2–6 кГц, HIGH 6–20 кГц; плотность на октаву против цели (спад
/// 1,5 dB на октаву от 1 кГц — 4,5 dB/oct спектра FFT, средний спектр сведённой музыки), минус среднее отклонение (громкость не важна).
/// Сглаживание ~0,3 с.
final class TonalState {
    static let edges: [Float] = [20, 250, 2000, 6000, 20000]
    static let names: [String] = ["LOW", "LOW MID", "HIGH MID", "HIGH"]
    /// Коридор цели, ± dB.
    static let corridor: Float = 3
    let fftp = PowerFFT()
    let map: [Int] = PowerFFT.bandMap(TonalState.edges)
    let mono = UnsafeMutablePointer<Float>.allocate(capacity: PowerFFT.size)
    private var power = [Float](repeating: 0, count: 4)
    private var fresh = [Float](repeating: 0, count: 4)
    /// Отклонение полос от цели, dB; nil — ещё нет сигнала.
    private(set) var dev: [Float]? = nil

    deinit { mono.deallocate() }

    func tick(_ s: ScopeState) {
        if !s.gonioOk { return }
        var e: Float = 0
        for i in 0..<PowerFFT.size {
            let v: Float = 0.5 * (s.gl[i] + s.gr[i])
            mono[i] = v
            e += v * v
        }
        if e < 1e-6 { return }
        fftp.bands(UnsafePointer(mono), map, into: &fresh)
        for j in 0..<4 { power[j] = power[j] == 0 ? fresh[j] : power[j] * 0.95 + fresh[j] * 0.05 }
        var d = [Float](repeating: 0, count: 4)
        var mean: Float = 0
        for j in 0..<4 {
            let lo: Float = TonalState.edges[j], hi: Float = TonalState.edges[j + 1]
            let oct: Float = log2(hi / lo)
            let fc: Float = (lo * hi).squareRoot()
            let dens: Float = 10 * log10(max(1e-20, power[j]) / oct)
            let target: Float = -1.5 * log2(fc / 1000)
            d[j] = dens - target
            mean += d[j] / 4
        }
        dev = d.map { $0 - mean }
    }
}

/// TONAL — на месте скопа при MIX: 4 столбца полос; серый коридор цели ±3 dB, средняя линия, жёлтая метка —
/// отклонение полосы (шкала ±12 dB); подписи полос и шкалы — 9 px цветом --dim.
struct TonalView: View {
    let model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            ScopeCanvas(now: tl.date) { ctx, size in draw(ctx, size) }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let top: CGFloat = 14, bottom: CGFloat = size.height - 22
        let cy: CGFloat = (top + bottom) / 2
        let k: CGFloat = (bottom - top) / 24
        let left: CGFloat = 28
        let cell: CGFloat = (size.width - left - 8) / 4
        for (v, s) in [(12, "+12"), (0, "0"), (-12, "−12")] {
            let y: CGFloat = cy - CGFloat(v) * k
            ctx.fill(Path(CGRect(x: left, y: y, width: size.width - left - 8, height: 1)), with: .color(theme.grid))
            let t = ctx.resolve(Text(s).font(.system(size: 9)).foregroundColor(theme.dim))
            ctx.draw(t, at: CGPoint(x: left - 4, y: y), anchor: .trailing)
        }
        let dev: [Float]? = model.tonal.dev
        let w: CGFloat = min(36, cell * 0.6)
        let cor: CGFloat = CGFloat(TonalState.corridor) * k
        for j in 0..<4 {
            let x: CGFloat = left + cell * (CGFloat(j) + 0.5)
            let band = CGRect(x: x - w / 2, y: cy - cor, width: w, height: 2 * cor)
            ctx.fill(Path(roundedRect: band, cornerRadius: 3), with: .color(theme.meterTrack))
            let name = ctx.resolve(Text(TonalState.names[j]).font(.system(size: 9)).foregroundColor(theme.dim))
            ctx.draw(name, at: CGPoint(x: x, y: size.height - 8), anchor: .center)
            guard let d = dev else { continue }
            let v: CGFloat = CGFloat(max(-12, min(12, d[j])))
            let y: CGFloat = cy - v * k
            ctx.fill(Path(CGRect(x: x - w / 2, y: min(cy, y), width: w, height: abs(y - cy))), with: .color(theme.accent.opacity(0.3)))
            ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: y - 2, width: w, height: 4), cornerRadius: 2), with: .color(theme.accent))
        }
    }
}
