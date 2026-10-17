// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// Самотест движков Plaits: сверка с эталонами Resources/golden (ios/tools/plaits/golden.mjs — рендер plaits.wasm веба).
// Общий для CoreTests (Linux) и окна DIAGNOSTICS → SELF-TEST (iPad). Не для аудиоколбэка.
import Foundation

public enum PlaitsSelfTest {
    public struct Case: Decodable, Sendable {
        public let file: String
        public let engine: Int
        public let set: Int
        public let note: Float
        public let harmonics: Float
        public let timbre: Float
        public let morph: Float
    }

    public struct Cases: Decodable, Sendable {
        public let frames: Int
        public let block: Int
        public let accent: Float
        public let cases: [Case]
    }

    /// Итог случая: ошибка по отсчётам (dB к RMS эталона), наибольшее отличие третьоктавной полосы (dB), RMS (dBFS).
    public struct Result: Sendable {
        public let file: String
        public let engine: Int
        public let sampleErrorDb: Double
        public let maxBandDiffDb: Double
        public let rmsDb: Double
        public let finite: Bool
        /// Критерий S3a: по отсчётам ≤ −60 dB ИЛИ полосы 20 Hz–20 kHz в пределах ±0,5 dB.
        public var passes: Bool { sampleErrorDb <= -60 || maxBandDiffDb <= 0.5 }
        /// Итог: критерий + страховка (по отсчётам не хуже −40 dB — полярность, сдвиг), без NaN, не тишина.
        public var ok: Bool { passes && finite && sampleErrorDb <= -40 && rmsDb > -40 }
    }

    public static let engineNames = ["VA", "WAVESHAPE", "FM", "GRAIN", "ADDITIVE", "WAVETABLE", "CHORDS", "SPEECH"]
    /// Усиления OUT и AUX (< 0 — лимитер) — те же, что у голоса синта (jambo_voices.cc).
    static var outGains: [Float] { return SynthVoices.outGains }
    static var auxGains: [Float] { return SynthVoices.auxGains }

    /// Сдвиг ноты в вебе (plaits-worklet.js на 48 кГц), как SHIFT в golden.mjs: в Double, как в JS.
    static let webNoteShift: Double = 12 * log2(47872.34 / 48000)

    static func makeEngine(_ index: Int, _ r: PlaitsResources) -> PlaitsEngine {
        switch index {
        case 0: return VirtualAnalogEngine(resources: r)
        case 1: return WaveshapingEngine(resources: r)
        case 2: return FMEngine(resources: r)
        case 3: return GrainEngine(resources: r)
        case 4: return AdditiveEngine(resources: r)
        case 5: return WavetableEngine(resources: r)
        case 6: return ChordEngine(resources: r)
        default: return SpeechEngine(resources: r, random: StmRandom())
        }
    }

    // MARK: Файлы

    /// Папка с файлом name: в bundle приложения ресурсы могут лежать в корне (.process) или в подпапке.
    public static func directory(of name: String, in bundle: Bundle, subdirectories: [String]) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for sub in [nil] + subdirectories.map { Optional($0) } {
            if let url = bundle.url(forResource: base, withExtension: ext, subdirectory: sub) {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    /// Таблицы с a0 веба: эталоны — wasm с a0 по 47872,34 Гц и нотой, сдвинутой на webNoteShift.
    public static func webResources(_ tablesDir: URL) -> PlaitsResources? {
        var r = PlaitsResources.load(dir: tablesDir)
        r?.a0 = (440.0 / 8.0) / kCorrectedSampleRate
        return r
    }

    public static func loadCases(_ goldenDir: URL) throws -> Cases {
        let data = try Data(contentsOf: goldenDir.appendingPathComponent("cases.json"))
        return try JSONDecoder().decode(Cases.self, from: data)
    }

    public static func loadGolden(_ goldenDir: URL, _ file: String) throws -> [Float] {
        let data = try Data(contentsOf: goldenDir.appendingPathComponent(file))
        return data.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float($0) / 32767 }
        }
    }

    // MARK: Прогон

    /// Один случай: свежий движок (как свежий экземпляр wasm в эталоне), рендер, сравнение.
    public static func run(_ c: Case, _ all: Cases, _ r: PlaitsResources, _ goldenDir: URL) throws -> Result {
        let engine = makeEngine(c.engine, r)
        let actual = render(engine, c, frames: all.frames, block: all.block, accent: all.accent,
                            outGain: outGains[c.engine], auxGain: auxGains[c.engine])
        let golden = try loadGolden(goldenDir, c.file)
        return compare(c, actual, golden)
    }

    /// Рендер как render() в wasm/plaits/jambo_voices.cc: выбор движка (LoadUserData, Reset), триггер (фронт и гейт)
    /// в первом блоке, затем гейт снят; после движка — Post (усиление, < 0 — лимитер); aux_mix 0 — OUT, ±1, Int16.
    static func render(_ engine: PlaitsEngine, _ c: Case, frames: Int, block: Int, accent: Float,
                       outGain: Float, auxGain: Float) -> [Float] {
        var result = [Float](repeating: 0, count: frames)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: kMaxBlockSize)
        let aux = UnsafeMutablePointer<Float>.allocate(capacity: kMaxBlockSize)
        defer { out.deallocate(); aux.deallocate() }
        var limiter = StmLimiter()
        var auxLimiter = StmLimiter()
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

    static func compare(_ c: Case, _ actual: [Float], _ golden: [Float]) -> Result {
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
        return Result(file: c.file, engine: c.engine, sampleErrorDb: sampleErrorDb, maxBandDiffDb: maxDiff,
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
