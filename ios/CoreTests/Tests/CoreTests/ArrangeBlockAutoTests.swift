import XCTest
@testable import Core

/// Автоматизация в блоках (решение пользователя 1.11): у каждого блока своя кривая, едет и копируется с ним;
/// LINK соединяет кривую со следующим блоком; прежний формат раскладывается по блокам.
final class ArrangeBlockAutoTests: XCTestCase {
    private func track() -> Track {
        var t = Track(index: 0)
        t.placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        t.placeBlock(ArrBlock(clip: 0, start: 32, length: 16))
        return t
    }

    func testPointsGoToBlocksAndGroupsBreak() {
        var t = track()
        t.setAuto("filter", [ArrAutoPoint(x: 4, y: 1), ArrAutoPoint(x: 24, y: 0.5), ArrAutoPoint(x: 40, y: 0)])
        XCTAssertEqual(t.blocks[0].autos[0].points, [ArrAutoPoint(x: 4, y: 1)])
        XCTAssertEqual(t.blocks[1].autos[0].points, [ArrAutoPoint(x: 8, y: 0)], "x — от начала блока")
        XCTAssertEqual(t.autoGroups("filter").count, 2, "точка в промежутке не ставится, блоки отдельно")
        XCTAssertNil(t.autoValue("filter", at: 20), "между блоками — значение ручки")
        t.setAutoLink(0, true)
        XCTAssertEqual(t.autoGroups("filter").count, 1)
        XCTAssertEqual(t.autoValue("filter", at: 22)!, 0.5, accuracy: 1e-9, "LINK — прямая через промежуток")
    }

    func testMoveDuplicateDeleteCarryCurve() {
        var t = track()
        t.setAuto("filter", [ArrAutoPoint(x: 2, y: 0.2), ArrAutoPoint(x: 10, y: 0.8)])
        let i: Int = t.moveBlock(0, to: 64)
        XCTAssertEqual(t.autoPoints("filter").map { $0.x }, [66, 74], "кривая едет с блоком")
        let j: Int = t.duplicateBlock(i)
        XCTAssertEqual(t.autoPoints("filter").map { $0.x }, [66, 74, 82, 90])
        // Правка копии не трогает оригинал.
        t.setAuto("filter", [ArrAutoPoint(x: 66, y: 0.2), ArrAutoPoint(x: 74, y: 0.8), ArrAutoPoint(x: 84, y: 1)])
        XCTAssertEqual(t.blocks[i].autos[0].points.count, 2)
        XCTAssertEqual(t.blocks[j].autos[0].points, [ArrAutoPoint(x: 4, y: 1)])
        t.deleteBlock(j)
        XCTAssertEqual(t.autoPoints("filter").map { $0.x }, [66, 74])
    }

    func testResizeLeftKeepsTimelinePlaces() {
        var t = track()
        t.setAuto("filter", [ArrAutoPoint(x: 6, y: 0.2), ArrAutoPoint(x: 12, y: 0.8)])
        _ = t.resizeBlock(0, start: 4, end: 16)
        XCTAssertEqual(t.autoPoints("filter").map { $0.x }, [6, 12])
        _ = t.resizeBlock(0, start: 8, end: 16)
        XCTAssertEqual(t.autoPoints("filter").map { $0.x }, [12], "точка за краем блока не звучит")
    }

    func testMigrateOldFormat() throws {
        var t = Track(index: 0)
        t.placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        t.placeBlock(ArrBlock(clip: 0, start: 16, length: 16))
        t.autos = [ArrAutoLane(param: "filter", points: [ArrAutoPoint(x: 0, y: 0), ArrAutoPoint(x: 30, y: 1)])]
        let data: Data = try JSONEncoder().encode(t)
        let u: Track = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertTrue(u.autos[0].points.isEmpty, "у строки точек не остаётся")
        XCTAssertEqual(u.autoPoints("filter").map { $0.x }, [0, 30])
        XCTAssertEqual(u.autoValue("filter", at: 15)!, 0.5, accuracy: 1e-9, "соседние блоки — с LINK, звучит как раньше")
    }

    /// Колбэк: между блоками без LINK кривая не действует (значение ручки), с LINK — прямая.
    func testPlaybackBreaksBetweenBlocks() {
        var p = Project()
        for t in 1..<8 { p.tracks[t].clips[0] = nil }
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 8))
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 24, length: 8))
        p.tracks[0].setAuto("reverb", [ArrAutoPoint(x: 0, y: 1), ArrAutoPoint(x: 8, y: 1), ArrAutoPoint(x: 24, y: 1)])
        let snap = SeqSnapshot(p)
        let d: SeqData = snap.data
        let j: Int = ArrAutoTarget.index("reverb")!
        XCTAssertEqual(d.auto(0, j, at: 4), 1, accuracy: 1e-6)
        XCTAssertEqual(d.auto(0, j, at: 16), -1, "промежуток — без кривой")
        XCTAssertEqual(d.auto(0, j, at: 8), 1, accuracy: 1e-6, "сама точка на краю")
        p.tracks[0].setAutoLink(0, true)
        let snap2 = SeqSnapshot(p)
        let e: SeqData = snap2.data
        XCTAssertEqual(e.auto(0, j, at: 16), 1, accuracy: 1e-6)
        withExtendedLifetime(snap) {}
        withExtendedLifetime(snap2) {}
    }

    /// DUPLICATE в меню дорожки: копии блоков — со своей копией клипа, кривыми и LINK (как у оригиналов).
    func testTrackDuplicateKeepsPatternCurvesAndLink() {
        var t = track()
        var c = Clip()
        c.pages[0][3].on = true
        t.blocks[0].pattern = c
        t.setAuto("filter", [ArrAutoPoint(x: 2, y: 0.2), ArrAutoPoint(x: 10, y: 0.8), ArrAutoPoint(x: 40, y: 0.4)])
        t.setAutoLink(0, true)
        t.duplicateBlocks()
        XCTAssertEqual(t.blocks.count, 4)
        XCTAssertEqual(t.blocks[2].start, 48)
        XCTAssertEqual(t.blocks[2].pattern, c, "своя копия клипа")
        XCTAssertTrue(t.blocks[2].autoLink, "LINK")
        XCTAssertEqual(t.autoPoints("filter").map { $0.x }, [2, 10, 40, 50, 58, 88])
        XCTAssertEqual(t.autoValue("filter", at: 73)!, 0.6, accuracy: 1e-9, "LINK копий — прямая через промежуток")
    }
}
