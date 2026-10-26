import XCTest
@testable import Core

/// Картинки FX: формы — по формулам звука, геометрия в пределах окна.
final class FxPictureTests: XCTestCase {
    func testFilterCuts() {
        XCTAssertNil(FxPicture.reverbCut(20))
        XCTAssertEqual(FxPicture.reverbCut(2000)!.x, 2.0 / 3, accuracy: 1e-9)
        XCTAssertNil(FxPicture.delayCut(0))
        XCTAssertFalse(FxPicture.delayCut(-100)!.low)
        XCTAssertTrue(FxPicture.delayCut(100)!.low)
        XCTAssertNil(FxPicture.driveCut(25))
        XCTAssertTrue(FxPicture.driveCut(200)!.low)
    }

    func testCutEnvelope() {
        // На частоте среза −3 dB; далеко в полосе пропускания — верх поля; за срезом — к низу; всё в поле.
        let hp = FxPicture.Cut(low: true, hz: 200)
        XCTAssertEqual(FxPicture.cutDb(hp, 200), -3.0103, accuracy: 1e-3)
        XCTAssertEqual(FxPicture.cutDb(FxPicture.Cut(low: false, hz: 3000), 3000), -3.0103, accuracy: 1e-3)
        let env = FxPicture.cutEnvelope(hp)
        XCTAssertEqual(env.first!.y, FxPicture.bottom, accuracy: 1e-9)
        XCTAssertEqual(env.last!.y, FxPicture.top, accuracy: 0.01)
        let lp = FxPicture.cutEnvelope(FxPicture.Cut(low: false, hz: 500))
        XCTAssertEqual(lp.first!.y, FxPicture.top, accuracy: 0.01)
        XCTAssertGreaterThan(lp.last!.y, 50)
        for p in env + lp {
            XCTAssertTrue(p.x >= FxPicture.x0 && p.x <= FxPicture.x1 && p.y >= FxPicture.top && p.y <= FxPicture.bottom)
        }
    }

    func testReverbGrows() {
        let a = FxPicture.reverb(size: 0, decay: 0.1, tone: -100)
        let b = FxPicture.reverb(size: 100, decay: 20, tone: 100)
        XCTAssertLessThan(a.size, b.size)
        XCTAssertLessThan(a.fill, b.fill)
        XCTAssertEqual(a.contours, 0)
        XCTAssertEqual(b.contours, 6)
    }

    func testDelayEchoes() {
        // 1/32 — шаг меньше, чем у 1 bar; FEEDBACK 0 — один повтор; 100 % — почти той же высоты.
        XCTAssertLessThan(FxPicture.delayStep(time: 0, synced: true), FxPicture.delayStep(time: 11, synced: true))
        XCTAssertEqual(FxPicture.delayEchoes(time: 5, synced: true, feedback: 0).count, 1)
        let full = FxPicture.delayEchoes(time: 0, synced: true, feedback: 100)
        XCTAssertGreaterThan(full.count, 10)
        XCTAssertGreaterThan(full[1].h, 0.95)
        XCTAssertEqual(full[0].side, -1)
        XCTAssertEqual(full[1].side, 1)
        for e in full { XCTAssertLessThanOrEqual(e.x, 1.0001) }
    }

    func testDriveWave() {
        // DRIVE растит амплитуду; HARD на 100 % срезан ровно на 1; все формы в ±1.
        let soft0 = FxPicture.driveWave(type: 0, drive: 0).map { abs($0) }.max()!
        let soft1 = FxPicture.driveWave(type: 0, drive: 100).map { abs($0) }.max()!
        XCTAssertLessThan(soft0, soft1)
        XCTAssertEqual(FxPicture.driveWave(type: 1, drive: 100).max()!, 1, accuracy: 1e-12)
        for t in 0..<6 {
            for d in [0.0, 26, 100] {
                let w = FxPicture.driveWave(type: t, drive: d)
                XCTAssertLessThanOrEqual(w.map { abs($0) }.max()!, 1.0000001, "type \(t) drive \(d)")
            }
        }
        // CRUSH 100 %: 3 бита — не больше 8 уровней.
        XCTAssertLessThanOrEqual(Set(FxPicture.driveWave(type: 5, drive: 100)).count, 8)
    }

    func testDuckCurve() {
        // Возврат как в FxDuck: на половине RELEASE громкость 1 − 0,5^q (CURVE 50 → 0,75; 100 → 0,293; 0 → 0,996).
        let cases: [(Double, Double)] = [(50, 0.75), (100, 0.293), (0, 0.996)]
        for (c, v) in cases {
            let d = FxPicture.duck(attack: 5, release: 200, curve: c)
            XCTAssertEqual(FxPicture.duckVolume(d, (d.a1 + d.r1) / 2), v, accuracy: 0.001)
        }
        let d = FxPicture.duck(attack: 100, release: 1000, curve: 50)
        XCTAssertLessThanOrEqual(d.r1, 1)
        XCTAssertEqual(FxPicture.duckVolume(d, d.a1), 0, accuracy: 1e-9)
        XCTAssertLessThan(FxPicture.duck(attack: 0.1, release: 10, curve: 50).a1, d.a1)
        XCTAssertEqual(FxPicture.duckDot(1.9), 0)
        XCTAssertEqual(FxPicture.duckDot(0.8), 0.5, accuracy: 1e-9)
    }
}

/// SETTINGS → APPEARANCE → FX ANIMATION: по умолчанию включено, сохраняется.
final class FxPictureSettingTests: XCTestCase {
    func testDefaultAndRoundTrip() {
        XCTAssertTrue(AppSettings().fxPictures)
        XCTAssertTrue(AppSettings.decode(Data("{}".utf8)).fxPictures)
        var s = AppSettings()
        s.fxPictures = false
        XCTAssertFalse(AppSettings.decode(s.encode()).fxPictures)
    }
}
