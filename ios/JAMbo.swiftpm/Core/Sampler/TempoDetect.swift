import Foundation

// Темп файла (S15g, референс): огибающая атак (рост громкости всей полосы и низа, кадры по 256 отсчётов), её
// автокорреляция и гребёнка кратных долей — у какого темпа доли и их половины (на отрезке 6,4 с) совпадают с атаками
// лучше всего.
// Диапазон 75…180 BPM (ближе к 125; половинный темп, если двойной почти так же хорош, — двойной). Отрезок — 40 с с 20 % длины.

public enum TempoDetect {
    static let hop = 256
    static let lo: Double = 75
    static let hi: Double = 180

    /// Темп, BPM (около целого — целый); nil — не нашёлся (тишина, слишком коротко).
    public static func bpm(_ s: SampleData) -> Double? {
        let rate: Double = AudioCore.sampleRate
        let fr: Double = rate / Double(hop)
        let want: Int = Int(40 * rate)
        let total: Int = s.frames
        if total < Int(6 * rate) { return nil }
        let len: Int = Swift.min(want, total)
        let from: Int = Swift.min(total - len, total / 5)
        let onset: [Double] = envelope(s, from: from, count: len)
        let n: Int = onset.count
        let maxLag: Int = Int(8 * 60 * fr / lo) + 2
        if n < maxLag + 16 { return nil }
        let r: [Double] = autocorr(onset, maxLag)
        if r[0] <= 0 { return nil }
        let span: Double = Double(maxLag - 2)
        // Грубо — шаг 0,5 BPM, затем точнее — 0,01 возле лучшего.
        var best: Double = 0
        var bestScore: Double = -1
        var b: Double = lo
        while b < hi {
            let sc: Double = score(r, b, fr, span)
            if sc > bestScore {
                bestScore = sc
                best = b
            }
            b += 0.5
        }
        if bestScore <= 0 { return nil }
        // Половинный темп (у ритма с атакой на каждой доле 87 и 174 одинаково законны): двойной в диапазоне и почти
        // так же хорош — двойной.
        let twice: Double = best * 2
        if twice < hi && score(r, twice, fr, span) >= 0.8 * bestScore { best = twice }
        var fine: Double = best
        var fineScore: Double = -1
        b = best - 0.6
        while b <= best + 0.6 {
            let sc: Double = score(r, b, fr, span)
            if sc > fineScore {
                fineScore = sc
                fine = b
            }
            b += 0.01
        }
        let whole: Double = fine.rounded()
        if abs(fine - whole) < 0.2 { return whole }
        return (fine * 10).rounded() / 10
    }

    /// Среднее автокорреляции на долях темпа bpm в пределах span кадров и с весом 0,5 — на половинах долей (у темпа
    /// 2/3 и 3/2 от верного половины долей — мимо атак); один отрезок времени у всех темпов (иначе медленный набирал
    /// больше долей), мягкое предпочтение темпа около 125.
    static func score(_ r: [Double], _ bpm: Double, _ fr: Double, _ span: Double) -> Double {
        let lag: Double = 60 * fr / bpm
        var sum: Double = 0
        var k: Int = 1
        while Double(k) * lag <= span {
            sum += interp(r, lag * Double(k))
            sum += 0.5 * interp(r, lag * (Double(k) - 0.5))
            k += 1
        }
        if k == 1 { return 0 }
        let oct: Double = abs(log2(bpm / 125))
        return sum / Double(k - 1) * (1 - 0.15 * oct)
    }

    static func interp(_ r: [Double], _ x: Double) -> Double {
        let i: Int = Int(x)
        if i + 1 >= r.count || i < 0 { return 0 }
        let f: Double = x - Double(i)
        return r[i] * (1 - f) + r[i + 1] * f
    }

    /// Атаки по кадрам: рост логарифма энергии всей полосы и низа (ФНЧ ~150 Гц), минус среднее за ~0,5 с, не меньше 0.
    static func envelope(_ s: SampleData, from: Int, count: Int) -> [Double] {
        let n: Int = count / hop
        var full = [Double](repeating: 0, count: n)
        var low = [Double](repeating: 0, count: n)
        let l = s.left, r = s.right
        let a: Float = 0.0194
        var lp: Float = 0
        var k = 0
        while k < n {
            var e: Float = 0
            var el: Float = 0
            var i: Int = from + k * hop
            let end: Int = i + hop
            while i < end {
                let m: Float = (l[i] + r[i]) * 0.5
                lp += (m - lp) * a
                e += m * m
                el += lp * lp
                i += 1
            }
            full[k] = log(1 + 1000 * Double(e))
            low[k] = log(1 + 1000 * Double(el))
            k += 1
        }
        var d = [Double](repeating: 0, count: n)
        k = 1
        while k < n {
            let x: Double = Swift.max(0, full[k] - full[k - 1])
            let y: Double = Swift.max(0, low[k] - low[k - 1])
            d[k] = x + y
            k += 1
        }
        // Минус скользящее среднее (±47 кадров ≈ 0,25 с в каждую сторону).
        let w: Int = 47
        var out = [Double](repeating: 0, count: n)
        var acc: Double = 0
        var lo: Int = 0
        var hi: Int = 0
        k = 0
        while k < n {
            while hi < Swift.min(n, k + w + 1) {
                acc += d[hi]
                hi += 1
            }
            while lo < k - w {
                acc -= d[lo]
                lo += 1
            }
            let mean: Double = acc / Double(hi - lo)
            out[k] = Swift.max(0, d[k] - mean)
            k += 1
        }
        return out
    }

    /// Автокорреляция (нормированная на число пар) для лагов 0…maxLag.
    static func autocorr(_ x: [Double], _ maxLag: Int) -> [Double] {
        let n: Int = x.count
        var r = [Double](repeating: 0, count: maxLag + 1)
        x.withUnsafeBufferPointer { p in
            var lag = 0
            while lag <= maxLag {
                var sum: Double = 0
                var i = 0
                let m: Int = n - lag
                while i < m {
                    sum += p[i] * p[i + lag]
                    i += 1
                }
                r[lag] = sum / Double(Swift.max(1, m))
                lag += 1
            }
        }
        return r
    }
}
