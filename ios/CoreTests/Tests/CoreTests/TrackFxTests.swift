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

    /// MORPH эффектов (17.11): исходное запоминается, на всех дорожках — сдвиг на ту же долю, возврат — в клипы.
    func testMorphFxAndReturn() throws {
        var p = Project()
        p.setFx(track: 0, "rev.decay", 1.5)
        p.setFx(track: 1, "rev.decay", 3)
        let def = try XCTUnwrap(Params.byId["rev.decay"])
        p.morphFx(track: 0, "rev.decay")
        let target: Double = 8
        p.setFx(track: 0, "rev.decay", target)
        let dn: Double = def.toNorm(target) - def.toNorm(1.5)
        p.morphShiftFx(from: 0, def: def, norm: def.toNorm(target))
        XCTAssertTrue(p.tracks[0].morphEdited && p.tracks[1].morphEdited, "точка MORPH на дорожках")
        XCTAssertEqual(def.toNorm(p.fxValue(track: 1, "rev.decay")), def.toNorm(3) + dn, accuracy: 1e-9)
        let pts = p.morphReturnPoints()
        XCTAssertEqual(pts.count, p.tracks.count, "все дорожки с клипом")
        p.applyMorphReturn(pts, 0.5)
        XCTAssertLessThan(p.fxValue(track: 0, "rev.decay"), target)
        for i in p.tracks.indices where p.tracks[i].morphEdited { p.undoMorph(track: i) }
        XCTAssertEqual(p.fxValue(track: 0, "rev.decay"), 1.5, accuracy: 1e-9)
        XCTAssertEqual(p.fxValue(track: 1, "rev.decay"), 3, accuracy: 1e-9)
        XCTAssertNil(p.tracks[0].params["fx:rev.decay"], "ключ MORPH не попадает в ручки")
        XCTAssertFalse(p.tracks[0].morphEdited)
    }
}
