import XCTest
@testable import Core

/// RAW и профили пунктов SPACE (8.11): профиль в настройках (UserDefaults-словарь), смесь импульсов по RAW,
/// выровненные импульсы комнат в rooms.json.
final class MonitorProfileTests: XCTestCase {
    func testProfileRoundTrip() {
        var m = MonitorSettings()
        m.raw = 0.4
        m.ambienceDb = -10
        let curve = Data([1, 2, 3])
        m.spaces["Studio"] = MonitorProfile(ambienceDb: -3, raw: 0.25, strength: 0.8, correct: curve)
        m.spaces["Home Hi-Fi"] = MonitorProfile(ambienceDb: -60, raw: 1, strength: 1, correct: nil)
        let back = MonitorSettings(plist: m.plist)
        XCTAssertEqual(back.raw, 0.4)
        XCTAssertEqual(back.ambienceDb, -10)
        XCTAssertEqual(back.spaces["Studio"]?.ambienceDb, -3)
        XCTAssertEqual(back.spaces["Studio"]?.raw, 0.25)
        XCTAssertEqual(back.spaces["Studio"]?.strength, 0.8)
        XCTAssertEqual(back.spaces["Studio"]?.correct, curve)
        XCTAssertNil(back.spaces["Home Hi-Fi"]?.correct)
        // Неверные значения — в пределах.
        let bad = MonitorProfile(plist: ["raw": 7, "strength": -1, "ambienceDb": 9])
        XCTAssertEqual(bad.raw, 1)
        XCTAssertEqual(bad.strength, 0)
        XCTAssertEqual(bad.ambienceDb, 0)
        // Старые настройки (без raw и профилей) — по умолчанию.
        let old = MonitorSettings(plist: ["ambienceDb": -12])
        XCTAssertEqual(old.raw, 1)
        XCTAssertEqual(old.ambienceDb, -12)
        XCTAssertTrue(old.spaces.isEmpty)
    }

    func testRoomsHaveFlatAndMix() {
        let list = RoomTests.rooms()
        for (k, r) in list.enumerated() {
            XCTAssertFalse(r.flatFile.isEmpty)
            XCTAssertFalse(r.flatHeadFile.isEmpty)
            let ir: RoomIR = RoomTests.ir(k)
            let d = RoomTests.audio(r.flatFile)
            let flat = RoomIR(name: r.name, wav: d, gainDb: r.flatGainDb, direct: r.direct)!
            XCTAssertLessThan(flat.frames, ir.frames)
            XCTAssertTrue(ir.mixed(flat: flat, raw: 1) === ir)
            let z: RoomIR = ir.mixed(flat: flat, raw: 0)
            let half: RoomIR = ir.mixed(flat: flat, raw: 0.5)
            let n: Int = flat.frames
            var e0: Float = 0, eh: Float = 0, tail: Float = 0
            for path in 0..<4 {
                for i in stride(from: 0, to: n - 480, by: 3) {
                    let k: Int = path * ir.frames + i
                    let fl: Float = flat.h[path * n + i]
                    e0 = max(e0, abs(z.h[k] - fl))
                    eh = max(eh, abs(half.h[k] - 0.5 * (ir.h[k] + fl)))
                }
                for i in stride(from: n, to: ir.frames, by: 5) {
                    let k: Int = path * ir.frames + i
                    tail = max(tail, abs(z.h[k] - ir.h[k]))
                }
            }
            XCTAssertEqual(tail, 0)
            XCTAssertLessThan(e0, 1e-6)
            XCTAssertLessThan(eh, 1e-6)
        }
    }
}
