import XCTest
@testable import Core

/// Удаление блока убирает автоматизацию на его месте (кривая вне места не меняется).
final class ArrangeClearAutoTests: XCTestCase {
    func testClearInside() {
        var t = Track(index: 0)
        t.setAuto("reverb", [ArrAutoPoint(x: 0, y: 0), ArrAutoPoint(x: 20, y: 1), ArrAutoPoint(x: 40, y: 0),
                             ArrAutoPoint(x: 64, y: 0.5)])
        let before16: Double? = t.autos[0].value(at: 8)
        let before40: Double? = t.autos[0].value(at: 50)
        t.clearAuto(from: 16, to: 48)
        let pts: [ArrAutoPoint] = t.autos[0].points
        XCTAssertFalse(pts.contains { $0.x == 20 || $0.x == 40 })
        XCTAssertEqual(t.autos[0].value(at: 8)!, before16!, accuracy: 1e-9, "слева — как было")
        XCTAssertEqual(t.autos[0].value(at: 50)!, before40!, accuracy: 1e-9, "справа — как было")
        XCTAssertEqual(pts.first { $0.x == 16 }?.y ?? -1, 0.8, accuracy: 1e-9)
    }

    func testClearTail() {
        var t = Track(index: 0)
        t.setAuto("reverb", [ArrAutoPoint(x: 0, y: 0), ArrAutoPoint(x: 8, y: 1), ArrAutoPoint(x: 24, y: 1)])
        t.clearAuto(from: 16, to: 32)
        XCTAssertEqual(t.autos[0].points.map { $0.x }, [0, 8, 16], "справа точек нет — кривая кончается на краю")
        var u = Track(index: 0)
        u.setAuto("reverb", [ArrAutoPoint(x: 40, y: 1)])
        u.clearAuto(from: 0, to: 16)
        XCTAssertEqual(u.autos[0].points.count, 1, "точек на месте нет — кривая та же")
    }
}
