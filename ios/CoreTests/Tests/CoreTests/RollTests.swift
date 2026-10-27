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

/// S8d: правки нот из пианоролла.
final class RollEditsTests: XCTestCase {
    func testAddRemoveMove() {
        var t = Track(index: 0)
        t.pages[0][2].locks["filter"] = 50
        t.pages[0][2].notes = [70]
        t.addRollNote(2, pitch: 48, len: 2, vel: nil)
        XCTAssertTrue(t.pages[0][2].on)
        XCTAssertEqual(t.pages[0][2].notes, [48], "старые ноты снятого шага не возвращаются")
        XCTAssertEqual(t.pages[0][2].len, 2)
        XCTAssertEqual(t.pages[0][2].locks["filter"], 50, "p-lock остаётся")
        t.addRollNote(2, pitch: 52, len: 1, vel: nil)
        t.setRollNoteLen(2, pitch: 52, len: 4)
        XCTAssertEqual(t.pages[0][2].lens, [2, 4])
        t.pages[0][2].setNoteVel(0, 90)
        t.moveRollNote(2, pitch: 48, to: 5, pitch: 55)
        XCTAssertEqual(t.pages[0][2].notes, [52])
        XCTAssertEqual(t.pages[0][5].notes, [55])
        XCTAssertEqual(t.pages[0][5].len, 2, "длина переезжает с нотой")
        XCTAssertEqual(t.pages[0][5].noteVel(0), 90, "velocity — тоже")
        XCTAssertNil(t.pages[0][5].locks["filter"], "p-lock остаётся на шаге 2")
        t.removeRollNote(2, pitch: 52)
        XCTAssertFalse(t.pages[0][2].on)
        XCTAssertEqual(t.pages[0][2].locks["filter"], 50)
    }

    /// Нота одна на шаге — p-lock и свой звук шага едут с ней (через аккорд и шаг со своими p-lock — не трогая их).
    func testMoveCarriesLocks() {
        var t = Track(index: 0)
        t.addRollNote(2, pitch: 48, len: 1, vel: nil)
        t.pages[0][2].locks["filter"] = 50
        t.pages[0][2].sound = "snd"
        t.addRollNote(4, pitch: 60, len: 1, vel: nil)
        t.pages[0][4].locks["reso"] = 10
        t.pages[0][6].locks["pan"] = 20
        var c: StepCarry? = t.rollCarry(2, pitch: 48)
        XCTAssertNotNil(c)
        t.moveRollNote(2, pitch: 48, to: 3, pitch: 48, carry: &c)
        XCTAssertEqual(t.pages[0][3].locks["filter"], 50, "p-lock — на новом шаге")
        XCTAssertEqual(t.pages[0][3].sound, "snd", "свой звук шага — тоже")
        XCTAssertTrue(t.pages[0][2].locks.isEmpty, "старый шаг пустой")
        XCTAssertNil(t.pages[0][2].sound)
        // Через аккорд: у шага 4 свои p-lock, эти — «в руке».
        t.moveRollNote(3, pitch: 48, to: 4, pitch: 48, carry: &c)
        XCTAssertEqual(t.pages[0][4].locks, ["reso": 10])
        XCTAssertTrue(t.pages[0][3].locks.isEmpty)
        // Через пустой шаг со своими p-lock — его p-lock остаются, эти ждут.
        t.moveRollNote(4, pitch: 48, to: 6, pitch: 48, carry: &c)
        XCTAssertEqual(t.pages[0][4].locks, ["reso": 10], "аккорд остался со своими p-lock")
        XCTAssertEqual(t.pages[0][6].locks, ["pan": 20])
        t.moveRollNote(6, pitch: 48, to: 7, pitch: 50, carry: &c)
        XCTAssertEqual(t.pages[0][6].locks, ["pan": 20], "p-lock пустого шага не тронуты")
        XCTAssertEqual(t.pages[0][7].locks["filter"], 50)
        XCTAssertEqual(t.pages[0][7].notes, [50])
        // Нота из аккорда — p-lock остаются у аккорда.
        t.addRollNote(4, pitch: 64, len: 1, vel: nil)
        XCTAssertNil(t.rollCarry(4, pitch: 64))
        var none: StepCarry? = t.rollCarry(4, pitch: 64)
        t.moveRollNote(4, pitch: 64, to: 9, pitch: 64, carry: &none)
        XCTAssertEqual(t.pages[0][4].locks, ["reso": 10])
        XCTAssertTrue(t.pages[0][9].locks.isEmpty)
    }

    func testSnap() {
        XCTAssertEqual(Roll.snap(7, grid: 1), 7)
        XCTAssertEqual(Roll.snap(7, grid: 2), 6)
        XCTAssertEqual(Roll.snap(7, grid: 4), 4)
        XCTAssertEqual(Roll.snapLen(steps: 2.6, grid: 1, pos: 0, cols: 16), 3)
        XCTAssertEqual(Roll.snapLen(steps: 0.2, grid: 2, pos: 0, cols: 16), 2, "не короче клетки")
        XCTAssertEqual(Roll.snapLen(steps: 5.1, grid: 2, pos: 0, cols: 16), 6)
        XCTAssertEqual(Roll.snapLen(steps: 20, grid: 1, pos: 12, cols: 16), 4, "до конца прохода")
    }
}

/// S8e: velocity ноты из пианоролла.
final class RollVelTests: XCTestCase {
    func testSetVelAndLevel() {
        var t = Track(index: 0)
        t.params["level"] = 100
        t.addRollNote(0, pitch: 48, len: 1, vel: nil)
        let n = Roll.notes(t.openClip)[0]
        XCTAssertEqual(t.rollNoteLevel(n), 100, "без своей — Level дорожки")
        t.setLock(0, "level", 80)
        XCTAssertEqual(t.rollNoteLevel(n), 80, "или p-lock Level шага")
        t.setRollNoteVel(0, pitch: 48, vel: 30)
        XCTAssertEqual(t.rollNoteLevel(Roll.notes(t.openClip)[0]), 30)
        XCTAssertEqual(t.pages[0][0].locks["level"], 30, "velocity связана с p-lock Level")
        XCTAssertTrue(Track.hasManualLocks(t.pages[0][0]))
        // Аккорд: правка одной ноты не меняет звук другой; p-lock — по самой сильной.
        t.addRollNote(0, pitch: 52, len: 1, vel: nil)
        t.setLock(0, "level", 70)
        XCTAssertNil(t.pages[0][0].vels, "p-lock Level ручкой — velocity всех нот")
        t.setRollNoteVel(0, pitch: 48, vel: 20)
        XCTAssertEqual(t.pages[0][0].vels, [20, 70])
        XCTAssertEqual(t.pages[0][0].locks["level"], 70)
        t.setRollNoteVel(0, pitch: 52, vel: 90)
        XCTAssertEqual(t.pages[0][0].locks["level"], 90)
    }
}
