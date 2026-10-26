import XCTest
@testable import Core

final class EditTests: XCTestCase {
    func testHistoryUndoRedoAndGesture() {
        var h = History<Int>()
        var v = 1
        h.record(before: v, after: 2); v = 2
        h.record(before: v, after: 2) // без изменений — нет записи
        h.beginGesture(v)
        h.record(before: v, after: 3); v = 3 // внутри жеста — не пишется
        v = 5
        h.endGesture(v) // весь жест — одна запись (2 → 5)
        XCTAssertEqual(h.undo(v), 2); v = 2
        XCTAssertEqual(h.undo(v), 1); v = 1
        XCTAssertNil(h.undo(v))
        XCTAssertEqual(h.redo(v), 2); v = 2
        h.record(before: v, after: 9); v = 9 // новое действие очищает REDO
        XCTAssertFalse(h.canRedo)
    }

    func testHistoryLimit() {
        var h = History<Int>()
        for i in 0..<300 { h.record(before: i, after: i + 1) }
        var v = 300
        var n = 0
        while let p = h.undo(v) { v = p; n += 1 }
        XCTAssertEqual(n, 200)
        XCTAssertEqual(v, 100)
    }

    private func trackWith(pages: Int) -> Track {
        var t = Track(index: 0)
        for _ in 1..<pages { t.addPage() }
        return t
    }

    func testAddPageGrowsFullLengthAndPlayRange() {
        var t = Track(index: 0)
        t.addPage()
        XCTAssertEqual(t.pages.count, 2)
        XCTAssertEqual(t.length, 32, "при полной длине длина растёт")
        XCTAssertEqual(t.playTo, 1, "играли все — играют все")
        // Своя длина у каждой страницы: прежняя общая длина 20 — 16 + 4; новая страница — 16.
        t.length = 20
        XCTAssertEqual(t.pageLens, [16, 4])
        t.setPlayPages(0, 0)
        t.addPage()
        XCTAssertEqual(t.pageLens, [16, 4, 16])
        XCTAssertEqual(t.length, 36)
        XCTAssertEqual(t.playTo, 0)
        for _ in 0..<10 { t.addPage() }
        XCTAssertEqual(t.pages.count, Params.maxPages)
    }

    /// Страница в 12 шагов: «+» — 12 + 16, DUPLICATE — 12 + 12; PASTE и перенос — с длиной; длина шага — своей страницы.
    func testPageLengthsMoveWithPages() {
        var t = Track(index: 0)
        t.setPageLength(lastIndex: 11)
        XCTAssertEqual(t.pageLens, [12])
        var a = t
        a.addPage()
        XCTAssertEqual(a.pageLens, [12, 16])
        XCTAssertEqual(a.playLen(from: 0, to: 1), 28)
        var d = t
        XCTAssertTrue(d.duplicatePages(0))
        XCTAssertEqual(d.pageLens, [12, 12])
        XCTAssertEqual(d.playLen(from: 0, to: 1), 24)
        d.setPageLength(lastIndex: 16 + 6)
        XCTAssertEqual(d.pageLens, [12, 7])
        d.movePage(1, 0)
        XCTAssertEqual(d.pageLens, [7, 12])
        // Меню страницы действует на играющий диапазон: копируется одна страница, когда играет только она.
        d.setPlayPages(1, 1)
        let copy = d.copyPages(1)
        XCTAssertEqual(copy.lens, [12])
        d.setPlayPages(0, 0)
        d.pastePages(0, copy)
        XCTAssertEqual(d.pageLens, [12, 12])
        XCTAssertTrue(d.deletePages(0))
        XCTAssertEqual(d.pageLens, [12])
        // Проход: страница 1 — 12 шагов, страница 2 — 16; шаг 13-й прохода — первый шаг второй страницы.
        XCTAssertEqual(a.openClip.playIndex(12), 16)
        XCTAssertTrue(a.openClip.outside(12))
        XCTAssertFalse(a.openClip.outside(16 + 15))
    }

    /// Прежний проект: только общая длина — страницы до последней по 16, последняя — остаток; сохраняется pageLens.
    func testLegacyLengthDecodes() throws {
        let json = #"{"pages":[[],[],[]],"length":40,"playFrom":0,"playTo":2}"#
        var c = try JSONDecoder().decode(Clip.self, from: Data(json.utf8))
        c.repair()
        XCTAssertEqual(c.pageLens, [16, 16, 8])
        let back = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.pageLens, [16, 16, 8])
        XCTAssertEqual(back.length, 40)
        XCTAssertEqual(Int32(bitPattern: UInt32(15 | 15 << 4 | 7 << 8) | 0xFFFFF000), c.packedLens)
    }

    func testDuplicatePasteDelete() {
        var t = trackWith(pages: 2)
        t.pages[0][3].on = true
        t.setPlayPages(0, 0)
        XCTAssertTrue(t.duplicatePages(0))
        XCTAssertEqual(t.pages.count, 3)
        XCTAssertTrue(t.pages[1][3].on, "копия сразу за страницей")
        let clip = t.copyPages(0)
        t.pastePages(2, clip)
        XCTAssertTrue(t.pages[2][3].on)
        t.setPlayPages(1, 2)
        XCTAssertTrue(t.deletePages(2), "удаляется весь играющий диапазон 1…2")
        XCTAssertEqual(t.pages.count, 1)
        XCTAssertEqual(t.playFrom, 0)
        XCTAssertFalse(t.deletePages(0), "одна страница остаётся")
    }

    func testNudgeAcrossPagesAndOctave() {
        var t = trackWith(pages: 2)
        t.pages[0][15].on = true
        t.pages[0][15].notes = [60]
        t.setPlayPages(0, 1)
        t.nudgePages(0, .right)
        XCTAssertTrue(t.pages[1][0].on, "через границу страниц")
        t.nudgePages(1, .left)
        XCTAssertTrue(t.pages[0][15].on)
        XCTAssertTrue(t.nudgePages(0, .up))
        XCTAssertEqual(t.pages[0][15].notes, [72])
        t.pages[0][15].notes = [120]
        XCTAssertFalse(t.nudgePages(0, .up), "за 127 — без сдвига")
        XCTAssertEqual(t.pages[0][15].notes, [120])
    }

    func testLocksAndToggle() {
        var t = Track(index: 0)
        t.toggleStep(2, notes: [36])
        XCTAssertEqual(t.pages[0][2].notes, [36])
        t.setLock(2, "filter", -40)
        t.setLock(5, "pan", 10) // p-lock на пустом шаге
        XCTAssertTrue(Track.hasManualLocks(t.pages[0][5]))
        XCTAssertEqual(t.value("filter", step: t.pages[0][2]), -40)
        t.clearLock(2, "filter")
        XCTAssertEqual(t.value("filter", step: t.pages[0][2]), 0)
        t.setLock(2, "pan", 5)
        t.clearAllLocks()
        XCTAssertTrue(t.pages[0][2].locks.isEmpty && t.pages[0][5].locks.isEmpty)
        t.setLock(2, "pan", 5)
        t.toggleStep(2, notes: [36])
        XCTAssertEqual(t.pages[0][2], Step(), "снятый триг забывает p-lock")
    }

    func testTailAndParamScales() {
        var t = trackWith(pages: 2)
        t.pages[0][14].on = true
        t.pages[0][14].len = 4
        XCTAssertTrue(t.isTail(16), "хвост через границу страниц")
        XCTAssertFalse(t.isTail(18))
        let decay = Params.byId["decay"]!
        XCTAssertEqual(decay.fromNorm(decay.toNorm(500)), 500, accuracy: 1e-9)
        XCTAssertEqual(decay.fromNorm(0.5), 500, accuracy: 1e-9, "кубическая шкала: середина — 500 ms")
        let ratchet = Params.byId["ratchet"]!
        XCTAssertEqual(ratchet.fromNorm(0.4), 1)
        XCTAssertEqual(ratchet.format(3), "4")
        XCTAssertEqual(Params.byId["filter"]!.format(0), "OFF")
        XCTAssertEqual(Params.byId["pan"]!.format(-10), "L10")
        XCTAssertEqual(Params.trackGrid[0].id, "pitch")
        XCTAssertEqual(Params.trackGrid[1].id, "attack", "сетка — ряд за рядом")
        // S12: 1.4 у сэмпла пустая, 4.4 Velocity (прежний level), Swing не на сетке.
        XCTAssertEqual(Params.trackGrid[12].id, "", "1.4 у сэмпла пока пустая")
        XCTAssertEqual(Params.trackGrid[15].id, "level")
        XCTAssertEqual(Params.trackGrid[15].label, "Velocity")
        XCTAssertEqual(Params.trackGrid[15].format(127), "100%")
        XCTAssertFalse(Params.trackGrid.contains { $0.id == "swing" })
        XCTAssertNil(Params.byId[""])
        XCTAssertEqual(Params.defaults()["swing"], 50)
        XCTAssertNil(Params.defaults()[""])
        XCTAssertFalse(ModTarget.ids.contains("swing"))
    }
}

/// MORPH: изменения ручек и назначений запоминаются при первом изменении и возвращаются целиком.
final class MorphTests: XCTestCase {
    func testMorphRestoresParamsAndAssigns() {
        var t = Track(index: 0)
        t.assigns["pan"] = ModAssign(lfo: 1, amount: 0.5)
        t.morphParam("filter")
        t.params["filter"] = -40
        t.morphParam("filter")
        t.params["filter"] = -80
        t.morphAssign("pan")
        t.assigns["pan"] = ModAssign(lfo: 2, amount: -1)
        t.morphAssign("level")
        t.assigns["level"] = ModAssign(lfo: 4, amount: 0.3)
        XCTAssertTrue(t.morphEdited)
        t.undoMorph()
        XCTAssertEqual(t.params["filter"], 0)
        XCTAssertEqual(t.assigns["pan"], ModAssign(lfo: 1, amount: 0.5))
        XCTAssertNil(t.assigns["level"])
        XCTAssertFalse(t.morphEdited)
        XCTAssertTrue(t.morphOrig.isEmpty)
    }
}
