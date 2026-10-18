import Foundation

// Самотест мастера: сверка с эталонами Resources/golden/mst_*.i16 (ios/tools/master/golden.mjs — рендер worklet'ов веба
// в Node: блоки по 128, параметры — сообщения port в начале блока). Вход повторяет input() из golden.mjs.
// Общий для CoreTests и DIAGNOSTICS → SELF-TEST.

public enum MasterSelfTest {
    public struct Case: @unchecked Sendable {
        public let file: String
        public let proc: String
        public let frames: Int
        public let input: String
        /// Сообщения: начальное (кадр 0) и события — [(кадр, сообщение)]; у chain сообщение — { sat, glue, clip, lim }.
        let msgs: [(frame: Int, msg: [String: Any])]
    }

    public struct Cases: @unchecked Sendable {
        public let block: Int
        public let cases: [Case]
    }

    /// Коды в Result.engine (после FX 32–35) и имена в SELF-TEST.
    public static let codes = ["saturator": 36, "glue": 37, "clipper": 38, "limiter": 39, "chain": 40]
    public static let engineNames = [36: "MST SAT", 37: "MST COMP", 38: "MST CLIP", 39: "MST LIM", 40: "MST CHAIN"]

    public static func loadCases(_ goldenDir: URL) throws -> Cases {
        let data = try Data(contentsOf: goldenDir.appendingPathComponent("mst_cases.json"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["cases"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        var cases: [Case] = []
        for c in list {
            var msgs: [(frame: Int, msg: [String: Any])] = [(0, c["msg"] as? [String: Any] ?? [:])]
            for e in c["events"] as? [[String: Any]] ?? [] {
                msgs.append(((e["frame"] as? NSNumber)?.intValue ?? 0, e["msg"] as? [String: Any] ?? [:]))
            }
            cases.append(Case(file: c["file"] as? String ?? "", proc: c["proc"] as? String ?? "",
                              frames: (c["frames"] as? NSNumber)?.intValue ?? 0, input: c["input"] as? String ?? "",
                              msgs: msgs))
        }
        return Cases(block: (root["block"] as? NSNumber)?.intValue ?? 128, cases: cases)
    }

    /// Ключи сообщений worklet'ов → номера MasterChain.Index.
    static let keys: [String: [String: Int]] = {
        let I = MasterChain.Index.self
        return [
            "sat": ["drive": I.satDrive, "type": I.satType, "tone": I.satTone, "mix": I.satMix, "focus": I.satFocus],
            "glue": ["thr": I.cmpThr, "att": I.cmpAtt, "rel": I.cmpRel, "auto": I.cmpAuto, "makeup": I.cmpMakeup,
                     "ratio": I.cmpRatio, "knee": I.cmpKnee, "mix": I.cmpMix, "schpf": I.cmpSchpf, "bypass": I.cmpBypass],
            "clip": ["drive": I.clipDrive, "ceiling": I.clipCeiling, "softness": I.clipSoftness, "bass": I.clipBass,
                     "bypass": I.clipBypass],
            "lim": ["gain": I.limGain, "ceiling": I.limCeiling, "lookahead": I.limLookahead, "rel": I.limRel,
                    "auto": I.limAuto, "bypass": I.limBypass],
        ]
    }()

    static let modules = ["saturator": "sat", "glue": "glue", "clipper": "clip", "limiter": "lim"]

    static func apply(_ msg: [String: Any], _ module: String, _ p: UnsafeMutablePointer<Double>) {
        guard let map = keys[module] else { return }
        for (k, v) in msg {
            guard let idx = map[k] else { continue }
            // Числа и true/false (у JSONSerialization на Mac true — тоже NSNumber, 1).
            if let n = v as? NSNumber { p[idx] = n.doubleValue } else if let b = v as? Bool { p[idx] = b ? 1 : 0 }
        }
    }

    /// Вход случая (Float32) — как input() в golden.mjs.
    static func input(_ kind: String, _ frames: Int) -> ([Float], [Float]) {
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        let sr: Double = 48000
        switch kind {
        case "sine":
            for i in 0..<min(24000, frames) {
                let v = Float(0.25 * sin((2 * Double.pi * 440 * Double(i)) / sr))
                l[i] = v
                r[i] = v
            }
        case "stereo":
            var rnd = FxRandom(11)
            for i in 0..<min(1440, frames) {
                l[i] = Float((rnd.next() * 2 - 1) * 0.5)
                r[i] = Float(0.3 * sin((2 * Double.pi * 660 * Double(i)) / sr))
            }
        case "drums":
            var rnd = FxRandom(5)
            for i in 0..<frames {
                let t: Double = Double(i % 12000) / sr
                let th: Double = Double((i + 6000) % 12000) / sr
                let ph: Double = 55 * t + 40 * 0.03 * (1 - exp(-t / 0.03))
                let kick: Double = 0.9 * exp(-t / 0.12) * sin(2 * Double.pi * ph)
                let hat: Double = 0.4 * exp(-th / 0.015) * (rnd.next() * 2 - 1)
                l[i] = Float(kick + hat)
                r[i] = Float(kick + hat + 0.2 * sin((2 * Double.pi * 220 * Double(i)) / sr))
            }
        case "loud":
            for i in 0..<frames {
                let v: Double = i < 24000 ? sin((2 * Double.pi * 1000 * Double(i)) / sr)
                    : 0.708 * sin((2 * Double.pi * 5000 * Double(i)) / sr)
                l[i] = Float(v)
                r[i] = Float(0.9 * v)
            }
        default:
            break
        }
        return (l, r)
    }

    /// Рендер случая: L и R.
    static func render(_ c: Case, block: Int) -> ([Float], [Float]) {
        let (iL, iR) = input(c.input, c.frames)
        var outL = [Float](repeating: 0, count: c.frames)
        var outR = [Float](repeating: 0, count: c.frames)
        let bL = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let bR = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: MasterChain.Index.count)
        defer { bL.deallocate(); bR.deallocate(); p.deallocate() }
        for (k, v) in MasterChain.defaults.enumerated() { p[k] = v }
        let chain = MasterChain(sampleRate: 48000)
        let I = MasterChain.Index.self
        var f = 0
        while f < c.frames {
            for m in c.msgs where m.frame == f {
                if c.proc == "chain" {
                    for mod in ["sat", "glue", "clip", "lim"] { apply(m.msg[mod] as? [String: Any] ?? [:], mod, p) }
                } else {
                    apply(m.msg, modules[c.proc] ?? "", p)
                }
            }
            var i = 0
            while i < block {
                bL[i] = f + i < c.frames ? iL[f + i] : 0
                bR[i] = f + i < c.frames ? iR[f + i] : 0
                i += 1
            }
            switch c.proc {
            case "saturator":
                chain.sat.process(inL: bL, inR: bR, outL: bL, outR: bR, frames: block, drive: p[I.satDrive],
                                  type: p[I.satType], tone: p[I.satTone], mix: p[I.satMix], focus: p[I.satFocus])
            case "glue":
                chain.glue.process(inL: bL, inR: bR, outL: bL, outR: bR, frames: block, thr: p[I.cmpThr], att: p[I.cmpAtt],
                                   rel: p[I.cmpRel], auto: p[I.cmpAuto] >= 0.5, makeup: p[I.cmpMakeup],
                                   ratio: p[I.cmpRatio], knee: p[I.cmpKnee], mix: p[I.cmpMix], schpf: p[I.cmpSchpf],
                                   bypass: p[I.cmpBypass] >= 0.5)
            case "clipper":
                chain.clip.process(inL: bL, inR: bR, outL: bL, outR: bR, frames: block, drive: p[I.clipDrive],
                                   ceiling: p[I.clipCeiling], softness: p[I.clipSoftness], bass: p[I.clipBass],
                                   bypass: p[I.clipBypass] >= 0.5)
            case "limiter":
                chain.lim.process(inL: bL, inR: bR, outL: bL, outR: bR, frames: block, gain: p[I.limGain],
                                  ceiling: p[I.limCeiling], lookahead: p[I.limLookahead], rel: p[I.limRel],
                                  auto: p[I.limAuto] >= 0.5, bypass: p[I.limBypass] >= 0.5)
            default:
                chain.process(left: bL, right: bR, frames: block, params: p)
            }
            i = 0
            while i < block && f + i < c.frames {
                outL[f + i] = bL[i]
                outR[f + i] = bR[i]
                i += 1
            }
            f += block
        }
        func q(_ x: [Float]) -> [Float] { return x.map { (min(max($0, -1), 1) * 32767).rounded() / 32767 } }
        return (q(outL), q(outR))
    }

    /// Один случай: L и R сравниваются отдельно, итог — худший из каналов (критерий — как у Plaits).
    public static func run(_ c: Case, _ all: Cases, _ goldenDir: URL) throws -> PlaitsSelfTest.Result {
        let (l, r) = render(c, block: all.block)
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
        return PlaitsSelfTest.Result(file: c.file, engine: codes[c.proc] ?? 0, sampleErrorDb: worst.sampleErrorDb,
                                     maxBandDiffDb: max(a.maxBandDiffDb, b.maxBandDiffDb),
                                     rmsDb: max(a.rmsDb, b.rmsDb), finite: a.finite && b.finite)
    }
}
