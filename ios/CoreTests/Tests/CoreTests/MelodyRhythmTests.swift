import XCTest
@testable import Core

/// Случайные мелодические партии: роли дорожек, басовая линия по стилю и прогрессии.
final class MelodyRhythmTests: XCTestCase {
    func testRoles() {
        typealias M = MelodyRhythm
        XCTAssertEqual(M.role(sample: "mi:17", octave: 3, chord: false, arp: true), .arp)
        XCTAssertEqual(M.role(sample: "mi:17", octave: 3, chord: true, arp: false), .keys)
        XCTAssertEqual(M.role(sample: "mi:24", octave: 4, chord: false, arp: false), .bass, "SUB")
        XCTAssertEqual(M.role(sample: "mi:25", octave: 3, chord: false, arp: false), .pad, "TEXTURE")
        XCTAssertEqual(M.role(sample: "mi:26", octave: 3, chord: false, arp: false), .pad, "GRANULAR")
        XCTAssertEqual(M.role(sample: "mi:17", octave: 2, chord: false, arp: false), .bass, "низкая октава")
        XCTAssertEqual(M.role(sample: "mi:17", octave: 3, chord: false, arp: false), .lead)
        XCTAssertEqual(M.role(sample: "Lib/Deep 808 C.wav", octave: 4, chord: false, arp: false), .bass)
        XCTAssertEqual(M.role(sample: "Lib/Warm Pad.wav", octave: 4, chord: false, arp: false), .pad)
        XCTAssertEqual(M.role(sample: "Lib/Piano Chord.wav", octave: 4, chord: false, arp: false), .keys)
        XCTAssertEqual(M.role(sample: "Lib/Vox.wav", octave: 4, chord: false, arp: false), .lead)
    }

    func testBassInScaleAndOnChords() {
        var g = SystemRandomNumberGenerator()
        let scale: Int = 1, root: Int = 9, oct: Int = 1
        let steps: [Int] = Scales.all[scale].steps
        let degrees: [Int] = [1, 6, 3, 7]
        for st in 0..<DrumRhythm.styles.count {
            for bpm in [90.0, 125.0, 172.0] {
                for _ in 0..<40 {
                    let pat = MelodyRhythm.bass(style: st, bpm: bpm, lens: [16, 16, 16, 16], degrees: degrees,
                                                scale: scale, root: root, octave: oct, using: &g)
                    XCTAssertEqual(pat.count, 4)
                    var seen = Set<Int>()
                    for (p, page) in pat.enumerated() {
                        XCTAssertFalse(page.isEmpty, "стиль \(st) страница \(p)")
                        for (i, e) in page.enumerated() {
                            XCTAssertTrue((0..<16).contains(e.step))
                            XCTAssertTrue(steps.contains(((e.note - root) % 12 + 12) % 12), "нота в гамме")
                            XCTAssertGreaterThanOrEqual(e.len, 1)
                            let next: Int = i + 1 < page.count ? page[i + 1].step : 16
                            XCTAssertLessThanOrEqual(e.step + e.len, next, "ноты не накладываются")
                            // Первая нота аккорда (4 страницы — аккорд на страницу) — его корень.
                            if i == 0 && !seen.contains(p) {
                                seen.insert(p)
                                let k: Int = Chords.degreeIndex(degrees[p], scale: scale)
                                XCTAssertEqual(e.note, Scales.note(scale: scale, root: root, octave: oct, degree: k))
                            }
                        }
                    }
                }
            }
        }
    }

    func testBassShortAndSilentPages() {
        var g = SystemRandomNumberGenerator()
        let pat = MelodyRhythm.bass(style: 0, bpm: 124, lens: [0, 7], degrees: [1, 4, 5, 1], scale: 0, root: 0,
                                    octave: 1, using: &g)
        XCTAssertTrue(pat[0].isEmpty)
        XCTAssertFalse(pat[1].isEmpty)
        XCTAssertTrue(pat[1].allSatisfy { $0.step < 7 && $0.step + $0.len <= 7 })
    }

    func testTechnoRollsOffKick() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let page = MelodyRhythm.bass(style: 1, bpm: 130, lens: [16], degrees: [1, 1, 1, 1], scale: 1, root: 0,
                                         octave: 1, using: &g)[0]
            XCTAssertTrue(page.allSatisfy { $0.step % 4 != 0 || page.count == 1 }, "мимо бочки")
        }
    }

    func testWriteRandomBass() {
        var g = SystemRandomNumberGenerator()
        var t = Track(index: 0)
        t.sample = "mi:24"
        t.pages = [Track.emptyPage(), Track.emptyPage()]
        t.toggleStep(20, notes: [60])
        t.writeRandomBass(pages: 0...0, degrees: [1, 5, 6, 4], scale: 0, root: 0, octave: 1, bpm: 124, using: &g)
        XCTAssertTrue(t.pages[0].contains { $0.on })
        XCTAssertTrue(t.pages[1][4].on, "страница вне range не тронута")
    }
}
