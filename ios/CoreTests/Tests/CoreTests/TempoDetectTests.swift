import XCTest
@testable import Core

/// Темп референса (S15g): синтетические ритмы — бочка, хэт на слабых долях, малый барабан, шум.
final class TempoDetectTests: XCTestCase {
    private var seed: UInt32 = 1

    private func noise() -> Float {
        seed = seed &* 1664525 &+ 1013904223
        return Float(Int32(bitPattern: seed)) / Float(Int32.max)
    }

    /// Ритм bpm длиной sec: бочка (синус со спадом) на каждой доле (или на 1 и 3 такта — breaks), хэт на восьмых
    /// между долями, малый на 2 и 4 (шум), фон — тихий шум.
    private func groove(_ bpm: Double, sec: Double = 60, fourOnFloor: Bool = true) -> SampleData {
        let rate: Double = 48000
        let n: Int = Int(sec * rate)
        var x = [Float](repeating: 0, count: n)
        let beat: Double = 60 / bpm * rate
        var b: Int = 0
        while Double(b) * beat < Double(n) {
            let at: Int = Int(Double(b) * beat)
            let kick: Bool = fourOnFloor || b % 4 == 0 || b % 4 == 2
            if kick {
                var i = 0
                while i < 6000 && at + i < n {
                    let t: Double = Double(i) / rate
                    x[at + i] += Float(sin(2 * .pi * 55 * t) * exp(-t * 18)) * 0.8
                    i += 1
                }
            }
            if b % 2 == 1 {
                var i = 0
                while i < 4000 && at + i < n {
                    x[at + i] += noise() * Float(exp(-Double(i) / 900)) * 0.4
                    i += 1
                }
            }
            let off: Int = at + Int(beat / 2)
            var i = 0
            while i < 1200 && off + i < n {
                x[off + i] += noise() * Float(exp(-Double(i) / 200)) * 0.15
                i += 1
            }
            b += 1
        }
        var k = 0
        while k < n {
            x[k] += noise() * 0.005
            k += 1
        }
        return SampleData(left: x, right: nil)
    }

    func testHouse() {
        XCTAssertEqual(TempoDetect.bpm(groove(126)), 126)
        XCTAssertEqual(TempoDetect.bpm(groove(128)), 128)
    }

    func testRange() {
        XCTAssertEqual(TempoDetect.bpm(groove(90, fourOnFloor: false)), 90)
        XCTAssertEqual(TempoDetect.bpm(groove(100)), 100)
        XCTAssertEqual(TempoDetect.bpm(groove(140)), 140)
        XCTAssertEqual(TempoDetect.bpm(groove(174, fourOnFloor: false)), 174)
        XCTAssertEqual(TempoDetect.bpm(groove(85)), 85, "медленный с хэтами на восьмых — не двойной")
    }

    func testFractional() {
        let v: Double = TempoDetect.bpm(groove(123.5)) ?? 0
        XCTAssertEqual(v, 123.5, accuracy: 0.11)
    }

    func testSilenceAndShort() {
        XCTAssertNil(TempoDetect.bpm(SampleData(left: [Float](repeating: 0, count: 48000 * 20), right: nil)))
        XCTAssertNil(TempoDetect.bpm(groove(120, sec: 3)))
    }
}
