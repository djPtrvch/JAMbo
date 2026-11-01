import XCTest
@testable import Core

/// CUT в редакторе сэмпла: вырезание с кроссфейдом на стыке, сдвиг маркеров нарезки и меток WARP.
final class SampleCutTests: XCTestCase {
    private func ramp(_ n: Int, stereo: Bool) -> SampleData {
        let s = SampleData(frames: n, stereo: stereo)
        for i in 0..<n {
            s.left[i] = Float(i)
            if stereo { s.right[i] = -Float(i) }
        }
        return s
    }

    func testCutJoinsWithFade() {
        let s = ramp(10000, stereo: true)
        let out = SampleEdit.cut(s, 0.2, 0.5)
        XCTAssertEqual(out.frames, 7000)
        XCTAssertEqual(out.channels, 2)
        XCTAssertEqual(out.left[1999], 1999, "до стыка — как было")
        let f = SampleEdit.cutFade
        XCTAssertEqual(out.left[2000 + f], Float(5000 + f), "после кроссфейда — правая часть")
        XCTAssertEqual(out.right[2000 + f], -Float(5000 + f))
        // Кроссфейд: от левой (продолжение) к правой, монотонно.
        let mid: Float = out.left[2000 + f / 2]
        XCTAssertGreaterThan(mid, Float(2000 + f / 2))
        XCTAssertLessThan(mid, Float(5000 + f / 2))
        XCTAssertEqual(out.left[6999], 9999)
    }

    func testCutEdges() {
        let s = ramp(1000, stereo: false)
        let head = SampleEdit.cut(s, 0, 0.3)
        XCTAssertEqual(head.frames, 700)
        XCTAssertEqual(head.left[0], 300, "с начала — без кроссфейда")
        let tail = SampleEdit.cut(s, 0.6, 1)
        XCTAssertEqual(tail.frames, 600)
        XCTAssertEqual(tail.left[599], 599)
        XCTAssertNil(SampleEdit.cutRange(1000, 0, 1), "всё — нечего оставить")
        XCTAssertNil(SampleEdit.cutRange(1000, 0.5, 0.5))
    }

    func testCarrySlicesAndWarp() {
        var t = Track(index: 0)
        let frames = 96000
        t.addSlice("a", at: 0.1)
        t.addSlice("a", at: 0.3)
        t.addSlice("a", at: 0.6)
        _ = t.setSliceNote("a", 2, note: 60, notes: [48, 49, 50])
        // 120 BPM: доля — 24000; метки на 0, 1, 2, 3 доли.
        t.autoWarp("a", onsets: [24000, 48000, 72000], frames: frames, detectedBpm: 120, grid: 1)
        // Вырезаем 24000..<48000 (ровно одну долю).
        let (i0, i1) = SampleEdit.cutRange(frames, 0.25, 0.5)!
        t.carryCut("a", "b", frames: frames, i0, i1, detectedBpm: 120)
        let m = t.sliceMarks("b")
        XCTAssertEqual(m.count, 2, "маркер внутри вырезанного удалён")
        XCTAssertEqual(m[0].at * 72000, 9600, accuracy: 1e-6)
        XCTAssertEqual(m[1].at * 72000, 57600 - 24000, accuracy: 1e-6)
        XCTAssertEqual(m[1].note, 60, "своя нота едет с маркером")
        let w = t.warpInfo("b")
        XCTAssertEqual(w.bpm, 120, "с метками BPM файла закрепляется")
        XCTAssertEqual(w.marks.map { $0.beat }, [0, 1, 2], "метка на стыке — одна, после — на долю раньше")
        XCTAssertEqual(w.marks[1].at * 72000, 24000, accuracy: 1e-6)
        XCTAssertEqual(w.marks[2].at * 72000, 48000, accuracy: 1e-6)
        XCTAssertEqual(t.sliceMarks("a").count, 3, "у исходного — как было (UNDO)")
    }
}
