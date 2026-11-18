import XCTest
@testable import Core

/// AUTO MAKEUP (18.11): замер громкости входа и выхода компрессора без MAKEUP.
final class MasterAutoMakeupTests: XCTestCase {
    /// Синус 1 кГц −6 dB, порог −20, 4:1: выход тише входа на столько, сколько сжимает; без замера суммы не копятся;
    /// BYPASS — разницы нет.
    func testMeasure() {
        let n = 256 * 188
        let src = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { src.deallocate(); out.deallocate() }
        for i in 0..<n { src[i] = Float(0.5 * sin(2 * Double.pi * 1000 * Double(i) / 48000)) }
        func run(_ g: MasterGlue, bypass: Double) {
            var i = 0
            while i < n {
                g.process(inL: src + i, inR: src + i, outL: out + i, outR: out + i, frames: 256, thr: -20, att: 10,
                          rel: 100, auto: false, makeup: 0, ratio: 4, knee: 0, mix: 100, schpf: 20, bypass: bypass)
                i += 256
            }
        }
        let g = MasterGlue(sampleRate: 48000)
        run(g, bypass: 0)
        XCTAssertEqual(g.kCount, 0)
        g.measuring = true
        g.resetMeasure()
        run(g, bypass: 0)
        // Уровень детектора синуса −6 dB (пик), сверх порога 14 dB, 4:1 — сжатие 10,5 dB.
        XCTAssertEqual(10 * log10(g.kSumIn / g.kSumOut), 10.5, accuracy: 0.7)
        let b = MasterGlue(sampleRate: 48000)
        b.measuring = true
        run(b, bypass: 1)
        XCTAssertEqual(10 * log10(b.kSumIn / b.kSumOut), 0, accuracy: 0.01)
    }
}
