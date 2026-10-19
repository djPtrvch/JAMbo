import XCTest
@testable import Core

/// Эффекты по эталонам fx_* (рендер worklet'ов веба; FxSelfTest).
final class FxTests: XCTestCase {
    private func check(_ proc: String, count: Int) throws {
        let all = try FxSelfTest.loadCases(GoldenPaths.goldenDir)
        let cases = all.cases.filter { $0.proc == proc }
        XCTAssertEqual(cases.count, count)
        for c in cases {
            let r = try FxSelfTest.run(c, all, GoldenPaths.goldenDir)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertTrue(r.ok, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }

    func testDelay() throws { try check("delay", count: 4) }
    func testReverb() throws { try check("reverb", count: 4) }
    func testDrive() throws { try check("drive", count: 7) }
    func testDuck() throws { try check("duck", count: 3) }

    /// SELF-TEST: у каждого случая — код эффекта и имя в строке.
    func testSelfTestNames() throws {
        let all = try FxSelfTest.loadCases(GoldenPaths.goldenDir)
        XCTAssertEqual(all.cases.count, 18)
        for c in all.cases {
            let code = try XCTUnwrap(FxSelfTest.codes[c.proc], c.file)
            XCTAssertNotNil(FxSelfTest.engineNames[code])
            XCTAssertNil(JamboSelfTest.engineNames[code])
            XCTAssertGreaterThanOrEqual(code, SynthEngines.count)
        }
    }

    /// Нагрузка (отладочная сборка тестов, доля одного ядра): 1 с шума через каждый эффект блоками по 256.
    func testLoad() {
        let n = 256, blocks = 48000 / 256
        let iL = UnsafeMutablePointer<Float>.allocate(capacity: n), iR = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let oL = UnsafeMutablePointer<Float>.allocate(capacity: n), oR = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { iL.deallocate(); iR.deallocate(); oL.deallocate(); oR.deallocate() }
        var rnd = FxRandom(3)
        for i in 0..<n {
            iL[i] = Float(rnd.next() - 0.5)
            iR[i] = Float(rnd.next() - 0.5)
        }
        let dly = FxDelay(sampleRate: 48000, seed: 1), rev = FxReverb(sampleRate: 48000, seed: 1)
        let drv = FxDrive(sampleRate: 48000), duck = FxDuck(sampleRate: 48000)
        func time(_ name: String, _ body: (Int) -> Void) {
            let t0 = Date()
            for b in 0..<blocks { body(b) }
            print(String(format: "load %@: %.1f %%", name, Date().timeIntervalSince(t0) * 100))
        }
        time("delay") { _ in dly.process(inL: iL, inR: iR, outL: oL, outR: oR, frames: n, time: 0.25, feedback: 0.5, filter: -0.3, spread: 0.7) }
        time("reverb") { _ in rev.process(inL: iL, inR: iR, outL: oL, outR: oR, frames: n, size: 50, decay: 2, tone: 0, lowcut: 120, predelay: 0) }
        time("drive") { _ in drv.process(inL: iL, inR: iR, outL: oL, outR: oR, frames: n, drive: 50, type: 0, tone: 50, lowcut: 80) }
        time("duck") { b in
            if b % 24 == 0 { duck.trig(frame: Int64(b * n), attack: 5, release: 150, curve: 50) }
            duck.process(blockStart: Int64(b * n), out: oL, frames: n)
        }
    }

    /// FxRandom — тот же mulberry32, что golden.mjs (первые значения seed 1).
    func testRandom() {
        var r = FxRandom(1)
        XCTAssertEqual(r.next(), 0.6270739405881613, accuracy: 1e-15)
    }
}
