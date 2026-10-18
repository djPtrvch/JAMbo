import XCTest
@testable import Core

final class PianoTests: XCTestCase {
    func testScaleNotesAndKeys() {
        // C Minor от C2 (36): C D Eb F G Ab Bb, следующая октава.
        let notes = (0..<8).map { Scales.note(scale: 1, root: 0, octave: 2, degree: $0) }
        XCTAssertEqual(notes, [36, 38, 39, 41, 43, 44, 46, 48])
        XCTAssertEqual(Scales.keyCount(scale: 1, octaves: 2), 15)
        XCTAssertEqual(Scales.keyCount(scale: 8, octaves: 1), 6, "пентатоника, одна октава + корень")
        XCTAssertEqual(Scales.keyCount(scale: 10, octaves: 2), 25)
        XCTAssertEqual(Scales.note(scale: 0, root: 4, octave: 2, degree: 0), 40, "E2")
    }

    func testChordsAndNames() {
        XCTAssertEqual(Scales.chord(scale: 0, root: 0, octave: 2, degree: 0), [36, 40, 43])
        XCTAssertEqual(Scales.chordName(scale: 0, root: 0, octave: 2, degree: 5), "Am")
        XCTAssertEqual(Scales.chordName(scale: 0, root: 0, octave: 2, degree: 6), "Bdim")
        XCTAssertEqual(Scales.chordName(scale: 0, root: 0, octave: 2, degree: 4), "G")
        let names = Scales.progressions[0].degrees.map { Scales.chordName(scale: 0, root: 0, octave: 2, degree: $0) }
        XCTAssertEqual(names, ["C", "G", "Am", "F"])
    }

    func testRecordNotesMergeOverdubVelocity() {
        var t = Track(index: 0)
        t.pages[0][3].on = true
        t.pages[0][3].notes = [40]
        t.recordNotes(3, [36], merge: false, overdub: false, velocity: nil)
        XCTAssertEqual(t.pages[0][3].notes, [36], "OVERDUB OFF — заменяет")
        t.recordNotes(3, [43], merge: true, overdub: false, velocity: nil)
        XCTAssertEqual(t.pages[0][3].notes, [36, 43], "тот же шаг в дубле — аккорд")
        t.recordNotes(3, [48], merge: false, overdub: true, velocity: nil)
        XCTAssertEqual(t.pages[0][3].notes, [36, 43, 48], "OVERDUB ON — добавляет")
        t.recordNotes(5, [36], merge: false, overdub: false, velocity: 0.5)
        XCTAssertEqual(t.pages[0][5].vels, [64], "сила — velocity ноты (S8), не p-lock Level")
        XCTAssertNil(t.pages[0][5].locks["level"])
        t.recordNotes(5, [40], merge: true, overdub: false, velocity: 0.9)
        XCTAssertEqual(t.pages[0][5].vels, [64, 114], "у каждой ноты аккорда своя")
        t.recordNotes(5, [36], merge: true, overdub: false, velocity: 0.2)
        XCTAssertEqual(t.pages[0][5].vels, [64, 114], "та же нота в дубле — по самой сильной")
        t.recordLength(5, 30)
        XCTAssertEqual(t.pages[0][5].len, 11, "не дальше конца паттерна (16 − 5)")
        XCTAssertTrue(t.clearPassStep(5))
        XCTAssertFalse(t.clearPassStep(5))
    }

    func testRecordClock() {
        // Шаг 6000 кадров; следующий шаг 10 на кадре 60000.
        let q = RecordClock.tick(frame: 57500, nextTick: 10, nextFrame: 60000, stepFrames: 6000, quantize: true)
        XCTAssertEqual(q, 10, "ближе к шагу 10")
        let f = RecordClock.tick(frame: 57500, nextTick: 10, nextFrame: 60000, stepFrames: 6000, quantize: false)
        XCTAssertEqual(f, 9, "без квантизации — шаг, в котором нажали")
        XCTAssertEqual(RecordClock.length(seconds: 0.3, stepSeconds: 0.125), 2)
        XCTAssertEqual(RecordClock.length(seconds: 0.01, stepSeconds: 0.125), 1)
    }

    func testPlayClockPublishedByCallback() {
        let core = AudioCore()
        core.publish(Project())
        core.events.push(.play(true))
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        for _ in 0..<30 { core.render(frames: 256, left: &l, right: &r, host: 1.5) }
        let s = core.sequencer.clock.read()
        XCTAssertTrue(s.playing)
        XCTAssertEqual(s.stepFrames, 6000, accuracy: 1e-9)
        XCTAssertEqual(s.blockFrame, 29 * 256)
        XCTAssertEqual(s.nextTick, 2, "кадр 7680: шаги 0 и 1 сыграны")
        XCTAssertEqual(s.nextFrame, 12000, accuracy: 1e-6)
        XCTAssertEqual(s.blockHost, 1.5)
    }

    func testHistorySerialAndSettingsDecode() {
        var h = History<Int>()
        let s0 = h.serial
        h.record(before: 1, after: 2)
        XCTAssertEqual(h.serial, s0 + 1)
        _ = h.undo(2)
        XCTAssertEqual(h.serial, s0 + 2)
        let old = "{\"velocity\":true}".data(using: .utf8)
        let st = AppSettings.decode(old)
        XCTAssertTrue(st.velocity)
        XCTAssertEqual(st.pianoOctaves, 2, "нет поля — по умолчанию")
        XCTAssertTrue(st.record.quantize)
        XCTAssertEqual(AppSettings.decode(st.encode()), st)
    }
}
