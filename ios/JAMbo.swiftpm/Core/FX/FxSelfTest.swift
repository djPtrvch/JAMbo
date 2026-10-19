import Foundation

// Самотест эффектов: сверка с эталонами Resources/golden/fx_*.i16 (ios/tools/fx/golden.mjs — рендер worklet'ов веба
// в Node: блоки по 128, k-rate параметры в начале блока, Math.random → mulberry32 с seed случая).
// Вход повторяет input() из golden.mjs. Общий для CoreTests и DIAGNOSTICS → SELF-TEST.

public enum FxSelfTest {
    public struct Case: Decodable, Sendable {
        public let file: String
        public let proc: String
        public let frames: Int
        public let seed: UInt32
        public let input: String
        public let params: [String: Double]?
        public let events: [Event]
    }

    /// В начале блока frame: новые значения параметров и (Sidechain) сообщения trig / flush.
    public struct Event: Decodable, Sendable {
        public let frame: Int
        public let params: [String: Double]?
        public let msg: [Msg]?
    }

    public struct Msg: Decodable, Sendable {
        public let type: String
        public let frame: Int64?
        public let attack: Double?
        public let release: Double?
        public let curve: Double?
    }

    public struct Cases: Decodable, Sendable {
        public let block: Int
        public let cases: [Case]
    }

    /// Коды эффектов в Result.engine (после движков 0–19) и их имена в SELF-TEST.
    public static let codes = ["delay": 32, "reverb": 33, "drive": 34, "duck": 35]
    public static let engineNames = [32: "DELAY", 33: "REVERB", 34: "DRIVE", 35: "SIDECHAIN"]

    public static func loadCases(_ goldenDir: URL) throws -> Cases {
        let data = try Data(contentsOf: goldenDir.appendingPathComponent("fx_cases.json"))
        return try JSONDecoder().decode(Cases.self, from: data)
    }

    /// mulberry32 как в golden.mjs (вход случая).
    static func input(_ kind: String, _ frames: Int) -> ([Float], [Float]) {
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        let sr: Double = 48000
        switch kind {
        case "burst":
            var rnd = FxRandom(7)
            for i in 0..<min(2400, frames) {
                l[i] = Float((rnd.next() * 2 - 1) * 0.5)
                r[i] = Float((rnd.next() * 2 - 1) * 0.5)
            }
            var i = 0
            while i < 2400 && 36000 + i < frames {
                l[36000 + i] = Float((rnd.next() * 2 - 1) * 0.25)
                r[36000 + i] = Float((rnd.next() * 2 - 1) * 0.25)
                i += 1
            }
        case "sine":
            for i in 0..<min(24000, frames) {
                let v = Float(0.25 * sin(2 * Double.pi * 440 * Double(i) / sr))
                l[i] = v
                r[i] = v
            }
        case "stereo":
            var rnd = FxRandom(11)
            for i in 0..<min(1440, frames) {
                l[i] = Float((rnd.next() * 2 - 1) * 0.5)
                r[i] = Float(0.3 * sin(2 * Double.pi * 660 * Double(i) / sr))
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
        var vals: [String: Double] = c.params ?? [:]
        let bL = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let bR = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let oL = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let oR = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer {
            bL.deallocate(); bR.deallocate(); oL.deallocate(); oR.deallocate()
        }
        // AudioParam — Float32 (как Float32Array в golden.mjs).
        func p(_ k: String, _ def: Double) -> Float { return Float(vals[k] ?? def) }
        let delay: FxDelay? = c.proc == "delay" ? FxDelay(sampleRate: 48000, maxTime: 6, seed: c.seed) : nil
        let reverb: FxReverb? = c.proc == "reverb" ? FxReverb(sampleRate: 48000, seed: c.seed) : nil
        let drive: FxDrive? = c.proc == "drive" ? FxDrive(sampleRate: 48000) : nil
        let duck: FxDuck? = c.proc == "duck" ? FxDuck(sampleRate: 48000) : nil
        var f = 0
        while f < c.frames {
            for e in c.events where e.frame == f {
                vals.merge(e.params ?? [:]) { _, b in b }
                for m in e.msg ?? [] {
                    if m.type == "flush" { duck?.flush() }
                    if m.type == "trig" {
                        duck?.trig(frame: m.frame ?? 0, attack: m.attack ?? 0, release: m.release ?? 0, curve: m.curve ?? 50)
                    }
                }
            }
            for i in 0..<block {
                bL[i] = f + i < c.frames ? iL[f + i] : 0
                bR[i] = f + i < c.frames ? iR[f + i] : 0
            }
            if let d = delay {
                d.process(inL: bL, inR: bR, outL: oL, outR: oR, frames: block, time: p("time", 0.25),
                          feedback: p("feedback", 0.4), filter: p("filter", 0), spread: p("spread", 0))
            }
            if let r = reverb {
                r.process(inL: bL, inR: bR, outL: oL, outR: oR, frames: block, size: p("size", 50), decay: p("decay", 2),
                          tone: p("tone", 0), lowcut: p("lowcut", 20), predelay: p("predelay", 0))
            }
            if let d = drive {
                d.process(inL: bL, inR: bR, outL: oL, outR: oR, frames: block, drive: p("drive", 26), type: p("type", 0),
                          tone: p("tone", 50), lowcut: p("lowcut", 20))
            }
            if let d = duck {
                d.process(blockStart: Int64(f), out: oL, frames: block)
                oR.update(from: oL, count: block)
            }
            var i = 0
            while i < block && f + i < c.frames {
                outL[f + i] = oL[i]
                outR[f + i] = oR[i]
                i += 1
            }
            f += block
        }
        // Как в эталоне: ±1, Int16.
        func q(_ x: [Float]) -> [Float] { return x.map { (min(max($0, -1), 1) * 32767).rounded() / 32767 } }
        return (q(outL), q(outR))
    }

    /// Один случай: L и R сравниваются отдельно, итог — худший из каналов (критерий и страховка — Golden).
    public static func run(_ c: Case, _ all: Cases, _ goldenDir: URL) throws -> Golden.Result {
        let (l, r) = render(c, block: all.block)
        let g = try Golden.load(goldenDir, c.file)
        var gl = [Float](repeating: 0, count: g.count / 2)
        var gr = [Float](repeating: 0, count: g.count / 2)
        for i in 0..<gl.count {
            gl[i] = g[2 * i]
            gr[i] = g[2 * i + 1]
        }
        let a = Golden.compare(c.file, 0, l, gl)
        let b = Golden.compare(c.file, 0, r, gr)
        let worst: Golden.Result = a.sampleErrorDb >= b.sampleErrorDb ? a : b
        return Golden.Result(file: c.file, engine: codes[c.proc] ?? 0, sampleErrorDb: worst.sampleErrorDb,
                                     maxBandDiffDb: max(a.maxBandDiffDb, b.maxBandDiffDb),
                                     rmsDb: max(a.rmsDb, b.rmsDb), finite: a.finite && b.finite)
    }
}
