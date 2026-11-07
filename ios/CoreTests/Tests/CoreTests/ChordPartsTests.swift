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

/// Аккорды по стилю: разные типы, ноты гаммы, расположение голосов.
final class StyleChordsTests: XCTestCase {
    func testStyleChords() {
        var g = SystemRandomNumberGenerator()
        XCTAssertEqual(MelodyRhythm.kindPools.count, DrumRhythm.Groove.allCases.count)
        XCTAssertEqual(MelodyRhythm.voicingPools.count, DrumRhythm.Groove.allCases.count)
        let scale: Int = 1, root: Int = 5, oct: Int = 3
        let steps: [Int] = Scales.all[scale].steps
        for st in 0..<DrumRhythm.styles.count {
            var sizes = Set<Int>()
            var shapes = Set<[Int]>()
            for _ in 0..<60 {
                let cs = MelodyRhythm.styleChords([1, 6, 3, 7], style: st, bpm: 124, scale: scale, root: root, octave: oct,
                                                  using: &g)
                XCTAssertEqual(cs.count, 4)
                for (i, c) in cs.enumerated() {
                    XCTAssertGreaterThanOrEqual(c.count, 3)
                    XCTAssertTrue(c.allSatisfy { steps.contains((($0 - root) % 12 + 12) % 12) }, "в гамме")
                    let base: Int = Scales.baseNote(root: root, octave: oct)
                    XCTAssertTrue(c.allSatisfy { $0 >= base - 12 && $0 < base + 12 }, "около октавы клавиатуры")
                    // Корень ступени — среди звуков.
                    let r: Int = Scales.note(scale: scale, root: root, octave: 0, degree: Chords.degreeIndex([1, 6, 3, 7][i], scale: scale)) % 12
                    XCTAssertTrue(c.contains { $0 % 12 == r })
                    sizes.insert(c.count)
                    shapes.insert(c.map { $0 - c[0] })
                }
            }
            XCTAssertGreaterThan(shapes.count, 3, "разные аккорды, стиль \(st)")
        }
        // Повтор ступени подряд — тот же тип.
        for _ in 0..<30 {
            let cs = MelodyRhythm.styleChords([1, 1, 1, 1], style: 6, bpm: 120, scale: 0, root: 0, octave: 3, using: &g)
            XCTAssertTrue(cs.allSatisfy { $0 == cs[0] })
        }
    }
}
