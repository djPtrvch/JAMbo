import XCTest
@testable import Core

/// Pitch по нотам (14.11): основа на ноте темперации, нота шага сдвигает на полутоны, подписи — имена нот.
final class PitchKeyTests: XCTestCase {
    func testDrumNotes() {
        // KICK 50 % ≈ 54,8 Гц — ближайшая нота A1 (55 Гц, MIDI 33).
        XCTAssertEqual(PitchKey.base(Jambo.drum, 0.5), 33)
        let up: Double = PitchKey.knob(Jambo.drum, 0.5, note: PitchKey.root + 12)
        let f: Double = Jambo.drumPitchMin * pow(Jambo.drumPitchMax / Jambo.drumPitchMin, up)
        XCTAssertEqual(f, 110, accuracy: 1e-6, "нота на октаву выше C3 — A2")
        let same: Double = PitchKey.knob(Jambo.drum, 0.5, note: PitchKey.root)
        XCTAssertEqual(Jambo.drumPitchMin * pow(Jambo.drumPitchMax / Jambo.drumPitchMin, same), 55, accuracy: 1e-6)
        // HAT: полутоны от C3, центр — C3.
        XCTAssertEqual(PitchKey.base(Jambo.hat, 0.5), PitchKey.root)
        XCTAssertEqual(PitchKey.knob(Jambo.hat, 0.5, note: PitchKey.root + 6), 0.75, accuracy: 1e-9, "TUNE ±1 октава: полоктавы — четверть хода")
        XCTAssertFalse(PitchKey.drum(Jambo.clap))
    }

    func testLabels() {
        XCTAssertEqual(PitchKey.drumDefs[Jambo.drum]?.format(50), "A1")
        XCTAssertEqual(PitchKey.sampleDef.format(0), "C3")
        XCTAssertEqual(PitchKey.sampleDef.format(7), "G3")
        XCTAssertEqual(PitchKey.shifted(nil, 2, note: 60), 14)
        XCTAssertEqual(PitchKey.drumDefs[Jambo.drum]?.format(PitchKey.shifted(Jambo.drum, 50, note: 55)), "E2")
        XCTAssertEqual(PitchKey.snapped(Jambo.drum, 50), PitchKey.norm(Jambo.drum, midi: 33) * 100, accuracy: 1e-9)
    }
}
