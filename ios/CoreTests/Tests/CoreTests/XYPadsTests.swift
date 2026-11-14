import XCTest
@testable import Core

/// Режим XY (на пробу): у каждой дорожки свои 4 площадки — ручки осей в Track.xy; старые проекты — без осей.
final class XYPadsTests: XCTestCase {
    func testTrackAxesRoundTrip() throws {
        var p = Project()
        p.tracks[2].setXYSlot(3, 5)
        p.tracks[2].setXYSlot(0, 9)
        XCTAssertEqual(p.tracks[2].xy.count, Track.xyAxes)
        let q = try JSONDecoder().decode(Project.self, from: try JSONEncoder().encode(p))
        XCTAssertEqual(q.tracks[2].xySlot(3), 5)
        XCTAssertEqual(q.tracks[2].xySlot(0), 9)
        XCTAssertNil(q.tracks[2].xySlot(1))
        XCTAssertNil(q.tracks[0].xySlot(0), "у других дорожек — свои площадки")
        XCTAssertEqual(q, p)
    }

    func testClearAllEmpties() {
        var t = Project().tracks[0]
        t.setXYSlot(1, 4)
        t.setXYSlot(1, nil)
        XCTAssertTrue(t.xy.isEmpty)
        t.setXYSlot(9, 4)
        XCTAssertTrue(t.xy.isEmpty, "осей 8")
    }

    func testOldProjectHasNoAxes() throws {
        let data = try JSONEncoder().encode(Project())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"xy\""))
        let q = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertTrue(q.tracks.allSatisfy { $0.xy.isEmpty })
    }

    func testSettingRoundTrip() throws {
        XCTAssertFalse(AppSettings().xyPads)
        var s = AppSettings()
        s.xyPads = true
        XCTAssertTrue(AppSettings.decode(s.encode()).xyPads)
    }
}
