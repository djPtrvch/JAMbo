import XCTest
@testable import Core

/// Аккордовые партии KEYS и PAD, прогрессии по стилям.
final class ChordPartsTests: XCTestCase {
    private let chords: [[Int]] = [[60, 64, 67], [57, 60, 64], [62, 65, 69], [59, 62, 67]]

    func testProgressionPools() {
        var g = SystemRandomNumberGenerator()
        XCTAssertEqual(MelodyRhythm.progressions.count, DrumRhythm.Groove.allCases.count)
        var last: [Int]? = nil
        var same: Int = 0
        for st in 0..<DrumRhythm.styles.count {
            for _ in 0..<100 {
                let p = MelodyRhythm.progression(style: st, bpm: 124, scale: 1, avoid: last, using: &g)
                XCTAssertEqual(p.count, 4)
                XCTAssertTrue(p.allSatisfy { (1...7).contains($0) })
                if p == last { same += 1 }
                last = p
            }
        }
        XCTAssertLessThan(same, 3, "не повторяет прошлую")
    }

    func testKeysAndPad() {
        var g = SystemRandomNumberGenerator()
        for st in 0..<DrumRhythm.styles.count {
            for bpm in [90.0, 125.0, 172.0] {
                for lens in [[16], [16, 16, 16, 16], [16, 7]] {
                    for role in [MelodyRhythm.Role.keys, .pad] {
                        let pat = MelodyRhythm.chordPart(role, style: st, bpm: bpm, lens: lens, chords: chords, using: &g)
                        XCTAssertEqual(pat.count, lens.count)
                        XCTAssertFalse(pat[0].isEmpty, "стиль \(st) \(role)")
                        let total: Int = lens.count * 16
                        for (p, page) in pat.enumerated() {
                            for e in page {
                                XCTAssertTrue(e.step >= 0 && e.step + e.len <= lens[p], "в пределах страницы")
                                let abs: Int = p * 16 + e.step
                                let ci: Int = min(3, abs / (total / 4))
                                XCTAssertTrue(chords[ci].contains(e.note), "звук своего аккорда")
                            }
                        }
                        if role == .pad && lens == [16, 16, 16, 16] {
                            for (p, page) in pat.enumerated() {
                                XCTAssertEqual(page.map { $0.step }, [0, 0, 0], "аккорд на страницу")
                                XCTAssertTrue(page.allSatisfy { $0.len == 16 })
                                XCTAssertEqual(Set(page.map { $0.note }), Set(chords[p]))
                            }
                        }
                    }
                }
            }
        }
    }

    func testHouseStabsOffbeat() {
        var g = SystemRandomNumberGenerator()
        var off: Int = 0
        for _ in 0..<40 {
            let page = MelodyRhythm.chordPart(.keys, style: 0, bpm: 124, lens: [16, 16, 16, 16], chords: chords, using: &g)[0]
            if page.contains(where: { $0.step == 2 }) { off += 1 }
        }
        XCTAssertGreaterThan(off, 10, "House — стабы на офбитах")
    }

    func testWriteChords() {
        var g = SystemRandomNumberGenerator()
        var t = Track(index: 0)
        t.writeRandomChords(.pad, pages: 0...0, chords: chords, bpm: 120, using: &g)
        XCTAssertEqual(t.pages[0][0].notes.sorted(), [60, 64, 67])
        XCTAssertTrue(t.pages[0][4].on)
    }
}
