import XCTest
@testable import Core

/// Режим CHORD: аккорды по ступеням гаммы, названия, римские ступени, пресеты и случайные прогрессии.
final class ChordTests: XCTestCase {
    /// Phrygian (3), корень E (4).
    private let phr: Int = 3
    private let e: Int = 4

    func testPhrygianTriads() {
        let names: [String] = (0..<7).map { d in
            Chords.name(Scales.chord(scale: phr, root: e, octave: 2, degree: d, kind: 0), kind: 0)
        }
        XCTAssertEqual(names, ["Em", "F", "G", "Am", "B°", "C", "Dm"])
        XCTAssertEqual(Chords.keyLabel(scale: phr, root: e, octave: 2, degree: 0, kind: 0), "Em · i")
        XCTAssertEqual(Chords.keyLabel(scale: phr, root: e, octave: 2, degree: 1, kind: 0), "F · II")
        XCTAssertEqual(Chords.keyLabel(scale: phr, root: e, octave: 2, degree: 4, kind: 0), "B° · v°")
        XCTAssertEqual(Chords.keyLabel(scale: phr, root: e, octave: 2, degree: 7, kind: 0), "Em · i", "через октаву")
    }

    func testAllNotesInScaleForAllKinds() {
        for scale in 0..<Scales.all.count {
            let steps: [Int] = Scales.all[scale].steps
            for root in 0..<12 {
                for kind in 0..<Scales.chordKinds.count {
                    for d in 0..<Scales.keyCount(scale: scale, octaves: 2) {
                        let c: [Int] = Scales.chord(scale: scale, root: root, octave: 2, degree: d, kind: kind)
                        XCTAssertEqual(c.count, Scales.chordDegrees[kind].count)
                        XCTAssertEqual(c, c.sorted(), "вверх от корня")
                        for n in c { XCTAssertTrue(steps.contains(Scales.wrap(n - root, 12))) }
                        XCTAssertFalse(Chords.name(c, kind: kind).isEmpty)
                    }
                }
            }
        }
    }

    func testFormulas() {
        // C Major, ступень C: 7th — Cmaj7, 9th — Cmaj9, sus2, sus4, add9; ступень G — G7, G9; B — Bm7b5.
        func name(_ d: Int, _ k: Int) -> String {
            return Chords.name(Scales.chord(scale: 0, root: 0, octave: 2, degree: d, kind: k), kind: k)
        }
        XCTAssertEqual(name(0, 1), "Cmaj7")
        XCTAssertEqual(name(0, 2), "Cmaj9")
        XCTAssertEqual(name(0, 3), "Csus2")
        XCTAssertEqual(name(0, 4), "Csus4")
        XCTAssertEqual(name(0, 5), "Cadd9")
        XCTAssertEqual(name(1, 5), "Dm(add9)")
        XCTAssertEqual(name(4, 1), "G7")
        XCTAssertEqual(name(4, 2), "G9")
        XCTAssertEqual(name(1, 1), "Dm7")
        XCTAssertEqual(name(6, 1), "Bm7b5")
        XCTAssertEqual(name(3, 4), "F(sus4)", "F B C — не чистая кварта: корень и тип")
        XCTAssertEqual(Scales.chord(scale: 0, root: 0, octave: 2, degree: 4, kind: 2), [43, 47, 50, 53, 57])
    }

    func testTopNoteFoldsDown() {
        // Хроматика от C9 (120): верх 9th выше 127 — на октаву ниже.
        let c: [Int] = Scales.chord(scale: 0, root: 0, octave: 9, degree: 6, kind: 2)
        XCTAssertTrue(c.allSatisfy { $0 <= 127 })
        XCTAssertEqual(c.first, 131 - 12)
    }

    func testProgressionPresets() {
        let p: ChordProgression = Chords.progressions[4]
        XCTAssertEqual(p.degrees, [1, 7, 6, 7])
        XCTAssertEqual(Chords.names(p.degrees, scale: phr, root: e, kind: 0), "Em – Dm – C – Dm", "по гамме: D F A")
        // Пентатоника (5 нот): ступени 6 и 7 — по модулю.
        XCTAssertEqual(Chords.degreeIndex(6, scale: 8), 0)
        XCTAssertEqual(Chords.degreeIndex(7, scale: 8), 1)
        for pr in Chords.progressions { XCTAssertEqual(pr.degrees.count, Chords.slots.count) }
    }

    func testRandomProgression() {
        var g = SeededGenerator(seed: 7)
        var last: [Int]? = nil
        for scale in 0..<Scales.all.count {
            for _ in 0..<200 {
                let r: [Int] = Chords.random(scale: scale, avoid: last, using: &g)
                XCTAssertEqual(r.count, 4)
                XCTAssertEqual(r[0], 1, "тоника первой")
                for i in 1..<4 { XCTAssertNotEqual(r[i], r[i - 1], "без повторов подряд") }
                XCTAssertTrue(r.allSatisfy { $0 >= 1 && $0 <= 7 })
                XCTAssertNotEqual(r, last)
                last = r
            }
        }
    }

    /// Запись прогрессии в страницу: шаги 1, 5, 9, 13 по 4 шага, остальные не тронуты; снимок отдаёт все ноты.
    func testWriteChordsToSteps() {
        var t = Track(index: 0)
        t.pages[0][2].on = true
        t.pages[0][2].notes = [60]
        let cs: [[Int]] = Chords.chords([1, 7, 6, 7], scale: phr, root: e, octave: 2, kind: 0)
        for (i, notes) in cs.enumerated() {
            t.withStep(Chords.slots[i]) { s in
                s.on = true
                s.notes = notes
                s.setAllLen(Chords.slotLen)
            }
        }
        XCTAssertEqual(t.pages[0][0].notes, [40, 43, 47])
        XCTAssertEqual(t.pages[0][4].notes, [50, 53, 57], "Dm: D F A")
        XCTAssertEqual(t.pages[0][12].len, 4)
        XCTAssertEqual(t.pages[0][2].notes, [60], "прочие шаги не тронуты")
        var p = Project()
        p.tracks[0] = t
        let d = SeqSnapshot(p)
        XCTAssertEqual((0..<3).map { Int(d.data.notes[$0]) }, [40, 43, 47])
    }
}

/// Детерминированный генератор для тестов (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
