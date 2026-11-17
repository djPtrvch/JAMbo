import XCTest
@testable import Core

/// Эффекты дорожек в клипах (17.11): чтение и запись по дорожке, Duck — общий, перенос старых проектов (версия 10).
final class TrackFxTests: XCTestCase {
    func testSetAndReadPerTrack() {
        var p = Project()
        XCTAssertNotNil(p.tracks[0].clips[0], "у новой дорожки есть клип")
        p.setFx(track: 0, "rev.size", 70)
        XCTAssertEqual(p.fxValue(track: 0, "rev.size"), 70)
        XCTAssertEqual(p.fxValue(track: 1, "rev.size"), p.fx["rev.size"], "у другой дорожки — общее")
        XCTAssertEqual(p.tracks[0].clips[0]?.fx?["rev.size"], 70, "значение — в клипе")
        p.setFx(track: 1, "sc.attack", 5)
        XCTAssertEqual(p.fx["sc.attack"], 5, "Duck — общий")
        XCTAssertEqual(p.fxValue(track: 0, "sc.attack"), 5)
    }

    func testMigrationKeepsSound() throws {
        var p = Project()
        p.fx["rev.size"] = 55
        p.fx["dly.feedback"] = 70
        p.tracks[1].clips[0]?.fx = ["rev.size": 10, "sc.release": 300]
        p.version = 9
        let data = try JSONEncoder().encode(p)
        var q = try JSONDecoder().decode(Project.self, from: data)
        q.repair()
        XCTAssertEqual(q.version, 10)
        for t in 0..<2 {
            XCTAssertEqual(q.fxValue(track: t, "rev.size"), 55, "дорожка \(t): FX прежнего лидера")
            XCTAssertEqual(q.fxValue(track: t, "dly.feedback"), 70)
        }
        XCTAssertEqual(q.tracks[1].clips[0]?.fx?["sc.release"], 300, "общие ключи клипа остаются")
    }
}
