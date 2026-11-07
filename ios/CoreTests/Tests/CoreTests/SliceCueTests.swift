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
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.sliceMarks("loop.caf").map { $0.isFree }, [false, true, false])
        // Нота метке без ноты — она становится маркером с нотой; занятая нота — не назначается.
        XCTAssertFalse(t.setSliceNote("loop.caf", 1, note: 49, notes: notes))
        XCTAssertTrue(t.setSliceNote("loop.caf", 1, note: 60, notes: notes))
        XCTAssertFalse(t.sliceMarks("loop.caf")[1].isFree)
        XCTAssertEqual(Slices.notes(t.sliceMarks("loop.caf"), map: .chromatic, scale: 0, root: 0), [48, 60, 50], "номер по порядку — по месту маркера")
        // Двойной тап клавиши при удержании флажка — нота снята.
        t.clearSliceNote("loop.caf", 1)
        XCTAssertTrue(t.sliceMarks("loop.caf")[1].isFree)
        XCTAssertNil(t.sliceMarks("loop.caf")[1].note)
        XCTAssertEqual(Slices.notes(t.sliceMarks("loop.caf"), map: .chromatic, scale: 0, root: 0), [48, Slices.noNote, 49])
    }

    func testPiecesAndWrite() {
        var marks: [SliceMark] = [SliceMark(at: 0, free: true), SliceMark(at: 0.5, role: 1, free: true)]
        var notes = Slices.notes(marks, map: .chromatic, scale: 0, root: 0)
        let r = SliceRhythm.pieces(marks, notes: notes) { a, b in (b - a) * 16 }
        XCTAssertEqual(r.pieces.map { $0.note }, [SliceRhythm.cutNote, SliceRhythm.cutNote + 1])
        XCTAssertEqual(r.pieces.map { $0.len }, [8, 8])
        XCTAssertEqual(r.pieces[1].role, .snare)
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
