import XCTest
@testable import Core

final class LibraryMarksTests: XCTestCase {
    func testRememberAndApply() throws {
        var t = Track(index: 0)
        t.addSlice("s", at: 0.25)
        t.addSlice("s", at: 0.5)
        t.autoWarp("s", onsets: [24000, 48000], frames: 96000, detectedBpm: 120, grid: 1)
        var lib = Library()
        XCTAssertTrue(lib.remember("s", t.sampleMarks("s")))
        XCTAssertFalse(lib.remember("s", t.sampleMarks("s")), "без перемен — без записи")
        // Сохранение и чтение библиотеки.
        let data = try JSONEncoder().encode(lib)
        let back = try JSONDecoder().decode(Library.self, from: data)
        XCTAssertEqual(back.marks["s"], lib.marks["s"])
        // Другая дорожка получает запомненное.
        var u = Track(index: 1)
        u.applyMarks("s", back.marks["s"])
        XCTAssertEqual(u.sliceMarks("s"), t.sliceMarks("s"))
        XCTAssertEqual(u.warpInfo("s"), t.warpInfo("s"))
        // Свои маркеры дорожки не перезаписываются.
        var v = Track(index: 2)
        v.addSlice("s", at: 0.9)
        v.applyMarks("s", back.marks["s"])
        XCTAssertEqual(v.sliceMarks("s").count, 1)
        // Всё удалили — забыто.
        XCTAssertTrue(lib.remember("s", SampleMarks()))
        XCTAssertNil(lib.marks["s"])
        // Старая библиотека без поля marks читается.
        let old = try JSONDecoder().decode(Library.self, from: Data("{\"nodes\":[]}".utf8))
        XCTAssertTrue(old.marks.isEmpty)
    }
}
