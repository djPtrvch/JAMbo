import XCTest
@testable import Core

final class SyncTests: XCTestCase {
    /// По умолчанию — как в вебе; испорченные значения — в пределах; старые настройки без sync читаются.
    func testDefaultsAndCoding() throws {
        let d = SyncSettings()
        XCTAssertEqual(d.quantum, 1)
        XCTAssertFalse(d.clock)
        XCTAssertEqual(d.source, .send)
        XCTAssertNil(d.clockOut)
        XCTAssertTrue(d.midiStartStop)
        XCTAssertTrue(d.linkNotify)
        XCTAssertFalse(d.linkStartStop)
        let json = #"{"quantum":3,"midiOffset":500,"linkOffset":-900,"source":"receive","clockOut":42}"#
        let s = try JSONDecoder().decode(SyncSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.quantum, 1)
        XCTAssertEqual(s.midiOffset, 200)
        XCTAssertEqual(s.linkOffset, -200)
        XCTAssertEqual(s.source, .receive)
        XCTAssertEqual(s.clockOut, 42)
        let old = AppSettings.decode(Data(#"{"velocity":true}"#.utf8))
        XCTAssertEqual(old.sync, SyncSettings())
        var a = AppSettings()
        a.sync.quantum = 4
        a.sync.clock = true
        XCTAssertEqual(AppSettings.decode(a.encode()).sync, a.sync)
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
