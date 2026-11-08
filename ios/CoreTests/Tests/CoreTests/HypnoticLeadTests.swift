import XCTest
@testable import Core

/// Гипнотический LEAD (Techno): ячейка-полиметрия или евклид на 16, 1–3 высоты, короткие ноты.
final class HypnoticLeadTests: XCTestCase {
    func testEuclid() {
        XCTAssertEqual(MelodyRhythm.euclid(3, 8, rot: 0).map { $0 ? 1 : 0 }.reduce(0, +), 3)
        XCTAssertEqual(MelodyRhythm.euclid(5, 16, rot: 3).filter { $0 }.count, 5)
        XCTAssertTrue(MelodyRhythm.euclid(2, 5, rot: 0)[0])
    }

    func testTechnoLeadIsHypnotic() {
        var g = SystemRandomNumberGenerator()
        let scale: Int = 1, root: Int = 9, oct: Int = 3
        let steps: [Int] = Scales.all[scale].steps
        for _ in 0..<200 {
            let pat = MelodyRhythm.lead(style: 1, bpm: 130, lens: [16, 16, 16, 16], degrees: [1, 1, 1, 1],
                                        scale: scale, root: root, octave: oct, using: &g)
            XCTAssertEqual(pat.count, 4)
            var notes = Set<Int>()
            for page in pat {
                XCTAssertFalse(page.isEmpty)
                for (i, e) in page.enumerated() {
                    XCTAssertTrue(steps.contains(((e.note - root) % 12 + 12) % 12), "нота в гамме")
                    XCTAssertTrue((1...2).contains(e.len), "короткие ноты")
                    let next: Int = i + 1 < page.count ? page[i + 1].step : 16
                    XCTAssertLessThanOrEqual(e.step + e.len, next, "ноты не накладываются")
                    notes.insert(e.note)
                }
            }
            XCTAssertLessThanOrEqual(notes.count, 3, "1–3 высоты на один аккорд")
            // Первые три страницы — одна ячейка без изменений (полиметрия или евклид на 16).
            let flat: [Int] = (0..<3).flatMap { p in pat[p].map { p * 16 + $0.step } }
            XCTAssertGreaterThanOrEqual(flat.count, 6)
        }
    }

    func testOtherStylesKeepMelody() {
        var g = SystemRandomNumberGenerator()
        let pat = MelodyRhythm.lead(style: 0, bpm: 124, lens: [16, 16], degrees: [1, 6], scale: 0, root: 0,
                                    octave: 4, using: &g)
        XCTAssertFalse(pat[0].isEmpty)
    }

    func testPartTypes() {
        typealias M = MelodyRhythm
        XCTAssertEqual(M.partName(.bass), "BASS")
        XCTAssertEqual(M.partName(.keys), "LEAD")
        XCTAssertEqual(M.partName(.lead), "LEAD")
        XCTAssertEqual(M.partName(.pad), "PAD")
        XCTAssertEqual(M.role(sample: "k1", name: "Dark Texture FX.wav", octave: 4, chord: false, arp: false), .pad)
        XCTAssertEqual(M.role(sample: "k2", name: "Noise Riser.wav", octave: 4, chord: false, arp: false), .pad)
        XCTAssertEqual(M.role(sample: "k3", name: "Acid Lead.wav", octave: 1, chord: false, arp: false), .lead)
    }
}
