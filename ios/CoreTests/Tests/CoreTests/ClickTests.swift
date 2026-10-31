import XCTest
@testable import Core

/// Громкость метронома (SETTINGS → RECORD → METRONOME): 0 — тишина, 2 — вдвое громче прежнего.
final class ClickTests: XCTestCase {
    private func peak(_ gain: Double) -> Float {
        var c = Click(sampleRate: 48000)
        c.gain = gain
        c.trigger(at: 0, accent: false)
        let n = 4096
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        l.initialize(repeating: 0, count: n)
        r.initialize(repeating: 0, count: n)
        c.render(blockStart: 0, frames: n, left: l, right: r)
        var m: Float = 0
        for i in 0..<n { m = max(m, abs(l[i])) }
        return m
    }

    func testGain() {
        XCTAssertEqual(peak(0), 0)
        let one: Float = peak(1)
        XCTAssertGreaterThan(one, 0.2)
        // Подъём и спад — от −80 dB до пика (не строго пропорционально): вдвое — с точностью 1 %.
        XCTAssertEqual(peak(2), 2 * one, accuracy: 0.01)
        XCTAssertEqual(AppSettings.decode(nil).metronomeVol, 100)
    }
}
