import XCTest
@testable import Core

/// Движки Plaits по эталонам e<движок>_* (PlaitsSelfTest — тот же код, что SELF-TEST в DIAGNOSTICS).
final class PlaitsEngineTests: XCTestCase {
    /// Все случаи движка; итог — Result.ok (критерий S3a и страховка −40 dB).
    private func checkGolden(engine index: Int) throws {
        let resources = try XCTUnwrap(PlaitsGolden.resources, "нет таблиц Resources/plaits")
        let all = try PlaitsSelfTest.loadCases(PlaitsGolden.goldenDir)
        let cases = all.cases.filter { $0.engine == index }
        // 3 набора × 2 ноты; у 11–15 ещё AUX на наборе 0.
        XCTAssertEqual(cases.count, index >= 11 ? 8 : 6)
        for c in cases {
            let r = try PlaitsSelfTest.run(c, all, resources, PlaitsGolden.goldenDir)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertTrue(r.finite, c.file)
            XCTAssertGreaterThan(r.rmsDb, -60, "\(c.file): почти тишина")
            // Страховка от ошибок с тем же спектром (полярность, сдвиг на отсчёт): по отсчётам не хуже −40 dB.
            XCTAssertLessThanOrEqual(r.sampleErrorDb, -40, c.file)
            XCTAssertTrue(r.passes, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
            XCTAssertTrue(r.ok, c.file)
        }
    }

    func testVirtualAnalog() throws { try checkGolden(engine: 0) }
    func testWaveshaping() throws { try checkGolden(engine: 1) }
    func testFM() throws { try checkGolden(engine: 2) }
    func testGrain() throws { try checkGolden(engine: 3) }
    func testAdditive() throws { try checkGolden(engine: 4) }
    func testWavetable() throws { try checkGolden(engine: 5) }
    func testChords() throws { try checkGolden(engine: 6) }
    func testSpeech() throws { try checkGolden(engine: 7) }
    func testSwarm() throws { try checkGolden(engine: 8) }
    func testNoise() throws { try checkGolden(engine: 9) }
    func testParticle() throws { try checkGolden(engine: 10) }
    func testString() throws { try checkGolden(engine: 11) }
    func testModal() throws { try checkGolden(engine: 12) }
    func testBassDrum() throws { try checkGolden(engine: 13) }
    func testSnareDrum() throws { try checkGolden(engine: 14) }
    func testHiHat() throws { try checkGolden(engine: 15) }

    /// Всего эталонов — 106 (16 движков × 3 набора × 2 ноты + AUX движков 11–15 на наборе 0).
    func testAllCasesListed() throws {
        let all = try PlaitsSelfTest.loadCases(PlaitsGolden.goldenDir)
        XCTAssertEqual(all.cases.count, 106)
        XCTAssertEqual(Set(all.cases.map(\.engine)), Set(0..<16))
        XCTAssertEqual(all.cases.filter(\.isAux).count, 10)
    }

    /// Поиск папок как в приложении: Resources как bundle, файлы — в подпапках plaits и golden.
    func testBundleLookup() throws {
        let bundle = try XCTUnwrap(Bundle(url: PlaitsGolden.resourcesDir))
        let tables = try XCTUnwrap(PlaitsSelfTest.directory(of: "lut_sine.f32", in: bundle,
                                                            subdirectories: ["plaits", "Resources/plaits"]))
        let golden = try XCTUnwrap(PlaitsSelfTest.directory(of: "cases.json", in: bundle,
                                                            subdirectories: ["golden", "Resources/golden"]))
        XCTAssertNotNil(PlaitsSelfTest.webResources(tables))
        XCTAssertEqual(try PlaitsSelfTest.loadCases(golden).cases.count, 106)
    }

    /// В приложении a0 — 48 кГц без сдвига ноты: A4 (нота 69) = 440 Гц с точностью до шага таблицы (1/256 полутона).
    func testAppPitchA4() throws {
        var app = try XCTUnwrap(PlaitsGolden.resources)
        app.a0 = plaitsA0
        let hz = app.noteToFrequency(69) * kSampleRate
        XCTAssertEqual(Double(hz), 440, accuracy: 440 * 0.0003)
    }
}
