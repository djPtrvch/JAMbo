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

    /// Выбор движка (SYNTH): ручки — по своим значениям этого движка, поверх начальных; тот же движок — без изменений.
    func testSetSynthUsesEngineDefaults() {
        let e: Int = SynthEngines.byId.firstIndex { $0 != nil }!
        let id: String = SynthEngines.knobIds[0]
        var d = KnobDefaults()
        d.values[KnobDefaults.key("synth\(e)", id)] = 77
        d.values[KnobDefaults.key("synth\(e)", "filter")] = -30
        var t = Track(index: 0)
        t.setSynth(e, defaults: d)
        XCTAssertEqual(t.params[id], 77)
        XCTAssertEqual(t.params["filter"], -30)
        t.params[id] = 10
        t.setSynth(e, defaults: d)
        XCTAssertEqual(t.params[id], 10, "тот же движок — ручки остаются")
        var u = Track(index: 1)
        u.setSynth(e)
        XCTAssertNotEqual(u.params[id], 77, "без своих значений — как прежде")
    }

    /// SAVE DEFAULT модуля мастера и EQ: параметры модуля вне сетки MST и полосы EQ — в NEW и ADD TRACK.
    func testModuleAndEqDefaults() throws {
        var d = KnobDefaults()
        XCTAssertTrue(d.isEmpty)
        d.values[KnobDefaults.key("mst", "cmp.knee")] = 9
        var bands = [EqBand?](repeating: nil, count: EqSpec.bands)
        bands[2] = EqBand(type: EqSpec.bell, freq: 300, gain: -3, q: 2)
        d.setEq(bands, master: true)
        d.setEq(bands, master: false)
        let back = KnobDefaults.decode(d.encode())
        XCTAssertEqual(back, d)
        XCTAssertEqual(KnobDefaults.decode(Data(#"{"values":{}}"#.utf8)).eqTrack, nil, "старый формат читается")
        var p = Project()
        back.apply(to: &p)
        XCTAssertEqual(p.master["cmp.knee"], 9)
        XCTAssertEqual(p.masterEq.bands[2]?.freq, 300)
        XCTAssertEqual(p.tracks.first?.eq.bands[2]?.gain, -3)
        var t = Track(index: 1)
        back.apply(to: &t)
        XCTAssertEqual(t.eq.bands[2]?.q, 2)
    }
}
