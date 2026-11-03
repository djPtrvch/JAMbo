import XCTest
@testable import Core

final class KeyMatchTests: XCTestCase {
    func testDistance() {
        // E Phrygian (3) — это C мажор.
        XCTAssertEqual(KeyMatch.majors(scale: 3, root: 4), [0])
        // A Min = C Maj: 0; G Maj — сосед: 1; D Min (F Maj) — сосед: 1.
        XCTAssertEqual(KeyMatch.distance(scale: 1, root: 9, scale: 0, root: 0), 0)
        XCTAssertEqual(KeyMatch.distance(scale: 0, root: 0, scale: 0, root: 7), 1)
        XCTAssertEqual(KeyMatch.distance(scale: 3, root: 4, scale: 1, root: 2), 1)
        // E Phr (C) и C Min (Eb): 3 шага; C Phr (Ab) и C: 4; F# Maj и C: 6.
        XCTAssertEqual(KeyMatch.distance(scale: 3, root: 4, scale: 1, root: 0), 3)
        XCTAssertEqual(KeyMatch.distance(scale: 3, root: 0, scale: 0, root: 0), 4)
        XCTAssertEqual(KeyMatch.distance(scale: 0, root: 6, scale: 0, root: 0), 6)
        XCTAssertNil(KeyMatch.distance(scale: 10, root: 0, scale: 0, root: 0), "Chromatic — без тональности")
        XCTAssertEqual(KeyMatch.grade(1), 0)
        XCTAssertEqual(KeyMatch.grade(3), 1)
        XCTAssertEqual(KeyMatch.grade(4), 2)
    }
}
