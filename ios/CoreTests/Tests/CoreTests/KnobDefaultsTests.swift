import XCTest
@testable import Core

/// Свои значения ручек по умолчанию: области, спутники, новый проект и дорожка.
final class KnobDefaultsTests: XCTestCase {
    func testApplyToProjectAndTrack() {
        var d = KnobDefaults()
        d.values[KnobDefaults.key("sampler", "filter")] = -40
        d.values[KnobDefaults.key("fx", "dly.feedback")] = 70
        d.values[KnobDefaults.key("mst", "sat.drive")] = 3
        d.values[KnobDefaults.key("mod", "lfo1.sync")] = 1
        var p = Project()
        d.apply(to: &p)
        XCTAssertEqual(p.tracks[0].params["filter"], -40)
        XCTAssertEqual(p.tracks[0].params["lfo1.sync"], 1)
        XCTAssertEqual(p.fx["dly.feedback"], 70)
        if Params.masterGrid.contains(where: { $0.id == "sat.drive" }) { XCTAssertEqual(p.master["sat.drive"], 3) }
        // У синта свои: значение сэмплера на него не переходит.
        var t = Track(index: 1)
        let e: Int = SynthEngines.byId.firstIndex { $0 != nil }!
        t.sample = "mi:\(e)"
        t.params["filter"] = 0
        d.apply(to: &t)
        XCTAssertNotNil(SynthKey.engine(t.sample))
        XCTAssertEqual(t.params["filter"], 0)
        let back = KnobDefaults.decode(d.encode())
        XCTAssertEqual(back, d)
        XCTAssertEqual(KnobDefaults.companion("dly.time"), "dly.sync")
        XCTAssertEqual(KnobDefaults.companion("lfo2.speed"), "lfo2.sync")
        XCTAssertNil(KnobDefaults.companion("filter"))
    }
}
