import XCTest
@testable import Core

final class MidiOutPlanTests: XCTestCase {
    private func note(_ kind: UInt8, _ n: Int, len: Int64 = 4800, live: Int = 0) -> MidiNoteOut {
        var e = MidiNoteOut()
        e.kind = kind
        e.note = Int16(n)
        e.velocity = 100
        e.length = len
        e.liveId = live
        return e
    }

    /// Нота секвенсора: Note On сразу, Note Off — когда подойдёт его момент (длина 4800 кадров — 0,1 с).
    func testSequencerNoteOnAndTimedOff() {
        var p = MidiOutPlan()
        let r = MidiOutRoute(dest: 7, channel: 2)
        let on = p.add(note(MidiNoteOut.on, 60), time: 10, route: r, sampleRate: 48000)
        XCTAssertEqual(on, [MidiOutPlan.Send(time: 10, dest: 7, word: MidiMessage.ump(status: 0x92, 60, 100))])
        XCTAssertEqual(p.due(now: 10, ahead: 0.05), [])
        let off = p.due(now: 10.06, ahead: 0.05)
        XCTAssertEqual(off.count, 1)
        XCTAssertEqual(off[0].time, 10.1, accuracy: 1e-9)
        XCTAssertEqual(off[0].word, MidiMessage.ump(status: 0x82, 60, 0))
        XCTAssertEqual(p.pending, 0)
    }

    /// Повтор той же ноты до её конца: прежняя отпускается перед новой; стоп отпускает всё сразу.
    func testRetriggerAndStop() {
        var p = MidiOutPlan()
        let r = MidiOutRoute(dest: 1, channel: 0)
        _ = p.add(note(MidiNoteOut.on, 36, len: 48000), time: 1, route: r, sampleRate: 48000)
        let again = p.add(note(MidiNoteOut.on, 36, len: 48000), time: 1.5, route: r, sampleRate: 48000)
        XCTAssertEqual(again.map { $0.word }, [MidiMessage.ump(status: 0x80, 36, 0), MidiMessage.ump(status: 0x90, 36, 100)])
        XCTAssertEqual(p.pending, 1)
        let stop = p.add(note(MidiNoteOut.allOff, 0), time: 1.7, route: nil, sampleRate: 48000)
        XCTAssertEqual(stop, [MidiOutPlan.Send(time: 1.7, dest: 1, word: MidiMessage.ump(status: 0x80, 36, 0))])
        XCTAssertEqual(p.pending, 0)
    }

    /// Живая нота держится до отпускания своего liveId; дорожка без выхода — ничего.
    func testLiveNoteAndNoRoute() {
        var p = MidiOutPlan()
        let r = MidiOutRoute(dest: 3, channel: 15)
        XCTAssertEqual(p.add(note(MidiNoteOut.on, 50), time: 0, route: nil, sampleRate: 48000), [])
        _ = p.add(note(MidiNoteOut.on, 62, len: -1, live: 4), time: 2, route: r, sampleRate: 48000)
        XCTAssertEqual(p.due(now: 100, ahead: 0), [])
        XCTAssertEqual(p.add(note(MidiNoteOut.release, 0, live: 5), time: 3, route: nil, sampleRate: 48000), [])
        let off = p.add(note(MidiNoteOut.release, 0, live: 4), time: 3, route: nil, sampleRate: 48000)
        XCTAssertEqual(off, [MidiOutPlan.Send(time: 3, dest: 3, word: MidiMessage.ump(status: 0x8F, 62, 0))])
    }
}
