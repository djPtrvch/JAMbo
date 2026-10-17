import Foundation

// Самотест своих движков JAMbo (DRUM, ANALOG, FM, WTABLE): сверка с эталонами Resources/golden/j*.i16
// (ios/tools/jambo/golden.mjs — рендер public/jambo-synth-worklet.js в Node). Узел worklet повторён: блоки process()
// по 128 кадров (дрейф ANALOG — в начале блока, время дорожки — в конце), внутри — куски по 24 и до кадра
// следующей ноты; тишина дольше 4800 кадров — голос молчит. Общий для CoreTests и DIAGNOSTICS → SELF-TEST.

public enum JamboSelfTest {
    public struct Case: Decodable, Sendable {
        public let file: String
        public let engine: Int
        public let set: Int
        public let note: Double
        public let p1: Double
        public let p2: Double
        public let p3: Double
        public let decay: Double
        public let retrig: Int
        /// Таблица WTABLE (имя встроенной; у других движков — пусто).
        public let table: String?
    }

    public struct Cases: Decodable, Sendable {
        public let frames: Int
        public let block: Int
        public let chunk: Int
        public let cases: [Case]
    }

    public static let engineNames = [16: "DRUM", 17: "ANALOG", 18: "FM", 19: "WTABLE"]

    public static func loadCases(_ goldenDir: URL) throws -> Cases {
        let data = try Data(contentsOf: goldenDir.appendingPathComponent("jambo_cases.json"))
        return try JSONDecoder().decode(Cases.self, from: data)
    }

    /// Рендер как JamboProcessor с одним слотом.
    static func render(_ c: Case, _ all: Cases, tables: JamboTables, wavetable: WtTable? = nil) -> [Float] {
        let sr = 48000.0
        var ref = WtRef()
        if let wt = wavetable {
            ref = WtRef(frames: wt.frames, sizes: UnsafePointer(wt.sizes), data: UnsafePointer(wt.data))
        }
        let voice = JamboVoice(tables: tables, sampleRate: sr)
        var drift = JamboDrift()
        var result = [Float](repeating: 0, count: all.frames)
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: all.chunk)
        defer { buf.deallocate() }
        // Ноты: кадр 0 и (если есть) второй удар.
        var pending: [Int] = [0]
        if c.retrig > 0 { pending.append(c.retrig) }
        var end = Int.max
        var start0 = 0
        var quiet = 0
        var blockStart = 0
        while blockStart < all.frames {
            let frames = min(all.block, all.frames - blockStart)
            drift.begin(all.block, sr)
            var pos = 0
            while pos < frames {
                let now = blockStart + pos
                while let f = pending.first, f <= now {
                    pending.removeFirst()
                    end = Int.max
                    start0 = f
                    quiet = 0
                    voice.trigger(engine: c.engine, note: c.note, c.p1, c.p2, c.p3, decay: c.decay,
                                  now: Double(now), tau: drift.tau + Double(now - blockStart) * drift.ratio)
                }
                var n = min(all.chunk, frames - pos)
                if let f = pending.first { n = min(n, f - now) }
                if now >= end {
                    voice.last = 0
                } else {
                    voice.render(buf, n, driftRatio: drift.ratio, table: ref)
                    var peak: Float = 0
                    for i in 0..<n {
                        result[now + i] = buf[i]
                        peak = max(peak, abs(buf[i]))
                    }
                    quiet = peak < 1e-5 ? quiet + n : 0
                    if quiet > 4800 && now - start0 > 4800 { end = now }
                }
                pos += n
            }
            drift.end(all.block)
            blockStart += all.block
        }
        // Как в эталоне: ±1, Int16.
        return result.map { (min(max($0, -1), 1) * 32767).rounded() / 32767 }
    }

    /// Один случай: рендер и сравнение (критерий и страховка — как у Plaits).
    /// wavetables — кэш встроенных таблиц по имени (строятся при первом случае WTABLE).
    public static func run(_ c: Case, _ all: Cases, _ goldenDir: URL, tables: JamboTables,
                           wavetables: inout [String: WtTable]) throws -> PlaitsSelfTest.Result {
        var wt: WtTable? = nil
        if c.engine == Jambo.wtable {
            let name = c.table ?? "BASIC"
            if wavetables[name] == nil { wavetables[name] = WtTable.builtin(name) }
            wt = wavetables[name]
        }
        let actual = render(c, all, tables: tables, wavetable: wt)
        let golden = try PlaitsSelfTest.loadGolden(goldenDir, c.file)
        let pc = PlaitsSelfTest.Case(file: c.file, engine: c.engine, set: c.set, note: Float(c.note), harmonics: Float(c.p1),
                                     timbre: Float(c.p2), morph: Float(c.p3), aux: nil)
        return PlaitsSelfTest.compare(pc, actual, golden)
    }
}
