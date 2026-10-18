import XCTest
@testable import Core

/// Эффекты по эталонам fx_* (рендер worklet'ов веба; FxSelfTest).
final class FxTests: XCTestCase {
    private func check(_ proc: String, count: Int) throws {
        let all = try FxSelfTest.loadCases(PlaitsGolden.goldenDir)
        let cases = all.cases.filter { $0.proc == proc }
        XCTAssertEqual(cases.count, count)
        for c in cases {
            let r = try FxSelfTest.run(c, all, PlaitsGolden.goldenDir)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertTrue(r.ok, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }

    func testDelay() throws { try check("delay", count: 4) }
    func testReverb() throws { try check("reverb", count: 4) }
    func testDrive() throws { try check("drive", count: 7) }

    /// FxRandom — тот же mulberry32, что golden.mjs (первые значения seed 1).
    func testRandom() {
        var r = FxRandom(1)
        XCTAssertEqual(r.next(), 0.6270739405881613, accuracy: 1e-15)
    }
}
