// Самопроверка движков Plaits: рендер против эталонов из plaits.wasm (ios/tools/plaits/golden.mjs).
// Критерии (docs/SWIFT_AUDIT.md, риск 2): поотсчётная ошибка ≤ −60 dB к RMS эталона; если нет —
// спектр по третьоктавам (20 Гц…20 кГц, полосы не тише −60 dB от самой громкой) в пределах ±0,5 dB.
// Причина второго критерия: plaits.wasm собран с -ffast-math, и в движках с обратной связью
// (фазовая обратная связь FM) ошибки округления копятся в фазе — на слух разницы нет.
import Foundation

public struct PlaitsGoldenCase: Decodable {
    public let file: String
    public let engine: Int
    public let note: Float
    public let harmonics, timbre, morph: Float
}

public struct PlaitsGoldenSet: Decodable {
    public let frames: Int
    public let block: Int
    public let accent: Float
    public let cases: [PlaitsGoldenCase]
}

public struct PlaitsCheckResult {
    public let file: String
    public let engine: Int
    /// Поотсчётная ошибка, dB к RMS эталона.
    public let sampleDB: Double
    /// Наибольшее отклонение третьоктавной полосы, dB.
    public let bandDB: Double
    public var passed: Bool { sampleDB <= -60 || bandDB <= 0.5 }
    public var bySamples: Bool { sampleDB <= -60 }
}

public enum PlaitsSelfTest {
    /// Сдвиг ноты на 48 кГц, как в вебе: Plaits настроен на 47872,34 Гц.
    public static let noteShift: Float = 12 * log2(Float(47872.34) / 48000)

    public static func loadSet(dir: URL) -> PlaitsGoldenSet? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("cases.json")) else { return nil }
        return try? JSONDecoder().decode(PlaitsGoldenSet.self, from: d)
    }

    /// Рендер голоса так же, как эталон: свежий голос, триггер, блоки по 24 с release после каждого.
    public static func render(_ c: PlaitsGoldenCase, frames: Int, block: Int, accent: Float, lut: PlaitsLUT) -> [Float] {
        let v = PlaitsVoice(lut: lut)
        v.set(engine: c.engine, note: c.note + noteShift, harmonics: c.harmonics, timbre: c.timbre, morph: c.morph,
              accent: accent, aux: 0)
        v.trigger()
        var out = [Float](repeating: 0, count: frames)
        var pos = 0
        while pos < frames {
            let n = min(block, frames - pos)
            v.render(n)
            v.release()
            for i in 0..<n { out[pos + i] = v.output[i] }
            pos += n
        }
        return out
    }

    public static func check(_ c: PlaitsGoldenCase, set: PlaitsGoldenSet, dir: URL, lut: PlaitsLUT) -> PlaitsCheckResult? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(c.file)) else { return nil }
        let ref: [Float] = d.withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { Float($0) / 32767 } }
        let x = render(c, frames: ref.count, block: set.block, accent: set.accent, lut: lut)
        var err = 0.0, sig = 0.0
        for i in 0..<ref.count {
            let e = Double(x[i] - ref[i])
            err += e * e
            sig += Double(ref[i]) * Double(ref[i])
        }
        let sampleDB = 10 * log10(max(err, 1e-30) / max(sig, 1e-30))
        let a = bands(ref), b = bands(x)
        let top = a.max() ?? 0
        var worst = 0.0
        for k in 0..<a.count where a[k] > top - 60 {
            worst = max(worst, abs(a[k] - b[k]))
        }
        return PlaitsCheckResult(file: c.file, engine: c.engine, sampleDB: sampleDB, bandDB: worst)
    }

    // MARK: - Третьоктавный спектр (Уэлч: окна Ханна 8192, шаг 4096)

    static let fftSize = 8192

    /// Уровни полос (dB) от 20 Гц до 20 кГц, частота 48 кГц.
    public static func bands(_ x: [Float]) -> [Double] {
        let n = fftSize
        var power = [Double](repeating: 0, count: n / 2)
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        var count = 0
        var start = 0
        while start + n <= x.count {
            for i in 0..<n {
                let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n))
                re[i] = Double(x[start + i]) * w
                im[i] = 0
            }
            fft(&re, &im)
            for k in 0..<n / 2 { power[k] += re[k] * re[k] + im[k] * im[k] }
            count += 1
            start += n / 2
        }
        let sr = 48000.0
        var res: [Double] = []
        var fc = 20.0
        while fc <= 20000 {
            let lo = fc / pow(2, 1.0 / 6), hi = fc * pow(2, 1.0 / 6)
            var s = 0.0
            let k0 = max(1, Int((lo / sr * Double(n)).rounded(.up)))
            let k1 = min(n / 2 - 1, Int(hi / sr * Double(n)))
            if k0 <= k1 { for k in k0...k1 { s += power[k] } }
            res.append(10 * log10(max(s / Double(max(count, 1)), 1e-30)))
            fc *= pow(2, 1.0 / 3)
        }
        return res
    }

    /// БПФ по основанию 2 на месте.
    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2 * Double.pi / Double(len)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0
                for k in 0..<len / 2 {
                    let ur = re[i + k], ui = im[i + k]
                    let vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci
                    let vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr
                    re[i + k] = ur + vr; im[i + k] = ui + vi
                    re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi
                    let t = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = t
                }
                i += len
            }
            len <<= 1
        }
    }
}
