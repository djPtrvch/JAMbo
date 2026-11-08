import XCTest
@testable import Core

final class SyncTests: XCTestCase {
    /// По умолчанию — как в вебе; испорченные значения — в пределах; старые настройки без sync читаются.
    func testDefaultsAndCoding() throws {
        let d = SyncSettings()
        XCTAssertEqual(d.quantum, 1)
        XCTAssertFalse(d.clock)
        XCTAssertTrue(d.send)
        XCTAssertFalse(d.receive)
        XCTAssertEqual(d.clockOuts, [])
        XCTAssertNil(d.clockIn)
        XCTAssertTrue(d.midiStartStop)
        XCTAssertTrue(d.linkNotify)
        XCTAssertFalse(d.linkStartStop)
        let json = #"{"quantum":3,"midiOffset":500,"linkOffset":-900,"source":"receive","clockOut":42,"clockIn":7}"#
        let s = try JSONDecoder().decode(SyncSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.quantum, 1)
        XCTAssertEqual(s.midiOffset, 200)
        XCTAssertEqual(s.linkOffset, -200)
        // Прежние настройки (до 8.11): RECEIVE — только приём, один выход — список из него.
        XCTAssertFalse(s.send)
        XCTAssertTrue(s.receive)
        XCTAssertEqual(s.clockOuts, [42])
        XCTAssertEqual(s.clockIn, 7)
        XCTAssertTrue(s.acceptsClock(source: 7))
        XCTAssertFalse(s.acceptsClock(source: 8))
        XCTAssertTrue(d.acceptsClock(source: 8))
        let old = AppSettings.decode(Data(#"{"velocity":true}"#.utf8))
        XCTAssertEqual(old.sync, SyncSettings())
        var a = AppSettings()
        a.sync.quantum = 4
        a.sync.clock = true
        XCTAssertEqual(AppSettings.decode(a.encode()).sync, a.sync)
    }

    /// SEND и RECEIVE вместе, несколько выходов: пусто — все; убран последний — снова все; запись и чтение.
    func testSendReceiveOutputs() throws {
        var s = SyncSettings()
        s.receive = true
        XCTAssertTrue(s.send && s.receive)
        XCTAssertTrue(s.sendsTo(5))
        s.toggleOut(5)
        s.toggleOut(9)
        XCTAssertEqual(s.clockOuts, [5, 9])
        XCTAssertTrue(s.sendsTo(9))
        XCTAssertFalse(s.sendsTo(7))
        s.toggleOut(5)
        s.toggleOut(9)
        XCTAssertEqual(s.clockOuts, [])
        XCTAssertTrue(s.sendsTo(7))
        s.toggleOut(3)
        let back = try JSONDecoder().decode(SyncSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        let old = try JSONDecoder().decode(SyncSettings.self, from: Data(#"{"source":"send"}"#.utf8))
        XCTAssertTrue(old.send)
        XCTAssertFalse(old.receive)
        XCTAssertEqual(old.clockOuts, [])
    }

    /// Ноты с входа клока: при приёме не играют (выбранный вход или вход последнего тика), с NOTES FROM CLOCK INPUT —
    /// играют; без приёма — всегда.
    func testClockNotes() {
        var s = SyncSettings()
        XCTAssertFalse(s.blocksNotes(source: 5, clockSource: 5), "клок выключен")
        s.clock = true
        s.receive = true
        XCTAssertTrue(s.blocksNotes(source: 5, clockSource: 5))
        XCTAssertFalse(s.blocksNotes(source: 6, clockSource: 5))
        XCTAssertFalse(s.blocksNotes(source: 5, clockSource: 0), "тиков ещё не было")
        s.clockIn = 7
        XCTAssertTrue(s.blocksNotes(source: 7, clockSource: 0))
        XCTAssertFalse(s.blocksNotes(source: 5, clockSource: 5))
        s.clockNotes = true
        XCTAssertFalse(s.blocksNotes(source: 7, clockSource: 7))
        s.clockNotes = false
        s.receive = false
        XCTAssertFalse(s.blocksNotes(source: 7, clockSource: 7))
    }

    /// Полоса фазы: 4 отрезка на такт × квант; в начале фразы горит один, стоп — ни одного.
    func testPhase() {
        var s = SyncSettings()
        XCTAssertEqual(s.phaseSegments, 4)
        XCTAssertEqual(s.phaseLit(beat: -1), 0)
        XCTAssertEqual(s.phaseLit(beat: 0), 1)
        XCTAssertEqual(s.phaseLit(beat: 3), 4)
        XCTAssertEqual(s.phaseLit(beat: 4), 1)
        s.quantum = 2
        XCTAssertEqual(s.phaseSegments, 8)
        XCTAssertEqual(s.phaseLit(beat: 7), 8)
        XCTAssertEqual(s.phaseLit(beat: 8), 1)
    }
}
