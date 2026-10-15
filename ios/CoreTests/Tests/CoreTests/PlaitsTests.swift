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
}
