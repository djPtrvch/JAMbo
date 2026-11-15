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
        XCTAssertEqual(M.role(sample: "k1", name: "Deep 808 C.wav", octave: 4, chord: false, arp: false), .bass)
        XCTAssertEqual(M.role(sample: "k2", name: "Warm Pad.wav", octave: 4, chord: false, arp: false), .pad)
        XCTAssertEqual(M.role(sample: "k2", name: "Warm Pad.wav", octave: 4, chord: true, arp: false), .pad, "пэд с CHORD — PAD")
        XCTAssertEqual(M.role(sample: "mi:25", octave: 3, chord: true, arp: false), .pad, "TEXTURE с CHORD — PAD")
        XCTAssertEqual(M.role(sample: "k2", name: "Bass Pad.wav", octave: 4, chord: false, arp: false), .bass)
        XCTAssertEqual(M.role(sample: "k3", name: "Piano Chord.wav", octave: 4, chord: false, arp: false), .lead,
                       "аккорды — только с CHORD")
        XCTAssertEqual(M.role(sample: "k3", name: "Piano Chord.wav", octave: 2, chord: false, arp: false), .lead)
        XCTAssertEqual(M.role(sample: "k3", name: "Piano Chord.wav", octave: 4, chord: true, arp: false), .keys)
        XCTAssertEqual(M.role(sample: "k4", name: "Vox.wav", octave: 4, chord: false, arp: false), .lead)
    }
}
