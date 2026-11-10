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
/// 20–250 Гц, LOW MID 250 Гц–2 кГц, HIGH MID 2–6 кГц, HIGH 6–20 кГц; плотность на октаву против базового наклона
/// (спад 1,5 dB на октаву от 1 кГц — 4,5 dB/oct спектра FFT), минус среднее отклонение (громкость не важна).
/// Цель — коридор стиля проекта (DrumRhythm.styles): свой сдвиг полос и ширина. Сглаживание ~0,3 с.
final class TonalState {
    static let edges: [Float] = [20, 250, 2000, 6000, 20000]
    static let names: [String] = ["LOW", "LOW MID", "HIGH MID", "HIGH"]
    /// Сдвиг центра коридора по полосам (dB) для стилей House, Techno, Breaks/D&B, Trap/R&B, Pop, Ambient — оценка,
    /// не замер эталонов.
    static let targets: [[Float]] = [[1, 0, -0.5, -0.5], [2, -0.5, -1, -0.5], [2, -1, 0, -1], [4, -1, -1.5, -1.5],
                                     [0, 0, 0.5, -0.5], [-1, 1, 0, 0]]
    /// Половина ширины коридора, dB.
    static let widths: [Float] = [3, 3, 3.5, 4, 3, 4]
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
        dev = TonalState.devs(power)
    }

    /// Мощности 4 полос → отклонение от базового наклона, минус среднее (dB).
    static func devs(_ power: [Float]) -> [Float] {
        var d = [Float](repeating: 0, count: 4)
        var mean: Float = 0
        for j in 0..<4 {
            let lo: Float = edges[j], hi: Float = edges[j + 1]
            let oct: Float = log2(hi / lo)
            let fc: Float = (lo * hi).squareRoot()
            let dens: Float = 10 * log10(max(1e-20, power[j]) / oct)
            let target: Float = -1.5 * log2(fc / 1000)
            d[j] = dens - target
            mean += d[j] / 4
        }
        return d.map { $0 - mean }
    }

    /// Цель по референсу (вне главного потока): центр — баланс всего файла (средняя мощность окон 4096 отсчётов, не
    /// больше ~1500 окон), половина ширины — разброс баланса по отрезкам ~1 с (1,5 σ, 1,5…4 dB); тишина (ниже
    /// −50 dBFS) не считается. nil — в файле нет звука.
    static func profile(_ key: String, _ s: SampleData) -> TonalTarget? {
        let n: Int = PowerFFT.size
        if s.frames < n { return nil }
        let fftp = PowerFFT()
        let map: [Int] = PowerFFT.bandMap(edges)
        let x = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { x.deallocate() }
        let r: UnsafeMutablePointer<Float> = s.channels > 1 ? s.right : s.left
        let hop: Int = max(n, (s.frames - n) / 1500)
        let perChunk: Int = max(1, 48000 / hop)
        var total = [Float](repeating: 0, count: 4)
        var chunk = [Float](repeating: 0, count: 4)
        var fresh = [Float](repeating: 0, count: 4)
        var inChunk = 0
        var chunks: [[Float]] = []
        var start = 0
        while start + n <= s.frames {
            var e: Float = 0
            for i in 0..<n {
                let v: Float = 0.5 * (s.left[start + i] + r[start + i])
                x[i] = v
                e += v * v
            }
            start += hop
            if e / Float(n) < 1e-5 { continue }
            fftp.bands(UnsafePointer(x), map, into: &fresh)
            for j in 0..<4 {
                total[j] += fresh[j]
                chunk[j] += fresh[j]
            }
            inChunk += 1
            if inChunk >= perChunk {
                chunks.append(devs(chunk))
                for j in 0..<4 { chunk[j] = 0 }
                inChunk = 0
            }
        }
        if total.allSatisfy({ $0 <= 0 }) { return nil }
        let center: [Float] = devs(total)
        var width = [Float](repeating: 3, count: 4)
        if chunks.count >= 4 {
            for j in 0..<4 {
                var v: Float = 0
                for c in chunks { v += (c[j] - center[j]) * (c[j] - center[j]) }
                let sd: Float = (v / Float(chunks.count)).squareRoot()
                width[j] = max(1.5, min(4, 1.5 * sd))
            }
        }
        return TonalTarget(key: key, center: center, width: width)
    }
}

/// Цель TONAL по референсу: центр коридора и половина ширины по полосам, dB.
final class TonalTarget {
    let key: String
    let center: [Float]
    let width: [Float]

    init(key: String, center: [Float], width: [Float]) {
        self.key = key
        self.center = center
        self.width = width
    }
}

/// Подпись на холсте: 9 px цветом --dim.
func dimText(_ ctx: GraphicsContext, _ s: String, _ p: CGPoint, _ a: UnitPoint) {
    ctx.draw(Text(s).font(.system(size: 9)).foregroundColor(theme.dim), at: p, anchor: a)
}

/// TONAL — на месте осциллоскопа при MIX: 4 столбца полос; серый коридор цели (стиль проекта или, тапом по окну,
/// референс REF аранжировщика), жёлтая метка — отклонение полосы (шкала ±12 dB); слева вверху — TARGET и стиль или
/// имя референса; подписи — 9 px цветом --dim.
struct TonalView: View {
    let model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            ScopeCanvas(now: tl.date) { ctx, size in TonalView.draw(ctx, size, model) }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .onTapGesture { model.tonalRef.toggle() }
    }

    /// Цель: стиль проекта или референс (nil — референса нет или ещё считается); title — имя: проекта (без имени —
    /// UNKNOWN) или референса.
    static func target(_ model: AppModel, _ title: inout String) -> TonalTarget? {
        if model.tonalRef {
            guard let ref = model.project.arrange.ref else {
                title = "REF — LOAD IN ARRANGE"
                return nil
            }
            title = String((ref.name.isEmpty ? "UNKNOWN" : ref.name).prefix(24)).uppercased()
            guard let t = model.refTonal, t.key == ref.key else {
                title += " …"
                return nil
            }
            return t
        }
        let st: Int = DrumRhythm.styleIndex(model.project.tracks.first?.drumStyle ?? 0)
        let tg: [Float] = TonalState.targets[st]
        let m: Float = (tg[0] + tg[1] + tg[2] + tg[3]) / 4
        let w: Float = TonalState.widths[st]
        let name: String = model.session.name
        title = String((name.isEmpty ? "UNKNOWN" : name).prefix(24)).uppercased()
        return TonalTarget(key: "", center: [tg[0] - m, tg[1] - m, tg[2] - m, tg[3] - m], width: [w, w, w, w])
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ model: AppModel) {
        let top: CGFloat = 24, bottom: CGFloat = size.height - 20
        let cy: CGFloat = (top + bottom) / 2
        let k: CGFloat = (bottom - top) / 24
        let left: CGFloat = 28
        let cell: CGFloat = (size.width - left - 8) / 4
        let scale: [String] = ["+12", "0", "−12"]
        for q in 0..<3 {
            let y: CGFloat = top + CGFloat(q) * 12 * k
            ctx.fill(Path(CGRect(x: left, y: y, width: size.width - left - 8, height: 1)), with: .color(theme.grid))
            dimText(ctx, scale[q], CGPoint(x: left - 4, y: y), .trailing)
        }
        var title = ""
        let tgt: TonalTarget? = target(model, &title)
        // TARGET и имя: своего трека — цветом текста, референса — жёлтым.
        dimText(ctx, "TARGET", CGPoint(x: 8, y: 4), .topLeading)
        let col: Color = model.tonalRef ? theme.accent : theme.text
        ctx.draw(Text(title).font(.system(size: 9, weight: .semibold)).foregroundColor(col), at: CGPoint(x: 50, y: 4), anchor: .topLeading)
        let dev: [Float]? = model.tonal.dev
        let w: CGFloat = min(36, cell * 0.6)
        for j in 0..<4 {
            let x: CGFloat = left + cell * (CGFloat(j) + 0.5)
            dimText(ctx, TonalState.names[j], CGPoint(x: x, y: size.height - 8), .center)
            if let t = tgt {
                let cor: CGFloat = CGFloat(t.width[j]) * k
                let tc: CGFloat = cy - CGFloat(t.center[j]) * k
                ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: tc - cor, width: w, height: 2 * cor), cornerRadius: 3),
                         with: .color(theme.meterTrack))
            }
            guard let d = dev else { continue }
            let y: CGFloat = cy - CGFloat(max(-12, min(12, d[j]))) * k
            ctx.fill(Path(CGRect(x: x - w / 2, y: min(cy, y), width: w, height: abs(y - cy))), with: .color(theme.accent.opacity(0.3)))
            ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: y - 2, width: w, height: 4), cornerRadius: 2), with: .color(theme.accent))
        }
    }
}
