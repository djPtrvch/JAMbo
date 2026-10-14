import XCTest
@testable import Core

final class ToneTests: XCTestCase {
    private func render(_ core: AudioCore, frames: Int, block: Int = 256) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: block)
        var pos = 0
        while pos < frames {
            let n = min(block, frames - pos)
            out.withUnsafeMutableBufferPointer { o in
                r.withUnsafeMutableBufferPointer { rr in
                    core.render(frames: n, left: o.baseAddress! + pos, right: rr.baseAddress!)
                }
            }
            pos += n
        }
        return out
    }

    func testSilentUntilOn() {
        let core = AudioCore()
        let x = render(core, frames: 4800)
        XCTAssertEqual(x.map(abs).max(), 0)
        XCTAssertEqual(core.framesRendered, 4800)
    }

    /// 440 Гц, −12 dBFS (RMS синуса = пик/√2), без щелчка на включении и выключении.
    func testToneLevelFrequencyAndRamp() {
        let core = AudioCore()
        core.events.push(.tone(on: true))
        let x = render(core, frames: 48000)
        let tail = Array(x[24000..<48000])
        let rms = sqrt(tail.reduce(0) { $0 + $1 * $1 } / Float(tail.count))
        let db = 20 * log10(rms * sqrt(2))
        XCTAssertEqual(db, -12, accuracy: 0.01)
        var crossings = 0
        for i in 1..<tail.count where tail[i - 1] < 0 && tail[i] >= 0 { crossings += 1 }
        XCTAssertEqual(crossings, 220, accuracy: 1) // 0,5 с × 440 Гц
        // Огибающая 5 мс: скачок между отсчётами не больше, чем у самого синуса (2π·440/48000·пик ≈ 0,0145).
        let maxStep = zip(x.dropFirst(), x).map { abs($0 - $1) }.max()!
        XCTAssertLessThan(maxStep, 0.0150)
        core.events.push(.tone(on: false))
        let y = render(core, frames: 9600)
        let maxStepOff = zip(y.dropFirst(), y).map { abs($0 - $1) }.max()!
        XCTAssertLessThan(maxStepOff, 0.0150)
        XCTAssertEqual(y.suffix(1000).map(abs).max(), 0, "через 200 мс тишина")
    }

    func testCPUMeterAverage() {
        let m = CPUMeter(sampleRate: 48000, windowSeconds: 0.5)
        // Блок 256 кадров = 5,333 мс; считаем 1,0666 мс → 20 %.
        for _ in 0..<100 { m.measure(ns: 1_066_666, frames: 256) }
        XCTAssertEqual(m.load, 0.2, accuracy: 0.001)
        XCTAssertEqual(m.peak, 0.2, accuracy: 0.001)
    }
}
