import XCTest
@testable import Core

/// Метки без ноты (флажки снизу редактора): сэмпл не нарезается на ноты, случайная нарезка — по Start и End.
final class SliceCueTests: XCTestCase {
    func testFreeMarksDoNotSliceNotes() throws {
        var t = Track(index: 0)
        t.sample = "loop.caf"
        t.addSlice("loop.caf", at: 0.25, free: true)
        XCTAssertFalse(t.sliced, "только метки без ноты — клавиши транспонируют весь сэмпл")
        XCTAssertTrue(t.hasCuts)
        t.addSlice("loop.caf", at: 0.5)
        t.addSlice("loop.caf", at: 0)
        XCTAssertTrue(t.sliced)
        let m = t.sliceMarks("loop.caf")
        let notes = Slices.notes(m, map: .chromatic, scale: 0, root: 0)
        // Ноты по порядку — только у маркеров с нотой: метка без ноты номера не занимает.
        XCTAssertEqual(notes, [48, Slices.noNote, 49])
        XCTAssertFalse(t.setSliceNote("loop.caf", 1, note: 60, notes: notes))
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.sliceMarks("loop.caf").map { $0.isFree }, [false, true, false])
    }

    func testMoveWithinOwnKind() {
        var t = Track(index: 0)
        t.addSlice("k", at: 0.2)
        t.addSlice("k", at: 0.4, free: true)
        t.addSlice("k", at: 0.6)
        // Маркер с нотой проходит мимо метки без ноты, но не дальше соседа своего вида.
        t.moveSlice("k", 0, at: 0.5, gap: 0.01)
        XCTAssertEqual(t.sliceMarks("k")[0].at, 0.5, accuracy: 1e-9)
        t.moveSlice("k", 0, at: 0.9, gap: 0.01)
        XCTAssertEqual(t.sliceMarks("k")[0].at, 0.59, accuracy: 1e-9)
    }

    func testPiecesAndWrite() {
        var marks: [SliceMark] = [SliceMark(at: 0, free: true), SliceMark(at: 0.5, role: 1, free: true)]
        var notes = Slices.notes(marks, map: .chromatic, scale: 0, root: 0)
        let r = SliceRhythm.pieces(marks, notes: notes) { a, b in (b - a) * 16 }
        XCTAssertEqual(r.pieces.map { $0.note }, [SliceRhythm.cutNote, SliceRhythm.cutNote + 1])
        XCTAssertEqual(r.pieces.map { $0.len }, [8, 8])
        XCTAssertEqual(r.pieces[1].role, .mid)
        XCTAssertEqual(r.cuts[SliceRhythm.cutNote + 1], SliceRhythm.Cut(a: 0.5, b: 1))
        var t = Track(index: 0)
        let pat: [[SliceRhythm.Event]] = [[SliceRhythm.Event(step: 0, note: SliceRhythm.cutNote + 1, len: 4, vel: 127),
                                           SliceRhythm.Event(step: 0, note: SliceRhythm.cutNote, len: 2, vel: 90)]]
        t.writeSlices(pat, pages: 0...0, cuts: r.cuts)
        let s = t.pages[0][0]
        XCTAssertEqual(s.notes, [Params.sampleRoot], "на шаге — один кусок, в исходной высоте")
        XCTAssertEqual(s.locks["start"], 50)
        XCTAssertEqual(s.locks["end"], 100)
        // Есть маркеры с нотой — куски только по ним.
        marks.append(SliceMark(at: 0.25))
        notes = Slices.notes(marks, map: .chromatic, scale: 0, root: 0)
        let n = SliceRhythm.pieces(marks, notes: notes) { a, b in (b - a) * 16 }
        XCTAssertEqual(n.pieces.map { $0.note }, [48])
        XCTAssertEqual(n.pieces.first?.len, 12)
        XCTAssertTrue(n.cuts.isEmpty)
    }
}
