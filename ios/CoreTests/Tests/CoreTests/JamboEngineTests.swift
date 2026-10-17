import XCTest
@testable import Core

/// Свои движки DRUM, ANALOG, FM по эталонам j<движок>_* (рендер jambo-synth-worklet.js веба; JamboSelfTest).
final class JamboEngineTests: XCTestCase {
    private static let tables = JamboTables()

    private func check(engine index: Int, count: Int) throws {
        let all = try JamboSelfTest.loadCases(PlaitsGolden.goldenDir)
        let cases = all.cases.filter { $0.engine == index }
        XCTAssertEqual(cases.count, count)
        for c in cases {
            let r = try JamboSelfTest.run(c, all, PlaitsGolden.goldenDir, tables: JamboEngineTests.tables)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertTrue(r.ok, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }

    func testDrum() throws { try check(engine: 16, count: 6) }
    func testAnalog() throws { try check(engine: 17, count: 8) }
    func testFM() throws { try check(engine: 18, count: 6) }

    func testFmRatioAndPitch() {
        XCTAssertEqual(Jambo.fmRatio(0), 0.5)
        XCTAssertEqual(Jambo.fmRatio(1), 8)
        XCTAssertEqual(Jambo.fmRatio(0.25), 1)  // 0.5·16^0.25 = 1
        XCTAssertEqual(Jambo.drumPitch(0), 30, accuracy: 1e-9)
        XCTAssertEqual(Jambo.drumPitch(0.5), 54.77, accuracy: 0.01)
    }
}
