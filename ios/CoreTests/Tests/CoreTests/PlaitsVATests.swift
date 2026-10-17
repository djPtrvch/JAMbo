import XCTest
@testable import Core

/// Движок 0 (VA) по эталонам e0_*: усиления OUT и AUX — 0,8, как у VA в jambo_voices.cc.
final class PlaitsVATests: XCTestCase {
    func testVirtualAnalogMatchesGolden() throws {
        let resources = try XCTUnwrap(PlaitsGolden.resources, "нет таблиц Resources/plaits")
        let all = try PlaitsGolden.loadCases()
        let cases = all.cases.filter { $0.engine == 0 }
        XCTAssertEqual(cases.count, 6)
        for c in cases {
            // Свежий движок на каждый случай, как свежий экземпляр wasm в эталоне.
            let engine = VirtualAnalogEngine(resources: resources)
            let actual = PlaitsGolden.render(engine, c, frames: all.frames, block: all.block, accent: all.accent,
                                             outGain: 0.8, auxGain: 0.8)
            let golden = try PlaitsGolden.loadGolden(c.file)
            XCTAssertEqual(golden.count, all.frames, c.file)
            XCTAssertFalse(actual.contains { !$0.isFinite }, c.file)
            let r = PlaitsGolden.compare(actual, golden)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertGreaterThan(r.rmsDb, -40, "\(c.file): почти тишина")
            XCTAssertTrue(r.passes, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }
}
