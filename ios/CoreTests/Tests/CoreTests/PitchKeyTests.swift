import XCTest
@testable import Core

/// Слежение ударных за нотами (14.11): C3 — высота ручки, другие ноты — на полутоны от неё; подпись «… Key».
final class PitchKeyTests: XCTestCase {
    private func hz(_ e: Int, _ n: Double) -> Double {
        if e == Jambo.drum { return Jambo.drumPitchMin * pow(Jambo.drumPitchMax / Jambo.drumPitchMin, n) }
        if e == Jambo.snare { return 120 * pow(400.0 / 120, n) }
        return Jambo.clapTone(n)
    }

    func testRelativeNotes() {
        let c3: Double = PitchKey.root
        XCTAssertEqual(PitchKey.knob(Jambo.drum, 0.37, note: c3), 0.37, "C3 — ручка как есть")
        let k: Double = hz(Jambo.drum, 0.5)
        XCTAssertEqual(hz(Jambo.drum, PitchKey.knob(Jambo.drum, 0.5, note: c3 + 12)), 2 * k, accuracy: 1e-9)
        XCTAssertEqual(hz(Jambo.snare, PitchKey.knob(Jambo.snare, 0.3, note: c3 - 7)), hz(Jambo.snare, 0.3) * pow(2, -7.0 / 12), accuracy: 1e-9)
        XCTAssertEqual(hz(Jambo.clap, PitchKey.knob(Jambo.clap, 0.5, note: c3 + 5)), hz(Jambo.clap, 0.5) * pow(2, 5.0 / 12), accuracy: 1e-6)
        XCTAssertEqual(PitchKey.knob(Jambo.hat, 0.5, note: c3 + 6), 0.75, accuracy: 1e-9, "TUNE ±1 октава")
        XCTAssertEqual(PitchKey.drumDefs[Jambo.drum]?.label, "Pitch Key")
        XCTAssertEqual(PitchKey.drumDefs[Jambo.drum]?.format(50), Params.synthGrids[Jambo.drum][0].format(50))
    }
}

/// Пресет синта с модуляцией (14.11): ручки LFO/ENV и назначения — в пресете и обратно на дорожку; старый пресет
/// модуляцию дорожки не трогает.
final class PresetModTests: XCTestCase {
    func testPresetKeepsModulation() throws {
        var t = Track(index: 0)
        t.setSynth(Jambo.analog)
        t.params["lfo1.speed"] = 3.5
        t.assigns["harm"] = ModAssign(lfo: 1, amount: 0.4)
        let p = t.preset(named: "Wobble")!
        XCTAssertEqual(p.mods?["lfo1.speed"], 3.5)
        XCTAssertEqual(p.assigns?["harm"]?.amount, 0.4)
        let back = try JSONDecoder().decode(SynthPreset.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        var u = Track(index: 1)
        u.applyItem(FolderItem(preset: back))
        XCTAssertEqual(u.params["lfo1.speed"], 3.5)
        XCTAssertEqual(u.assigns["harm"], ModAssign(lfo: 1, amount: 0.4))
        // Прежний пресет (без модуляции) — назначения дорожки остаются.
        u.applyItem(FolderItem(preset: SynthPreset(name: "Old", sound: "mi:17", params: ["harm": 12.5])))
        XCTAssertEqual(u.assigns["harm"]?.lfo, 1)
    }
}
