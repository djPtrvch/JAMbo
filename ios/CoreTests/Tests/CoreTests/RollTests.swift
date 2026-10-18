import XCTest
@testable import Core

/// S8b: строки и ноты пианоролла.
final class RollTests: XCTestCase {
    func testRowsAreScaleNotes() {
        let r = Roll.rows(scale: 0, root: 0)
        XCTAssertEqual(r.first, 0)
        XCTAssertEqual(r.last, 127)
        XCTAssertEqual(Array(r[0..<8]), [0, 2, 4, 5, 7, 9, 11, 12])
        let d = Roll.rows(scale: 0, root: 2)
        XCTAssertTrue(d.contains(54), "F#3 в D мажоре")
        XCTAssertFalse(d.contains(53))
        XCTAssertEqual(Roll.rows(scale: 10, root: 0).count, 128, "хроматика — все ноты")
        XCTAssertTrue(Roll.isSharp(54))
        XCTAssertFalse(Roll.isSharp(48))
        XCTAssertTrue(Roll.isRoot(50, root: 2))
    }

    func testNotesOfSelectedPages() {
        var c = Clip(pages: [Track.emptyPage(), Track.emptyPage(), Track.emptyPage()], length: 48, playFrom: 1, playTo: 2)
        c.pages[0][0].on = true
        c.pages[0][0].notes = [60]
        c.pages[1][3].on = true
        c.pages[1][3].addNote(48, len: 2, vel: 100)
        c.pages[1][3].addNote(52, len: 1, vel: nil)
        c.pages[2][0].on = true
        c.pages[2][0].notes = [55]
        let p = Roll.positions(c)
        XCTAssertEqual(p.count, 32)
        XCTAssertEqual(p[0], 16)
        let n = Roll.notes(c)
        XCTAssertEqual(n.count, 3, "страница 0 не выбрана")
        XCTAssertEqual(n[0], RollNote(pos: 3, index: 19, k: 0, pitch: 48, len: 2, vel: 100))
        XCTAssertEqual(n[1].vel, nil)
        XCTAssertEqual(n[2].pos, 16)
        XCTAssertEqual(Roll.beatLabel(0), "1.1")
        XCTAssertEqual(Roll.beatLabel(20), "2.2")
    }
}
