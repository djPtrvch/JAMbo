import XCTest
@testable import Core

final class MixBlendTests: XCTestCase {
    private func transition(_ a: Project, _ b: Project) -> MixTransition {
        return MixTransition(from: MixGlobals(a), to: MixGlobals(b))
    }

    func testNumbersBlendSmoothly() {
        var a = Project()
        var b = Project()
        a.bpm = 100
        b.bpm = 140
        a.tracks[2].vol = -20
        b.tracks[2].vol = 0
        a.outVol = -12
        a.master["cmp.ratio"] = 2
        b.master["cmp.ratio"] = 10
        let tr = transition(a, b)
        let m = tr.blend(0.25)
        XCTAssertEqual(m.globals.bpm, 110)
        XCTAssertEqual(m.globals.vols[2], -15, accuracy: 1e-9)
        XCTAssertEqual(m.globals.outVol, -9, accuracy: 1e-9)
        XCTAssertEqual(m.globals.master["cmp.ratio"]!, 4, accuracy: 1e-9)
        XCTAssertEqual(m.master[MasterChain.Index.cmpRatio], 4, accuracy: 1e-9)
        XCTAssertEqual(tr.blend(0).globals, tr.from)
        XCTAssertEqual(tr.blend(1).globals, tr.to)
    }

    func testBypassIsFraction() {
        var a = Project()
        let b = Project()
        a.limBypass = true
        a.satBypass = true
        let tr = transition(a, b)
        let I = MasterChain.Index.self
        XCTAssertEqual(tr.blend(0).master[I.limBypass], 1)
        XCTAssertEqual(tr.blend(0.25).master[I.limBypass], 0.75, accuracy: 1e-9)
        XCTAssertEqual(tr.blend(0.25).master[I.satBypass], 0.75, accuracy: 1e-9)
        XCTAssertTrue(tr.blend(0.25).globals.limBypass)
        XCTAssertFalse(tr.blend(0.75).globals.limBypass)
        XCTAssertEqual(tr.blend(1).master[I.limBypass], 0)
    }

    func testSatTypeGoesThroughDry() {
        var a = Project()
        var b = Project()
        a.master["sat.type"] = 0
        b.master["sat.type"] = 2
        let tr = transition(a, b)
        let I = MasterChain.Index.self
        XCTAssertEqual(tr.blend(0.25).master[I.satBypass], 0.5, accuracy: 1e-9)
        XCTAssertEqual(tr.blend(0.25).master[I.satType], 0)
        XCTAssertEqual(tr.blend(0.5).master[I.satBypass], 1, accuracy: 1e-9)
        XCTAssertEqual(tr.blend(0.75).master[I.satType], 2)
        XCTAssertEqual(tr.blend(0.75).master[I.satBypass], 0.5, accuracy: 1e-9)
        XCTAssertEqual(tr.blend(1).master[I.satBypass], 0)
    }

    func testEqBands() {
        var a = Project()
        var b = Project()
        // 0: bell в обоих; 1: low cut только в старом; 2: notch только в новом; 3: bell → high cut.
        a.masterEq.bands[0] = EqBand(type: EqSpec.bell, freq: 100, gain: 6, q: 1)
        b.masterEq.bands[0] = EqBand(type: EqSpec.bell, freq: 400, gain: -6, q: 4)
        a.masterEq.bands[1] = EqBand(type: EqSpec.lowCut, freq: 200, gain: 0, q: 0.7)
        b.masterEq.bands[2] = EqBand(type: EqSpec.notch, freq: 5000, gain: 0, q: 8)
        a.masterEq.bands[3] = EqBand(type: EqSpec.bell, freq: 1000, gain: 4, q: 1)
        b.masterEq.bands[3] = EqBand(type: EqSpec.highCut, freq: 8000, gain: 0, q: 0.7)
        let tr = transition(a, b)
        let half = tr.blend(0.5).globals.masterEq
        XCTAssertEqual(half.bands[0]!.freq, 200, accuracy: 1e-9)
        XCTAssertEqual(half.bands[0]!.gain, 0, accuracy: 1e-9)
        XCTAssertEqual(half.bands[0]!.q, 2, accuracy: 1e-9)
        XCTAssertEqual(half.bands[1]!.freq, (200.0 * 20).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(tr.blend(1).globals.masterEq.bands[1] ?? nil, nil)
        XCTAssertEqual(tr.blend(0.999).globals.masterEq.bands[1]!.freq, 20, accuracy: 0.1)
        XCTAssertEqual(tr.blend(0).globals.masterEq.bands[2] ?? nil, nil)
        XCTAssertEqual(tr.blend(0.001).globals.masterEq.bands[2]!.freq, 20000, accuracy: 50)
        // Разные полосы на одном месте: к середине старая не слышна, после — новая с края.
        XCTAssertEqual(tr.blend(0.49).globals.masterEq.bands[3]!.type, EqSpec.bell)
        XCTAssertEqual(tr.blend(0.5).globals.masterEq.bands[3]!.type, EqSpec.highCut)
        XCTAssertEqual(tr.blend(0.5).globals.masterEq.bands[3]!.freq, 20000, accuracy: 1e-6)
        XCTAssertEqual(tr.blend(0.4999).globals.masterEq.bands[3]!.gain, 0, accuracy: 1e-3)
    }

    /// Мастер с долей BYPASS: 0 и 1 — как кнопка, середина — между.
    func testLimiterPartialBypass() {
        let n = 4800
        func run(_ byp: Double) -> Float {
            let c = MasterChain(sampleRate: 48000)
            var l = [Float](repeating: 0, count: n)
            var r = [Float](repeating: 0, count: n)
            for i in 0..<n { l[i] = Float(sin(Double(i) * 0.05)) * 0.1; r[i] = l[i] }
            var p = MasterChain.defaults
            p[MasterChain.Index.limGain] = 12
            p[MasterChain.Index.limBypass] = byp
            p[MasterChain.Index.satBypass] = 1
            p[MasterChain.Index.cmpBypass] = 1
            p[MasterChain.Index.clipBypass] = 1
            p.withUnsafeBufferPointer { pp in
                var k = 0
                while k < n {
                    let m = min(256, n - k)
                    l.withUnsafeMutableBufferPointer { lb in
                        r.withUnsafeMutableBufferPointer { rb in
                            c.process(left: lb.baseAddress! + k, right: rb.baseAddress! + k, frames: m, params: pp.baseAddress!)
                        }
                    }
                    k += m
                }
            }
            let tail = l[(n - 1000)..<n]
            return (tail.map { $0 * $0 }.reduce(0, +) / Float(tail.count)).squareRoot()
        }
        let wet = run(0)
        let dry = run(1)
        let half = run(0.5)
        // RMS: сухой синус 0,1 — 0,0707; через лимитер с INPUT +12 dB (без ограничения) — вчетверо громче.
        XCTAssertEqual(dry, 0.1 / Float(2).squareRoot(), accuracy: 0.002)
        XCTAssertEqual(wet, 4 * dry, accuracy: 0.02)
        XCTAssertEqual(half, (wet + dry) / 2, accuracy: 0.02)
    }
}
