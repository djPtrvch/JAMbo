import XCTest
@testable import Core

/// Движки Plaits по эталонам e<движок>_*; усиления OUT и AUX — как в jambo_voices.cc.
final class PlaitsEngineTests: XCTestCase {
    /// Все случаи движка: свежий экземпляр на каждый (как свежий wasm в эталоне); критерий S3a (Result.passes).
    private func checkGolden(engine index: Int, outGain: Float, auxGain: Float,
                             make: (PlaitsResources) -> PlaitsEngine) throws {
        let resources = try XCTUnwrap(PlaitsGolden.resources, "нет таблиц Resources/plaits")
        let all = try PlaitsGolden.loadCases()
        let cases = all.cases.filter { $0.engine == index }
        XCTAssertEqual(cases.count, 6)
        for c in cases {
            let actual = PlaitsGolden.render(make(resources), c, frames: all.frames, block: all.block,
                                             accent: all.accent, outGain: outGain, auxGain: auxGain)
            let golden = try PlaitsGolden.loadGolden(c.file)
            XCTAssertEqual(golden.count, all.frames, c.file)
            XCTAssertFalse(actual.contains { !$0.isFinite }, c.file)
            let r = PlaitsGolden.compare(actual, golden)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertGreaterThan(r.rmsDb, -40, "\(c.file): почти тишина")
            // Страховка от ошибок с тем же спектром (полярность, сдвиг на отсчёт): по отсчётам не хуже −40 dB.
            XCTAssertLessThanOrEqual(r.sampleErrorDb, -40, c.file)
            XCTAssertTrue(r.passes, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }

    func testVirtualAnalog() throws {
        try checkGolden(engine: 0, outGain: 0.8, auxGain: 0.8) { VirtualAnalogEngine(resources: $0) }
    }

    func testWaveshaping() throws {
        try checkGolden(engine: 1, outGain: 0.7, auxGain: 0.6) { WaveshapingEngine(resources: $0) }
    }

    func testFM() throws {
        try checkGolden(engine: 2, outGain: 0.6, auxGain: 0.6) { FMEngine(resources: $0) }
    }

    func testGrain() throws {
        try checkGolden(engine: 3, outGain: 0.7, auxGain: 0.6) { GrainEngine(resources: $0) }
    }

    func testAdditive() throws {
        try checkGolden(engine: 4, outGain: 0.8, auxGain: 0.8) { AdditiveEngine(resources: $0) }
    }

    /// В приложении a0 — 48 кГц без сдвига ноты: A4 (нота 69) = 440 Гц с точностью до шага таблицы (1/256 полутона).
    func testAppPitchA4() throws {
        var app = try XCTUnwrap(PlaitsGolden.resources)
        app.a0 = plaitsA0
        let hz = app.noteToFrequency(69) * kSampleRate
        XCTAssertEqual(Double(hz), 440, accuracy: 440 * 0.0003)
    }
}
