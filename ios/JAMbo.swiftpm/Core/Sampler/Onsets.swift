import Foundation

// Атаки сэмпла (для таймстретча NORMAL, потом — для точек варпинга): энергия по кадрам 128 отсчётов (сумма каналов и
// её разность соседних отсчётов — верх весомее), рост логарифма энергии за кадр; атака — рост больше 9 dB над средним
// за 50 мс до неё, не чаще раза в 50 мс; позиция — начало подъёма (минимум огибающей в 5 мс перед пиком роста).
// Считается один раз на сэмпл, в основном потоке (SampleData.onsets).

public final class OnsetList: @unchecked Sendable {
    public let count: Int
    /// Позиции атак в отсчётах, по возрастанию.
    public let at: UnsafeMutablePointer<Double>

    init(_ list: [Double]) {
        count = list.count
        at = .allocate(capacity: Swift.max(1, list.count))
        at.initialize(repeating: 0, count: Swift.max(1, list.count))
        var i = 0
        while i < list.count {
            at[i] = list[i]
            i += 1
        }
    }

    deinit { at.deallocate() }
}

public enum Onsets {
    static let hop = 128

    public static func detect(_ s: SampleData) -> [Double] {
        let h = hop
        let n: Int = s.frames / h
        if n < 4 { return [] }
        let l = s.left, r = s.right
        // Энергия кадра: сигнал и его разность (верх) — в dB.
        var e = [Double](repeating: 0, count: n)
        var prev: Float = 0
        var k = 0
        while k < n {
            var a: Float = 0
            var i = k * h
            let end = i + h
            while i < end {
                let m: Float = s.channels > 1 ? (l[i] + r[i]) * 0.5 : l[i]
                let d: Float = m - prev
                prev = m
                a += m * m + 4 * d * d
                i += 1
            }
            e[k] = 10 * log10(1e-10 + Double(a) / Double(h))
            k += 1
        }
        let back: Int = Swift.max(2, Int(0.05 * AudioCore.sampleRate) / h)
        let gap: Int = back
        var out: [Double] = []
        var last: Int = -gap
        k = 1
        while k < n {
            // Среднее за 50 мс до кадра (в dB) и рост над ним; кадр — пик роста среди соседей.
            var sum: Double = 0
            var c = 0
            var j = Swift.max(0, k - back)
            while j < k {
                sum += e[j]
                c += 1
                j += 1
            }
            let base: Double = sum / Double(Swift.max(1, c))
            let rise: Double = e[k] - base
            let loud: Bool = e[k] > -60
            let next: Double = k + 1 < n ? e[k + 1] - base : -1000
            if loud && rise > 9 && rise >= next && k - last >= gap {
                out.append(start(s, k * h))
                last = k
            }
            k += 1
        }
        return out
    }

    /// Начало подъёма около кадра атаки: последнее место (по 4 отсчёта, модуль сглажен по 16) тише 5 % пика перед первым
    /// подъёмом выше 25 % пика; с запасом 1 мс назад.
    static func start(_ s: SampleData, _ at: Int) -> Double {
        let w: Int = Int(0.005 * AudioCore.sampleRate)
        let from: Int = Swift.max(0, at - w)
        let end: Int = Swift.min(s.frames - 16, at + 2 * hop)
        if end <= from { return Double(at) }
        var peak: Float = 0
        var j = from
        while j < end + 16 {
            peak = Swift.max(peak, Swift.abs(s.left[j]) + Swift.abs(s.right[j]))
            j += 1
        }
        var best: Int = at
        var i: Int = from
        while i <= end {
            var a: Float = 0
            var q = i
            while q < i + 16 {
                a += Swift.abs(s.left[q]) + Swift.abs(s.right[q])
                q += 1
            }
            a /= 16
            if a > 0.25 * peak { break }
            if a < 0.05 * peak { best = i + 16 }
            i += 4
        }
        let pre: Int = Int(0.001 * AudioCore.sampleRate)
        return Double(Swift.max(0, best - pre))
    }
}
