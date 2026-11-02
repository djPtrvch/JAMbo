import XCTest
@testable import Core

/// Аккорды больше голосов дорожки (6): смена аккорда крадёт голоса — без щелчка. Было: голос, уже гаснущий по
/// legatoCut (τ по атаке), крался снова и обрезался громким (вторая разность ~0,13).
final class ChordStealTests: XCTestCase {
    private func maxJump(kind: Int) -> Float {
        var p = Project()
        p.tracks[0].setSynth(17)
        p.tracks[0].params["attack"] = 203
        p.tracks[0].params["decay"] = 2030
        p.tracks[0].params["reverb"] = 0
        p.tracks[0].params["filter"] = -30
        var pages: [[Step]] = []
        for d in [1, 7, 6, 7] {
            var page = Track.emptyPage()
            page[0].on = true
            page[0].len = 16
            page[0].notes = Scales.chord(scale: 3, root: 4, octave: 2, degree: d - 1, kind: kind)
            pages.append(page)
        }
        p.tracks[0].pages = pages
        p.tracks[0].playTo = 3
        let core = AudioCore()
        core.installSynth()
        core.publish(p, samples: [:])
        core.events.push(.play(true))
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var a: Float = 0, b: Float = 0, m: Float = 0
        for _ in 0..<(7 * 48000 / 256) {
            core.render(frames: 256, left: &bl, right: &br)
            for x in bl {
                m = max(m, abs(x - 2 * a + b))
                b = a
                a = x
            }
        }
        return m
    }

    func testNoClickOnChordChange() {
        XCTAssertLessThan(maxJump(kind: 1), 0.003, "7th: 4 + 4 ноты")
        XCTAssertLessThan(maxJump(kind: 2), 0.003, "9th: 5 + 5 нот")
    }
}
