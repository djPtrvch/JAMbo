import XCTest
@testable import Core

/// REC в редакторе сэмпла (S11e): запись дорожки и мастера из колбэка, пики формы волны, запись на дорожку.
final class CaptureTests: XCTestCase {
    private func render(_ core: AudioCore, _ col: StemCollector, frames: Int, out: inout [Float],
                        done: inout [Int: SampleData], between: (Int) -> Void = { _ in }) {
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < frames {
            between(pos)
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            out.append(contentsOf: bl[0..<n])
            for s in col.poll(core.sequencer.stemRing) { done[s.channel] = s.data }
            pos += n
        }
    }

    private func core(master: Bool) -> AudioCore {
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [48]
        p.tracks[0].pages[0][0].len = 16
        let c = AudioCore(master: master)
        c.publish(p, samples: ["k": SampleData(left: [Float](repeating: 0.5, count: 48000 * 4), right: nil)])
        c.sequencer.stemRing.prepare()
        c.events.push(.play(true))
        return c
    }

    /// Дорожка: от события старта до стопа, по блокам; звук — выход дорожки, как стем.
    func testTrackCaptureFromStartToStop() {
        let c = core(master: false)
        let col = StemCollector()
        var out: [Float] = []
        var done: [Int: SampleData] = [:]
        render(c, col, frames: 48000, out: &out, done: &done) { pos in
            if pos == 2560 { c.events.push(.captureStart(source: 0)) }
            if pos == 2560 + 25600 { c.events.push(.captureStop) }
        }
        guard let d = done[StemRing.capture] else { return XCTFail("нет записи") }
        XCTAssertEqual(d.frames, 25600)
        XCTAssertNil(done[0], "стем дорожки не пишется")
        for i in stride(from: 0, to: 25600, by: 997) {
            XCTAssertEqual(d.left[i], out[2560 + i], accuracy: 1e-6)
        }
        XCTAssertGreaterThan(abs(d.left[12800]), 0.1)
    }

    /// Мастер: конечный выход мастера.
    func testMasterCaptureIsOutput() {
        let c = core(master: true)
        let col = StemCollector()
        var out: [Float] = []
        var done: [Int: SampleData] = [:]
        render(c, col, frames: 24000, out: &out, done: &done) { pos in
            if pos == 0 { c.events.push(.captureStart(source: StemRing.master)) }
            if pos == 12800 { c.events.push(.captureStop) }
        }
        guard let d = done[StemRing.capture] else { return XCTFail("нет записи") }
        XCTAssertEqual(d.frames, 12800)
        for i in stride(from: 0, to: 12800, by: 501) {
            XCTAssertEqual(d.left[i], out[i], accuracy: 1e-6)
        }
    }

    /// Предел длины: запись кончается сама на limit кадрах.
    func testRingLimitEndsCapture() {
        let ring = StemRing()
        ring.prepare()
        ring.begin(StemRing.capture, at: 100, limit: 300)
        let l = [Float](repeating: 1, count: 256)
        var t: Int64 = 0
        while t < 1024 {
            l.withUnsafeBufferPointer { lp in
                ring.capture(StemRing.capture, lp.baseAddress!, lp.baseAddress!, nil, blockStart: t, frames: 256)
            }
            t += 256
        }
        let done = StemCollector().poll(ring)
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done.first?.data.frames, 300)
        XCTAssertFalse(ring.isActive(StemRing.capture))
    }

    func testPeaksByBlocks() {
        var p = RecPeaks()
        var l = [Float](repeating: 0, count: 300)
        let r = [Float](repeating: 0, count: 300)
        l[5] = 0.5
        l[130] = -0.25
        p.update(left: l, right: r)
        XCTAssertEqual(p.count, 2, "неполный блок ждёт")
        XCTAssertEqual(p.frames, 256)
        XCTAssertEqual(p.hi[0][0], 0.5)
        XCTAssertEqual(p.lo[0][1], -0.25)
        l += [Float](repeating: 0.1, count: 84)
        p.update(left: l, right: r + [Float](repeating: 0, count: 84))
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.range(0, 0, 3).lo, -0.25)
        XCTAssertEqual(p.range(0, 0, 3).hi, 0.5)
        XCTAssertEqual(p.span, Capture.minSpan)
        XCTAssertEqual(Capture.minSpan * Capture.peakBlock, 5 * 48000)
        XCTAssertEqual(Capture.maxFrames, Int64(Capture.maxSeconds * 48000))
    }

    func testTime() {
        XCTAssertEqual(Capture.time(0), "0:00")
        XCTAssertEqual(Capture.time(12.9), "0:12")
        XCTAssertEqual(Capture.time(60), "1:00")
    }

    /// Запись на дорожку: на место сэмпла (и в папке) или в папку.
    func testRecordedSampleOnTrack() {
        var t = Project().tracks[0]
        t.addSamples(["a", "b"])
        t.applyItem(t.folder.items[1])
        t.folder.index = 1
        t.addRecordedSample("r1")
        XCTAssertEqual(t.sample, "r1")
        XCTAssertEqual(t.folder.sampleKeys, ["a", "r1"])
        XCTAssertEqual(t.folder.index, 1)
        t.addRecordedSample("r2")
        XCTAssertEqual(t.folder.sampleKeys, ["a", "r2"], "повторная запись перезаписывает прежнюю")
        var s = Project().tracks[0]
        s.sample = SynthKey.key(0)
        s.addRecordedSample("r")
        XCTAssertEqual(s.sample, "r")
        XCTAssertEqual(s.folder.sampleKeys, ["r"])
        var e = Project().tracks[0]
        e.addRecordedSample("r")
        XCTAssertEqual(e.sample, "r")
        XCTAssertEqual(e.folder.index, 0)
    }
}
