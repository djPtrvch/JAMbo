import XCTest
@testable import Core

final class NoteCaptureTests: XCTestCase {
    func testPhraseAfterLastPause() {
        let all: [PhraseNote] = [PhraseNote(step: 0, notes: [36]), PhraseNote(step: 4, notes: [38], len: 2),
                                 PhraseNote(step: 22, notes: [40]), PhraseNote(step: 25, notes: [41])]
        // 4 + 2 = 6, до 22 — 16 шагов паузы: новая фраза.
        XCTAssertEqual(NoteCapture.phrase(all).map { $0.step }, [22, 25])
        let close: [PhraseNote] = [PhraseNote(step: 0, notes: [36]), PhraseNote(step: 16, notes: [38])]
        XCTAssertEqual(NoteCapture.phrase(close).count, 2, "пауза 15 шагов — фраза одна")
        XCTAssertTrue(NoteCapture.phrase([]).isEmpty)
    }

    func testPhraseNotLongerThanEightPages() {
        let all: [PhraseNote] = (0..<20).map { PhraseNote(step: $0 * 8, notes: [36]) }
        let p = NoteCapture.phrase(all)
        XCTAssertEqual(p.last?.step, 152)
        XCTAssertEqual(p.first?.step, 32, "от страницы первой ноты — не больше 128 шагов")
        XCTAssertEqual(NoteCapture.pages(p), 8)
    }

    func testPagesByPhrase() {
        XCTAssertEqual(NoteCapture.pages([PhraseNote(step: 3, notes: [36]), PhraseNote(step: 15, notes: [36])]), 1)
        XCTAssertEqual(NoteCapture.pages([PhraseNote(step: 17, notes: [36]), PhraseNote(step: 40, notes: [36])]), 2)
        XCTAssertEqual(NoteCapture.pages([PhraseNote(step: 0, notes: [36]), PhraseNote(step: 40, notes: [36])]), 4)
        XCTAssertEqual(NoteCapture.pages([PhraseNote(step: 0, notes: [36]), PhraseNote(step: 70, notes: [36])]), 8)
    }

    func testCaptureIntoEmptyPattern() {
        var t = Track(index: 0)
        let ok = t.capture([PhraseNote(step: 20, notes: [36], len: 3), PhraseNote(step: 20, notes: [40]),
                            PhraseNote(step: 35, notes: [43])])
        XCTAssertTrue(ok)
        XCTAssertEqual(t.pages.count, 2, "от страницы 16 до шага 35 — 20 шагов, 2 страницы")
        XCTAssertEqual(t.length, 32)
        XCTAssertEqual(t.playFrom, 0)
        XCTAssertEqual(t.playTo, 1)
        XCTAssertEqual(t.step(20)?.notes, [36, 40], "ноты одного шага — аккорд")
        XCTAssertEqual(t.step(20)?.len, 3)
        XCTAssertEqual(t.step(3)?.on, true, "35 по кругу из 32 — шаг 3")
        XCTAssertFalse(t.capture([]))
    }

    func testCaptureAddsToExistingPattern() {
        var t = Track(index: 0)
        t.toggleStep(2, notes: [48])
        t.capture([PhraseNote(step: 18, notes: [36]), PhraseNote(step: 34, notes: [38])])
        XCTAssertEqual(t.pages.count, 1, "длина не меняется")
        XCTAssertEqual(t.step(2)?.notes.sorted(), [36, 38, 48], "по кругу, к стоящему тригу")
    }

    func testCaptureWithVelocity() {
        var t = Track(index: 0)
        t.capture([PhraseNote(step: 0, notes: [36], velocity: 0.5)])
        XCTAssertEqual(t.step(0)?.noteVel(0), (127 * 0.5).rounded())
    }
}
