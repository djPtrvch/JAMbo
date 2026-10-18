import Foundation

// Самотест EQ: сверка с эталонами Resources/golden/eq_*.i16 (ios/tools/eq/golden.mjs — EqChain веба в OfflineAudioContext
// Chromium). Как в вебе, EQ начинается пустым и первые полосы вводятся кроссфейдом; события — новый EQ в кадре блока.
// Вход — MasterSelfTest.input. Общий для CoreTests и DIAGNOSTICS → SELF-TEST.

public enum EqSelfTest {
    public struct Case: @unchecked Sendable {
        public let file: String
        public let frames: Int
        public let input: String
        /// EQ с кадра 0 и события — [(кадр, EQ)].
        let eqs: [(frame: Int, eq: Eq)]
    }

    /// Код в Result.engine (после мастера 36–40) и имя в SELF-TEST.
    public static let code = 41
    public static let engineNames = [41: "EQ"]
    static let block = 128

    static func parseEq(_ o: [String: Any]?) -> Eq {
        var eq = Eq()
        eq.on = (o?["on"] as? NSNumber)?.boolValue ?? true
        let list = o?["bands"] as? [Any] ?? []
        for (k, v) in list.enumerated() where k < EqSpec.bands {
            guard let b = v as? [String: Any] else { continue }
            func num(_ key: String) -> Double { return (b[key] as? NSNumber)?.doubleValue ?? 0 }
            eq.bands[k] = EqBand(on: (b["on"] as? NSNumber)?.boolValue ?? true, type: Int(num("type")), freq: num("freq"),
                                 gain: num("gain"), q: num("q"), slope: Int(num("slope")))
        }
        return eq
    }

    public static func loadCases(_ goldenDir: URL) throws -> [Case] {
        let data = try Data(contentsOf: goldenDir.appendingPathComponent("eq_cases.json"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["cases"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        return list.map { c in
            var eqs: [(frame: Int, eq: Eq)] = [(0, parseEq(c["eq"] as? [String: Any]))]
            for e in c["events"] as? [[String: Any]] ?? [] {
                eqs.append(((e["frame"] as? NSNumber)?.intValue ?? 0, parseEq(e["eq"] as? [String: Any])))
            }
            return Case(file: c["file"] as? String ?? "", frames: (c["frames"] as? NSNumber)?.intValue ?? 0,
                        input: c["input"] as? String ?? "", eqs: eqs)
        }
    }

    /// Рендер случая: L и R (Int16, как эталон).
    static func render(_ c: Case) -> ([Float], [Float]) {
        let (iL, iR) = MasterSelfTest.input(c.input, c.frames)
        var outL = [Float](repeating: 0, count: c.frames)
        var outR = [Float](repeating: 0, count: c.frames)
        let n = block
        let bL = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let bR = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: EqSpec.stride)
        defer { bL.deallocate(); bR.deallocate(); p.deallocate() }
        EqSpec.fill(p, Eq())
        let unit = EqUnit(sampleRate: 48000)
        var f = 0
        while f < c.frames {
            for e in c.eqs where e.frame == f { EqSpec.fill(p, e.eq) }
            for i in 0..<n {
                bL[i] = f + i < c.frames ? iL[f + i] : 0
                bR[i] = f + i < c.frames ? iR[f + i] : 0
            }
            unit.process(left: bL, right: bR, frames: n, params: p)
            var i = 0
            while i < n && f + i < c.frames {
                outL[f + i] = bL[i]
                outR[f + i] = bR[i]
                i += 1
            }
            f += n
        }
        func q(_ x: [Float]) -> [Float] { return x.map { (min(max($0, -1), 1) * 32767).rounded() / 32767 } }
        return (q(outL), q(outR))
    }

    /// Один случай: L и R сравниваются отдельно, итог — худший из каналов (критерий — как у Plaits).
    public static func run(_ c: Case, _ goldenDir: URL) throws -> PlaitsSelfTest.Result {
        let (l, r) = render(c)
        let g = try PlaitsSelfTest.loadGolden(goldenDir, c.file)
        var gl = [Float](repeating: 0, count: g.count / 2)
        var gr = [Float](repeating: 0, count: g.count / 2)
        for i in 0..<gl.count {
            gl[i] = g[2 * i]
            gr[i] = g[2 * i + 1]
        }
        let pc = PlaitsSelfTest.Case(file: c.file, engine: 0, set: 0, note: 0, harmonics: 0, timbre: 0, morph: 0, aux: nil)
        let a = PlaitsSelfTest.compare(pc, l, gl)
        let b = PlaitsSelfTest.compare(pc, r, gr)
        let worst: PlaitsSelfTest.Result = a.sampleErrorDb >= b.sampleErrorDb ? a : b
        return PlaitsSelfTest.Result(file: c.file, engine: code, sampleErrorDb: worst.sampleErrorDb,
                                     maxBandDiffDb: max(a.maxBandDiffDb, b.maxBandDiffDb),
                                     rmsDb: max(a.rmsDb, b.rmsDb), finite: a.finite && b.finite)
    }
}
