// Сверка с эталонами Resources/golden (самотест своих движков, FX, мастера и EQ): чтение файлов, ошибка
// по отсчётам и третьоктавные полосы. Общий для CoreTests (Linux) и окна DIAGNOSTICS → SELF-TEST (iPad).
// Не для аудиоколбэка.
import Foundation

public enum Golden {
    /// Итог случая: ошибка по отсчётам (dB к RMS эталона), наибольшее отличие третьоктавной полосы (dB), RMS (dBFS).
    /// engine — код строки SELF-TEST (свои движки 16–19, FX 32–35, мастер 36–40, EQ 41).
    public struct Result: Sendable {
        public let file: String
        public let engine: Int
        public let sampleErrorDb: Double
        public let maxBandDiffDb: Double
        public let rmsDb: Double
        public let finite: Bool
        /// Критерий: по отсчётам ≤ −60 dB ИЛИ полосы 20 Hz–20 kHz в пределах ±0,5 dB.
        public var passes: Bool { sampleErrorDb <= -60 || maxBandDiffDb <= 0.5 }
        /// Итог: критерий + страховка (по отсчётам не хуже −40 dB — полярность, сдвиг), без NaN, не тишина
        /// (RMS выше −60 dBFS).
        public var ok: Bool { passes && finite && sampleErrorDb <= -40 && rmsDb > -60 }
    }

    /// Папка с файлом name: в bundle приложения ресурсы могут лежать в корне (.process) или в подпапке.
    public static func directory(of name: String, in bundle: Bundle, subdirectories: [String]) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for sub in [nil] + subdirectories.map({ Optional($0) }) {
            if let url = bundle.url(forResource: base, withExtension: ext, subdirectory: sub) {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    /// Эталон: Int16 → −1…1.
    public static func load(_ goldenDir: URL, _ file: String) throws -> [Float] {
        let data = try Data(contentsOf: goldenDir.appendingPathComponent(file))
        return data.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float($0) / 32767 }
        }
    }

    public static func compare(_ file: String, _ code: Int, _ actual: [Float], _ golden: [Float]) -> Result {
        let n = min(actual.count, golden.count)
        var err = 0.0, ref = 0.0
        for i in 0..<n {
            let d = Double(actual[i]) - Double(golden[i])
            err += d * d
            ref += Double(golden[i]) * Double(golden[i])
        }
        let sampleErrorDb = 10 * log10(max(err, 1e-30) / max(ref, 1e-30))
        let rmsDb = 10 * log10(max(ref / Double(max(n, 1)), 1e-30))
        let a = thirdOctaveBands(actual), g = thirdOctaveBands(golden)
        // Полосы, где обоих сигналов почти нет (ниже −80 dB от всей энергии), не сравниваются.
        let total = g.reduce(0, +)
        var maxDiff = 0.0
        for k in 0..<g.count where max(a[k], g[k]) > total * 1e-8 {
            maxDiff = max(maxDiff, abs(10 * log10(max(a[k], 1e-30) / max(g[k], 1e-30))))
        }
        let finite = !actual.contains { !$0.isFinite } && golden.count == actual.count
        return Result(file: file, engine: code, sampleErrorDb: sampleErrorDb, maxBandDiffDb: maxDiff,
                      rmsDb: rmsDb, finite: finite)
    }

    /// Энергия третьоктавных полос (центры 1000·2^(k/3), k = −17…13: 20 Hz…20 kHz) по БПФ всего сигнала (48 кГц).
    static func thirdOctaveBands(_ x: [Float]) -> [Double] {
        var size = 1
        while size < x.count { size <<= 1 }
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for i in 0..<x.count { re[i] = Double(x[i]) }
        fft(&re, &im)
        let binHz = 48000.0 / Double(size)
        var bands = [Double]()
        for k in -17...13 {
            let center = 1000 * pow(2, Double(k) / 3)
            let lo = center * pow(2, -1.0 / 6), hi = center * pow(2, 1.0 / 6)
            var e = 0.0
            var bin = max(1, Int((lo / binHz).rounded(.up)))
            while Double(bin) * binHz < hi && bin <= size / 2 {
                e += re[bin] * re[bin] + im[bin] * im[bin]
                bin += 1
            }
            bands.append(e)
        }
        return bands
    }

    /// БПФ по основанию 2, на месте; поворотные множители — таблицей.
    private static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        guard n > 1 else { return }
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        let half = n / 2
        var cosT = [Double](repeating: 0, count: half)
        var sinT = [Double](repeating: 0, count: half)
        for k in 0..<half {
            let ang = -2 * Double.pi * Double(k) / Double(n)
            cosT[k] = cos(ang)
            sinT[k] = sin(ang)
        }
        var len = 2
        while len <= n {
            let step = n / len
            for start in stride(from: 0, to: n, by: len) {
                for k in 0..<(len / 2) {
                    let wr = cosT[k * step], wi = sinT[k * step]
                    let a = start + k, b = a + len / 2
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
            }
            len <<= 1
        }
    }
}
