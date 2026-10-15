import XCTest
import Foundation
@testable import Core

/// Движки Plaits против эталонов из plaits.wasm (ios/tools/plaits/golden.mjs): поотсчётная ошибка ≤ −60 dB к сигналу.
final class PlaitsTests: XCTestCase {
    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("JAMbo.swiftpm/Resources")

    static let lut = PlaitsLUT.load(dir: resources.appendingPathComponent("plaits"))!
    static let dir = resources.appendingPathComponent("golden")
    static let set = PlaitsSelfTest.loadSet(dir: dir)!

    func check(_ engine: Int) {
        let cases = Self.set.cases.filter { $0.engine == engine }
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            guard let r = PlaitsSelfTest.check(c, set: Self.set, dir: Self.dir, lut: Self.lut) else {
                XCTFail(c.file); continue
            }
            print("plaits \(c.file): \(String(format: "%.1f", r.sampleDB)) dB, bands \(String(format: "%.2f", r.bandDB)) dB")
            XCTAssertTrue(r.passed, c.file)
        }
    }

    func testVA() { check(0) }
    func testWaveshape() { check(1) }
    func testFM() { check(2) }
    func testGrain() { check(3) }
    func testAdditive() { check(4) }
    func testWavetable() { check(5) }
    func testChords() { check(6) }
    func testSpeech() { check(7) }
}

/// Нагрузка: 6 голосов × 1 с на каждом движке (печать; release-сборка: swift test -c release).
final class PlaitsLoadTests: XCTestCase {
    func testLoad() {
        let lut = PlaitsTests.lut
        for e in 0..<8 {
            let voices = (0..<6).map { _ in PlaitsVoice(lut: lut) }
            for (k, v) in voices.enumerated() {
                v.set(engine: e, note: 48 + Float(k * 3), harmonics: 0.3, timbre: 0.6, morph: 0.4, accent: 0.8, aux: 0)
                v.trigger()
            }
            let t0 = Date()
            for _ in 0..<2000 { for v in voices { v.render(24); v.release() } }
            let dt = Date().timeIntervalSince(t0)
            print("plaits load engine \(e): \(String(format: "%.1f", dt * 100))% of one core for 6 voices")
        }
    }
}
