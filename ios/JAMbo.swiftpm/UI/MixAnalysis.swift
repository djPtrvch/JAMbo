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

/// FREQ, MASK и LOUD при MIX (10.11, 15.11): по кадру — две дорожки по кругу; мощность в 30 полосах (по 1/3 октавы,
/// 20 Гц…20 кГц), среднее за ~4 с (тишина между ударами не обнуляет — полоса не мерцает); диапазон дорожки — полосы
/// не ниже наибольшей на 20 dB, пик — наибольшая. Полоса гаснет, когда средний уровень дорожки ниже −66 dBFS.
/// LOUD — громкость по восприятию: средний квадрат сигнала с весами кривой K (BS.1770) по полосам, среднее за ~4 с.
/// MASK — явные конфликты: полосы, важные и для дорожки, и для других слышимых, где эти другие не тише её больше
/// чем на 12 dB (громче или вровень — дорожку там заглушают); сглажено (updateMask).
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
    /// Средний квадрат с весами K (за ~4 с) — LOUD.
    private var kms = [Float](repeating: 0, count: TrackTaps.tracks)
    /// Вес кривой K (мощность) в середине каждой полосы.
    let kWeight: [Float]
    private var next = 0
    /// MASK: на сколько dB остальные могут быть тише дорожки, чтобы полоса ещё считалась конфликтом.
    static let maskRange: Float = 12
    /// MASK: полоса важна для дорожки, если не ниже её самой сильной на столько dB.
    static let maskSig: Float = 10
    /// MASK: «заглушают» снимается, когда остальные стали тише дорожки больше чем на столько dB.
    static let maskHyst: Float = 3
    /// MASK: «заглушают» видно, когда сглаженная сила не меньше этой (~2 с конфликта).
    static let maskShow: Float = 0.7
    /// MASK, сглаженное: сила по полосам, «заглушают», номер мешающей и кандидат на смену с его счётчиком кадров.
    private var mStr = [[Float]](repeating: [Float](repeating: 0, count: MixAnalysis.bands), count: TrackTaps.tracks)
    private var mBur = [[Bool]](repeating: [Bool](repeating: false, count: MixAnalysis.bands), count: TrackTaps.tracks)
    private var mWho = [Int](repeating: -1, count: TrackTaps.tracks)
    private var whoCand = [Int](repeating: -1, count: TrackTaps.tracks)
    private var whoHold = [Int](repeating: 0, count: TrackTaps.tracks)

    init() {
        var e: [Float] = []
        for j in 0...MixAnalysis.bands { e.append(20 * pow(1000, Float(j) / Float(MixAnalysis.bands))) }
        map = PowerFFT.bandMap(e)
        var kw: [Float] = []
        for j in 0..<MixAnalysis.bands {
            let f: Double = 20 * pow(1000, (Double(j) + 0.5) / Double(MixAnalysis.bands))
            kw.append(Float(MixAnalysis.kPower(f)))
        }
        kWeight = kw
        raw.initialize(repeating: 0, count: PowerFFT.size)
    }

    deinit { raw.deallocate() }

    /// Мощность кривой K на частоте f: полка и ФВЧ BS.1770 (коэффициенты для 48 кГц).
    static func kPower(_ f: Double) -> Double {
        let w: Double = 2 * Double.pi * f / 48000
        let shelf: Double = biquadPower([1.53512485958697, -2.69169618940638, 1.19839281085285],
                                        [-1.69065929318241, 0.73248077421585], w)
        let hp: Double = biquadPower([1, -2, 1], [-1.99004745483398, 0.99007225036621], w)
        return shelf * hp
    }

    /// |H|² биквада b0..b2 / (1, a1, a2) на круговой частоте w.
    static func biquadPower(_ b: [Double], _ a: [Double], _ w: Double) -> Double {
        let c1: Double = cos(w), s1: Double = sin(w)
        let c2: Double = cos(2 * w), s2: Double = sin(2 * w)
        let nr: Double = b[0] + b[1] * c1 + b[2] * c2
        let ni: Double = -(b[1] * s1 + b[2] * s2)
        let dr: Double = 1 + a[0] * c1 + a[1] * c2
        let di: Double = -(a[0] * s1 + a[1] * s2)
        return (nr * nr + ni * ni) / (dr * dr + di * di)
    }

    func reset() {
        for t in 0..<TrackTaps.tracks {
            rms[t] = 0
            kms[t] = 0
            mWho[t] = -1
            whoCand[t] = -1
            whoHold[t] = 0
            for j in 0..<MixAnalysis.bands {
                mStr[t][j] = 0
                mBur[t][j] = false
            }
            for j in 0..<MixAnalysis.bands { power[t][j] = 0 }
        }
    }

    /// Кадр: две дорожки из count; MASK (если mask) — по всем; audible — слышимые дорожки.
    func tick(_ taps: TrackTaps, count: Int, audible: [Bool], mask: Bool) {
        if count <= 0 { return }
        // Среднее за ~4 с: дорожка обновляется раз в count/2 кадров (60 в секунду).
        let a: Float = exp(-Float(count) / 480)
        for _ in 0..<2 {
            let t: Int = next % count
            next = (t + 1) % count
            analyze(taps, t, a)
        }
        if mask { updateMask(count, audible) }
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
        let ms: Float = sq / Float(n)
        // Тишина между ударами — спектр не трогаем (среднее держится); в LOUD тишина входит (как в LUFS).
        if r < 0.001 {
            kms[t] = kms[t] * a + ms * (1 - a)
            return
        }
        fftp.bands(UnsafePointer(raw), map, into: &fresh)
        for j in 0..<MixAnalysis.bands { power[t][j] = power[t][j] == 0 ? fresh[j] : power[t][j] * a + fresh[j] * (1 - a) }
        // Доля мощности после кривой K — по полосам этого окна.
        var all: Float = 0, wk: Float = 0
        for j in 0..<MixAnalysis.bands {
            all += fresh[j]
            wk += fresh[j] * kWeight[j]
        }
        let k: Float = all > 0 ? ms * wk / all : ms
        kms[t] = kms[t] == 0 ? k : kms[t] * a + k * (1 - a)
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

    /// LOUD дорожки t — линейно, как уровень метра (−0,691 dB BS.1770 и +3,01 dB: моно (L + R)/2 считается за два
    /// одинаковых канала; 0 dBFS синус 1 кГц в обоих — около 0); 0 — нет данных.
    func loud(_ t: Int) -> Float {
        guard t >= 0 && t < TrackTaps.tracks else { return 0 }
        let v: Float = kms[t]
        if v <= 1e-9 { return 0 }
        // 10^((−0,691 + 3,01) / 10) = 1,7058 (мощность).
        return (v * 1.7058).squareRoot()
    }

    /// MASK дорожки t (сглаженное, считает tick): сила конфликта по полосам (0…1), заглушают ли её там (узкая
    /// полоса) и номер дорожки, которая больше всех мешает в самом сильном конфликте (−1 — нет).
    func mask(_ t: Int) -> (strength: [Float], buried: [Bool], who: Int) {
        let nb: Int = MixAnalysis.bands
        guard t >= 0 && t < TrackTaps.tracks else {
            return ([Float](repeating: 0, count: nb), [Bool](repeating: false, count: nb), -1)
        }
        var bur = [Bool](repeating: false, count: nb)
        for j in 0..<nb { bur[j] = mBur[t][j] && mStr[t][j] >= MixAnalysis.maskShow }
        return (mStr[t], bur, mWho[t])
    }

    /// MASK за кадр (60 в секунду): явный конфликт — полоса важна для обеих дорожек (не ниже их самой сильной на
    /// maskSig dB); остальные (только такие) не тише дорожки больше чем на maskRange dB — сила 0…1 (громче или
    /// вровень — 1). Сила сглаживается (~1,5 с); «заглушают» — с гистерезисом maskHyst dB и видно, когда сила
    /// ≥ maskShow (конфликт держится ~2 с); номер мешающей меняется, если новая держится 1 с.
    private func updateMask(_ count: Int, _ audible: [Bool]) {
        let nb: Int = MixAnalysis.bands
        let tn: Int = TrackTaps.tracks
        let sig: Float = pow(10, -MixAnalysis.maskSig / 10)
        // 1 − exp(−1 / (60 · 1,5)).
        let k: Float = 0.01105
        var thr = [Float](repeating: Float.greatestFiniteMagnitude, count: tn)
        var live = [Bool](repeating: false, count: tn)
        for u in 0..<min(count, tn) {
            let ok: Bool = u < audible.count && audible[u] && rms[u] >= 0.0005
            var top: Float = 0
            for j in 0..<nb where power[u][j] > top { top = power[u][j] }
            if top > 0 { thr[u] = top * sig }
            live[u] = ok && top > 0
        }
        for t in 0..<tn {
            let on: Bool = t < count && rms[t] >= 0.0005 && thr[t] < Float.greatestFiniteMagnitude
            var bestScore: Float = 0, bestBand = -1
            for j in 0..<nb {
                var raw: Float = 0
                var bur: Bool = false
                let pj: Float = power[t][j]
                if on && pj >= thr[t] {
                    var other: Float = 0
                    for u in 0..<tn where u != t && live[u] && power[u][j] >= thr[u] { other += power[u][j] }
                    if other > 0 {
                        let d: Float = 10 * log10(other / pj)
                        raw = d >= 0 ? 1 : max(0, 1 + d / MixAnalysis.maskRange)
                        bur = mBur[t][j] ? d >= -MixAnalysis.maskHyst : d >= 0
                    }
                }
                mBur[t][j] = bur
                let v: Float = mStr[t][j] + (raw - mStr[t][j]) * k
                mStr[t][j] = v
                let score: Float = v * pj
                if v >= 0.3 && score > bestScore {
                    bestScore = score
                    bestBand = j
                }
            }
            var cand = -1
            if bestBand >= 0 {
                var loudest: Float = 0
                for u in 0..<tn where u != t && live[u] && power[u][bestBand] >= thr[u] {
                    if power[u][bestBand] > loudest {
                        loudest = power[u][bestBand]
                        cand = u
                    }
                }
            }
            if cand == mWho[t] {
                whoHold[t] = 0
            } else if cand == whoCand[t] {
                whoHold[t] += 1
                if whoHold[t] >= 60 || mWho[t] < 0 && cand >= 0 && whoHold[t] >= 30 {
                    mWho[t] = cand
                    whoHold[t] = 0
                }
            } else {
                whoCand[t] = cand
                whoHold[t] = 1
            }
        }
    }
}
