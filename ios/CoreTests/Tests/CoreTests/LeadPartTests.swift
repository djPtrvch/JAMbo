import XCTest
@testable import Core

/// Случайная мелодия LEAD: гамма, диапазон, сильные доли на звуках аккорда, мотив и конец фразы.
final class LeadPartTests: XCTestCase {
    func testLeadRules() {
        var g = SystemRandomNumberGenerator()
        let scale: Int = 1, root: Int = 2, oct: Int = 4
        let steps: [Int] = Scales.all[scale].steps
        let n: Int = steps.count
        let degrees: [Int] = [1, 6, 3, 7]
        let low: Int = Scales.note(scale: scale, root: root, octave: oct, degree: 0)
        let high: Int = Scales.note(scale: scale, root: root, octave: oct, degree: n + n / 2)
        for st in 0..<DrumRhythm.styles.count {
            for lens in [[16], [16, 16, 16, 16], [16, 16, 9]] {
                for _ in 0..<30 {
                    let pat = MelodyRhythm.lead(style: st, bpm: 124, lens: lens, degrees: degrees, scale: scale, root: root,
                                                octave: oct, using: &g)
                    let total: Int = lens.count * 16
                    var all: [(Int, SliceRhythm.Event)] = []
                    for (p, page) in pat.enumerated() {
                        XCTAssertFalse(page.isEmpty || page.count < 1, "стиль \(st)")
                        for (i, e) in page.enumerated() {
                            XCTAssertTrue(steps.contains(((e.note - root) % 12 + 12) % 12), "в гамме")
                            XCTAssertTrue((low...high).contains(e.note), "диапазон")
                            let next: Int = i + 1 < page.count ? page[i + 1].step : lens[p]
                            XCTAssertTrue(e.len >= 1 && e.step + e.len <= next, "не накладываются")
                            all.append((p * 16 + e.step, e))
                        }
                    }
                    // Techno — гипнотическая ячейка (HypnoticLead): секунда и септима на доле — намеренно.
                    for (abs, e) in all where abs % 4 == 0 && st != 1 {
                        let ci: Int = min(3, abs * 4 / total)
                        let k: Int = Chords.degreeIndex(degrees[ci], scale: scale)
                        let pcs: Set<Int> = Set([0, 2, 4].map { Scales.note(scale: scale, root: root, octave: 0, degree: k + $0) % 12 })
                        XCTAssertTrue(pcs.contains(e.note % 12), "сильная доля — звук аккорда, стиль \(st)")
                    }
                }
            }
        }
    }

    func testMotifRepeats() {
        var g = SystemRandomNumberGenerator()
        var same: Int = 0
        for _ in 0..<20 {
            let pat = MelodyRhythm.lead(style: 4, bpm: 110, lens: [16, 16, 16, 16], degrees: [1, 1, 1, 1], scale: 0,
                                        root: 0, octave: 4, using: &g)
            if pat[0].map({ $0.step }) == pat[2].map({ $0.step }) { same += 1 }
        }
        XCTAssertEqual(same, 20, "A — тот же ритм в тактах 1 и 3")
    }

    func testWriteLead() {
        var g = SystemRandomNumberGenerator()
        var t = Track(index: 0)
        t.writeRandomLead(pages: 0...0, degrees: [1, 4, 5, 1], scale: 0, root: 0, octave: 4, bpm: 120, using: &g)
        XCTAssertTrue(t.pages[0][0].on, "первая доля")
    }
}
