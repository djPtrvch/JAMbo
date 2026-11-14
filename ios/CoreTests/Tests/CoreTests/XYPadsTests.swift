import XCTest
@testable import Core

/// Режим XY (на пробу): оси площадок хранятся в проекте; старые проекты — без осей; настройка XY PADS.
final class XYPadsTests: XCTestCase {
    func testAxesRoundTrip() throws {
        var p = Project()
        p.setXYAxis(3, XYAxis(track: p.tracks[2].id, page: 1, slot: 5, amount: -0.4))
        XCTAssertEqual(p.xy.count, XYAxis.count)
        let data = try JSONEncoder().encode(p)
        let q = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(q.xyAxis(3), XYAxis(track: p.tracks[2].id, page: 1, slot: 5, amount: -0.4))
        XCTAssertNil(q.xyAxis(0))
        XCTAssertEqual(q, p)
    }

    func testOldProjectHasNoAxes() throws {
        let data = try JSONEncoder().encode(Project())
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\"xy\""))
        let q = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertTrue(q.xy.isEmpty)
        XCTAssertNil(q.xyAxis(7))
    }

    func testSettingRoundTrip() throws {
        XCTAssertFalse(AppSettings().xyPads)
        var s = AppSettings()
        s.xyPads = true
        XCTAssertTrue(AppSettings.decode(s.encode()).xyPads)
    }
}
