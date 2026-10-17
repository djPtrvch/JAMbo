import XCTest
@testable import Core

/// Свои движки DRUM, ANALOG, FM по эталонам j<движок>_* (рендер jambo-synth-worklet.js веба; JamboSelfTest).
final class JamboEngineTests: XCTestCase {
    private static let tables = JamboTables()
    private static var wavetables: [String: WtTable] = [:]

    private func check(engine index: Int, count: Int) throws {
        let all = try JamboSelfTest.loadCases(PlaitsGolden.goldenDir)
        let cases = all.cases.filter { $0.engine == index }
        XCTAssertEqual(cases.count, count)
        for c in cases {
            let r = try JamboSelfTest.run(c, all, PlaitsGolden.goldenDir, tables: JamboEngineTests.tables,
                                          wavetables: &JamboEngineTests.wavetables)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertTrue(r.ok, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }

    func testDrum() throws { try check(engine: 16, count: 6) }
    func testAnalog() throws { try check(engine: 17, count: 8) }
    func testFM() throws { try check(engine: 18, count: 6) }
    func testWavetable() throws { try check(engine: 19, count: 8) }

    /// Встроенные таблицы против wavetable.ts веба: уровни 0, 3, 6, 10, кадры 0, 31, 63, каждый 16-й отсчёт.
    func testBuiltinTables() throws {
        struct Level: Decodable { let level: Int; let size: Int; let values: [Float] }
        struct Check: Decodable { let frames: Int; let levels: [Level] }
        let url = PlaitsGolden.goldenDir.appendingPathComponent("jambo_tables.json")
        let checks = try JSONDecoder().decode([String: Check].self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(checks.keys), Set(WavetableKey.builtins))
        for name in WavetableKey.builtins {
            let t = JamboEngineTests.wavetables[name] ?? WtTable.builtin(name)
            JamboEngineTests.wavetables[name] = t
            let c = try XCTUnwrap(checks[name])
            XCTAssertEqual(t.frames, c.frames, name)
            for lv in c.levels {
                XCTAssertEqual(t.sizes[lv.level], lv.size, name)
                var k = 0
                var worst: Float = 0
                for f in [0, 31, 63] {
                    var j = 0
                    while j < lv.size {
                        worst = max(worst, abs(t.data[lv.level][f * lv.size + j] - lv.values[k]))
                        k += 1
                        j += 16
                    }
                }
                XCTAssertLessThan(worst, 1e-5, "\(name) level \(lv.level)")
            }
        }
    }

    func testFmRatioAndPitch() {
        XCTAssertEqual(Jambo.fmRatio(0), 0.5)
        XCTAssertEqual(Jambo.fmRatio(1), 8)
        XCTAssertEqual(Jambo.fmRatio(0.25), 1)  // 0.5·16^0.25 = 1
        XCTAssertEqual(Jambo.drumPitch(0), 30, accuracy: 1e-9)
        XCTAssertEqual(Jambo.drumPitch(0.5), 54.77, accuracy: 0.01)
    }
}
