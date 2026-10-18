import XCTest
@testable import Core

/// Уровни для измерителя и метров MIX (S5c): пики дорожек и мастера, LUFS (K-взвешивание и пороги BS.1770).
final class LevelsTests: XCTestCase {
    private func render(_ core: AudioCore, frames: Int) {
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            pos += n
        }
    }

    /// Наибольший пик канала ch за последние блоки.
    private func peak(_ core: AudioCore, _ ch: Int) -> (Float, Float) {
        var l: Float = 0, r: Float = 0
        _ = core.levels.read(since: 0) { b in
            l = max(l, Levels.value(b, ch, 0))
            r = max(r, Levels.value(b, ch, 1))
        }
        return (l, r)
    }

    /// Пик дорожки — после громкости микшера, до mute: заглушённая дорожка видна на метре, но не звучит.
    func testTrackPeakBeforeMute() {
        for mute in [false, true] {
            let core = AudioCore(master: false)
            var p = Project()
            p.tracks[0].addSamples(["dc"])
            p.tracks[0].vol = -6
            p.tracks[0].mute = mute
            core.publish(p, samples: ["dc": SampleData(left: [Float](repeating: 0.5, count: 96000), right: nil)])
            core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
            render(core, frames: 9600)
            let (l, r) = peak(core, 0)
            // Моно-сэмпл по центру панорамы: cos(π/4) · 0,5 · −6 dB (Level 100 — (100/127)^1,5).
            XCTAssertGreaterThan(l, 0.1)
            XCTAssertEqual(l, r, accuracy: 1e-4)
            XCTAssertEqual(peak(core, 1).0, 0, "молчащая дорожка")
        }
    }

    /// Мастер: пик выхода после цепочки.
    func testMasterPeak() {
        let core = AudioCore()
        var p = Project()
        p.tracks[0].addSamples(["dc"])
        p.tracks[0].vol = 0
        var rnd = FxRandom(7)
        let noise = (0..<96000).map { _ in Float(rnd.next() * 2 - 1) * 0.3 }
        core.publish(p, samples: ["dc": SampleData(left: noise, right: nil)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        render(core, frames: 24000)
        let (l, r) = peak(core, Levels.master)
        XCTAssertGreaterThan(l, 0.05)
        XCTAssertGreaterThan(r, 0.05)
        XCTAssertLessThan(l, 1.01, "после лимитера")
    }

    /// АЧХ K-взвешивания на частоте hz (два биквада Loudness), разы.
    private func kGain(_ m: Loudness, _ hz: Double) -> Double {
        let w: Double = 2 * Double.pi * hz / 48000
        var g: Double = 1
        for s in 0..<2 {
            let c = m.c + 5 * s
            let re1: Double = c[0] + c[1] * cos(w) + c[2] * cos(2 * w)
            let im1: Double = -c[1] * sin(w) - c[2] * sin(2 * w)
            let re2: Double = 1 + c[3] * cos(w) + c[4] * cos(2 * w)
            let im2: Double = -c[3] * sin(w) - c[4] * sin(2 * w)
            g *= sqrt((re1 * re1 + im1 * im1) / (re2 * re2 + im2 * im2))
        }
        return g
    }

    private func feed(_ m: Loudness, seconds: Double, amp: Float, hz: Double, phase: inout Double) {
        let n = 256
        var l = [Float](repeating: 0, count: n)
        let r = [Float](repeating: 0, count: n)
        for _ in 0..<Int(seconds * 48000 / Double(n)) {
            for i in 0..<n {
                l[i] = amp * Float(sin(phase))
                phase += 2 * Double.pi * hz / 48000
            }
            _ = m.listens(0)
            m.process(l, r, n)
            m.end(n)
        }
    }

    /// Синус 997 Гц на одном канале: моментальная и интегральная — по АЧХ фильтров (≈ −3 LUFS при 0 dBFS, как
    /// у BS.1770); тишина не тянет интегральную вниз (порог −70), тихий отрезок ниже −10 LU отсекается; сброс.
    func testLoudness() {
        let m = Loudness(sampleRate: 48000)
        m.source.store(0)
        var ph: Double = 0
        let k: Double = kGain(m, 997)
        let full: Double = -0.691 + 10 * log10(0.5 * k * k)
        // Блоки на нарастании и спаде окна (частично тишина, выше порогов) немного тянут интегральную вниз — как в вебе.
        feed(m, seconds: 10, amp: 1, hz: 997, phase: &ph)
        XCTAssertEqual(Double(m.momentary.load()), full, accuracy: 0.05)
        XCTAssertEqual(Double(m.integrated.load()), full, accuracy: 0.1)
        XCTAssertEqual(full, -3.0, accuracy: 0.3, "как BS.1770")
        let before = Double(m.integrated.load())
        feed(m, seconds: 10, amp: 0, hz: 997, phase: &ph)
        XCTAssertEqual(m.momentary.load(), -Float.infinity)
        XCTAssertEqual(Double(m.integrated.load()), before, accuracy: 0.15, "тишина ниже −70 LUFS не считается")
        let mid = Double(m.integrated.load())
        feed(m, seconds: 10, amp: 0.01, hz: 997, phase: &ph)
        XCTAssertEqual(Double(m.integrated.load()), mid, accuracy: 0.01, "−40 dB — ниже относительного порога")
        m.resetRequests.store(1)
        feed(m, seconds: 10, amp: 0.1, hz: 997, phase: &ph)
        XCTAssertEqual(Double(m.integrated.load()), full - 20, accuracy: 0.1, "после сброса — заново")
        m.source.store(1)
        _ = m.listens(0)
        XCTAssertEqual(m.integrated.load(), -Float.infinity, "смена канала — сброс")
    }
}
