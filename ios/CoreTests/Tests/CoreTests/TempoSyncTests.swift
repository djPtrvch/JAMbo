import XCTest
@testable import Core

/// Dly Time и Speed LFO по темпу (SHIFT + тап), порядок FX, подписи Duck, случайное имя проекта.
final class TempoSyncTests: XCTestCase {
    func testFxOrderAndLabels() {
        XCTAssertEqual(Params.fxGrid[9].id, "dly.spread", "Spread — на месте Filter")
        XCTAssertEqual(Params.fxGrid[13].id, "dly.filter")
        XCTAssertEqual(Set(Params.fxIds), Set((Params.fxGrid + Params.hiddenFx).map { $0.id }))
        XCTAssertEqual(Params.fxIds.count, Params.fxCount)
        XCTAssertEqual(Params.fxIds[FxRack.dlyFilter], "dly.filter")
        XCTAssertEqual(Params.fxIds[FxRack.dlySpread], "dly.spread")
        XCTAssertEqual(Params.fxIds[FxRack.dlySync], "dly.sync")
        XCTAssertEqual(Params.fxIds[FxRack.scCurve], "sc.curve")
        XCTAssertEqual(Params.byId["sidechain"]?.label, "Duck")
        XCTAssertEqual(Params.byId["sc.attack"]?.label, "Duck Attack")
    }

    func testDelayFreeTime() {
        XCTAssertEqual(Params.dlyFreeMs(0), 10, accuracy: 1e-9)
        XCTAssertEqual(Params.dlyFreeMs(11), 2000, accuracy: 1e-6)
        XCTAssertEqual(Params.dlyFreeMs(Params.dlyFreeValue(ms: 375)), 375, accuracy: 1e-6)
        let quarter: Int = Params.delayDivs.firstIndex { $0.name == "1/4" }!
        XCTAssertEqual(Params.nearestDelayDiv(ms: 500, bpm: 120), quarter)
        XCTAssertEqual(Params.dlyTimeFree.format(Params.dlyFreeValue(ms: 250)), "250ms")
    }

    func testLfoDivIndex() {
        XCTAssertEqual(Params.lfoDivIndex(Params.lfoSpeedMin), 0)
        XCTAssertEqual(Params.lfoDivIndex(Params.lfoSpeedMax), Params.lfoDivs.count - 1)
        XCTAssertEqual(Params.lfoSpeedSync(1).format(Params.lfoSpeedMin), "8 bars")
    }

    /// LFO1 по темпу на пункте 1/4 при 120 BPM — 2 Гц: за 0,5 с фаза делает ровно один оборот.
    func testLfoSyncedRate() {
        let quarter: Int = Params.lfoDivs.firstIndex { $0.name == "1/4" }!
        let x: Double = Double(quarter) / Double(Params.lfoDivs.count - 1)
        let speed: Double = Params.lfoSpeedMin * pow(Params.lfoSpeedMax / Params.lfoSpeedMin, x)
        let core = AudioCore()
        var p = Project()
        p.bpm = 120
        p.tracks[0].params["lfo1.speed"] = speed
        p.tracks[0].params["lfo1.sync"] = 1
        core.publish(p)
        var bl = [Float](repeating: 0, count: 240), br = bl
        core.render(frames: 240, left: &bl, right: &br)
        let ph0: Double = Double(core.mod.phaseOuts[0].load())
        for _ in 0..<100 { core.render(frames: 240, left: &bl, right: &br) }
        let ph1: Double = Double(core.mod.phaseOuts[0].load())
        let d: Double = (ph1 - ph0 + 1).truncatingRemainder(dividingBy: 1)
        XCTAssertEqual(min(d, 1 - d), 0, accuracy: 1e-4, "24000 кадров при 2 Гц — целый оборот")
    }

    func testRandomName() {
        let a: String = ProjectSession.randomName([], seed: 7)
        XCTAssertEqual(a, ProjectSession.randomName([], seed: 7), "с seed — повторяемо")
        XCTAssertLessThanOrEqual(a.count, ProjectSession.nameLimit)
        XCTAssertTrue(a.contains(" "))
        let taken = [ProjectInfo(id: "x", name: a, updated: 0)]
        XCTAssertNotEqual(ProjectSession.randomName(taken, seed: 7), a, "занятое имя не предлагается")
        for w in ProjectSession.nameAdjectives {
            for n in ProjectSession.nameNouns { XCTAssertLessThanOrEqual("\(w) \(n)".count, ProjectSession.nameLimit) }
        }
    }
}
