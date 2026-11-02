import XCTest
@testable import Core

/// KICK: вращение DRIVE во время удара — без треска. Было: DRIVE и компенсация менялись ступенькой раз в кусок
/// (24 отсчёта) — вторая разность на хвосте ~0,006 при быстром вращении (без вращения ~0,0002).
final class KickDriveTests: XCTestCase {
    private func maxJump(sweep: Bool) -> Float {
        var p = Project()
        p.tracks[0].setSynth(16)
        var page = Track.emptyPage()
        for s in stride(from: 0, to: 16, by: 4) {
            page[s].on = true
            page[s].notes = [36]
        }
        p.tracks[0].pages = [page]
        let core = AudioCore()
        core.installSynth()
        core.publish(p, samples: [:])
        core.events.push(.play(true))
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var a: Float = 0, b: Float = 0, m: Float = 0
        var f = 0
        for k in 0..<(2 * 48000 / 256) {
            if sweep && k % 2 == 0 {
                // DRIVE (ручка 3 движка — morph) быстро туда-обратно, как пальцем.
                p.tracks[0].params["morph"] = 50 + 50 * sin(Double(k) * 0.4)
                core.publish(p, samples: [:])
            }
            core.render(frames: 256, left: &bl, right: &br)
            for x in bl {
                // Без первых ~30 мс удара (там скачки — сам удар).
                if f % 24000 > 1500 { m = max(m, abs(x - 2 * a + b)) }
                b = a
                a = x
                f += 1
            }
        }
        return m
    }

    func testDriveSweepIsSmooth() {
        XCTAssertLessThan(maxJump(sweep: true), 0.0015)
    }
}
