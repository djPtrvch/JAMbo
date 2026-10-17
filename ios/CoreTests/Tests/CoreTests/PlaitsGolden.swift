import Foundation
@testable import Core

/// Сверка движков Plaits с эталонами Resources/golden (ios/tools/plaits/golden.mjs: рендер plaits.wasm веба).
enum PlaitsGolden {
    struct Case: Decodable {
        let file: String
        let engine: Int
        let set: Int
        let note: Float
        let harmonics: Float
        let timbre: Float
        let morph: Float
    }

    struct Cases: Decodable {
        let frames: Int
        let block: Int
        let accent: Float
        let cases: [Case]
    }

    /// Итог сравнения: ошибка по отсчётам (dB к RMS эталона) и наибольшее отличие третьоктавной полосы (dB).
    struct Result {
        let sampleErrorDb: Double
        let maxBandDiffDb: Double
        let rmsDb: Double
        /// Критерий S3a: по отсчётам ≤ −60 dB ИЛИ полосы 20 Hz–20 kHz в пределах ±0,5 dB.
        var passes: Bool { sampleErrorDb <= -60 || maxBandDiffDb <= 0.5 }
    }

    static let resourcesDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("JAMbo.swiftpm/Resources")

    /// Таблицы с a0 веба: эталоны — wasm с a0 по 47872,34 Гц и нотой, сдвинутой на webNoteShift.
    static let resources: PlaitsResources? = {
        var r = PlaitsResources.load(dir: resourcesDir.appendingPathComponent("plaits"))
        r?.a0 = (440.0 / 8.0) / kCorrectedSampleRate
        return r
    }()

    /// Сдвиг ноты в вебе (plaits-worklet.js на 48 кГц), как SHIFT в golden.mjs: в Double, как в JS.
    static let webNoteShift: Double = 12 * log2(47872.34 / 48000)

    static func loadCases() throws -> Cases {
        let data = try Data(contentsOf: resourcesDir.appendingPathComponent("golden/cases.json"))
        return try JSONDecoder().decode(Cases.self, from: data)
    }

    static func loadGolden(_ file: String) throws -> [Float] {
        let data = try Data(contentsOf: resourcesDir.appendingPathComponent("golden/" + file))
        return data.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float($0) / 32767 }
        }
    }

    /// Рендер как render() в wasm/plaits/jambo_voices.cc (нота со сдвигом веба): триггер (фронт и гейт) в первом
    /// блоке, затем гейт снят;
    /// после движка — Post (усиление, < 0 — лимитер); aux_mix 0 — только OUT, ограничение ±1; Int16 как в эталоне.
    static func render(_ engine: PlaitsEngine, _ c: Case, frames: Int, block: Int, accent: Float,
                       outGain: Float, auxGain: Float) -> [Float] {
        var result = [Float](repeating: 0, count: frames)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: kMaxBlockSize)
        let aux = UnsafeMutablePointer<Float>.allocate(capacity: kMaxBlockSize)
        defer { out.deallocate(); aux.deallocate() }
        var limiter = StmLimiter()
        var auxLimiter = StmLimiter()
        // Выбор движка в set() jambo_voices.cc: LoadUserData(nullptr), затем Reset.
        engine.loadUserData()
        engine.reset()
        var p = EngineParameters()
        // Нота + сдвиг — в Double и затем во Float, как JS передаёт в wasm.
        p.note = Float(Double(c.note) + webNoteShift)
        p.harmonics = c.harmonics
        p.timbre = c.timbre
        p.morph = c.morph
        p.accent = accent
        var pos = 0
        while pos < frames {
            let n = min(block, frames - pos)
            p.trigger = pos == 0 ? (triggerRisingEdge | triggerHigh) : triggerLow
            var enveloped = engine.postProcessing.alreadyEnveloped
            engine.render(p, out, aux, n, &enveloped)
            post(&limiter, outGain, out, n)
            post(&auxLimiter, auxGain, aux, n)
            for i in 0..<n {
                let v = min(max(out[i], -1), 1)
                result[pos + i] = (v * 32767).rounded() / 32767
            }
            pos += n
        }
        return result
    }

    private static func post(_ limiter: inout StmLimiter, _ gainIn: Float, _ buffer: UnsafeMutablePointer<Float>,
                             _ size: Int) {
        var gain = gainIn
        if gain < 0 {
            limiter.process(-gain, buffer, size)
            gain = 1
        }
        for i in 0..<size { buffer[i] *= gain }
    }

    static func compare(_ actual: [Float], _ golden: [Float]) -> Result {
        let n = min(actual.count, golden.count)
        var err = 0.0, ref = 0.0
        for i in 0..<n {
            let d = Double(actual[i]) - Double(golden[i])
            err += d * d
            ref += Double(golden[i]) * Double(golden[i])
        }
        let sampleErrorDb = 10 * log10(max(err, 1e-30) / max(ref, 1e-30))
        let rmsDb = 10 * log10(max(ref / Double(n), 1e-30))
        let a = thirdOctaveBands(actual), g = thirdOctaveBands(golden)
        // Полосы, где обоих сигналов почти нет (ниже −80 dB от всей энергии), не сравниваются.
        let total = g.reduce(0, +)
        var maxDiff = 0.0
        for k in 0..<g.count where max(a[k], g[k]) > total * 1e-8 {
            maxDiff = max(maxDiff, abs(10 * log10(max(a[k], 1e-30) / max(g[k], 1e-30))))
        }
        return Result(sampleErrorDb: sampleErrorDb, maxBandDiffDb: maxDiff, rmsDb: rmsDb)
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

    /// БПФ по основанию 2, на месте.
    private static func fft(_ re: inout [Double], _ im: inout [Double]) {
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
            for start in stride(from: 0, to: n, by: len) {
                for k in 0..<(len / 2) {
                    let wr = cos(ang * Double(k)), wi = sin(ang * Double(k))
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
