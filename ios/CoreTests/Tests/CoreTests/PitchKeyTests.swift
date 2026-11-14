import XCTest
@testable import Core

/// Pitch по нотам (14.11): шаг звучит своей нотой + сдвиг ручки (регистр движка), на ручке — нота.
final class PitchKeyTests: XCTestCase {
    private func hz(_ e: Int, _ n: Double) -> Double {
        if e == Jambo.drum { return Jambo.drumPitchMin * pow(Jambo.drumPitchMax / Jambo.drumPitchMin, n) }
        if e == Jambo.snare { return 120 * pow(400.0 / 120, n) }
        return Jambo.clapTone(n)
    }

    func testDrumNotes() {
        // Сдвиг 0 (ручка 50): SNARE на F3 — F3 (174,6 Гц), KICK — на 2 октавы ниже (F1), CLAP — на 3 выше (F6).
        let f3: Double = 53
        XCTAssertEqual(hz(Jambo.snare, PitchKey.knob(Jambo.snare, 0.5, note: f3)), 174.614, accuracy: 0.01)
        XCTAssertEqual(hz(Jambo.drum, PitchKey.knob(Jambo.drum, 0.5, note: f3)), 43.654, accuracy: 0.01)
        XCTAssertEqual(hz(Jambo.clap, PitchKey.knob(Jambo.clap, 0.5, note: f3)), 1396.91, accuracy: 0.1)
        // Ручка +12 полутонов (ход 0,48 полутона на единицу: 50 + 25) — октавой выше.
        XCTAssertEqual(hz(Jambo.snare, PitchKey.knob(Jambo.snare, 0.75, note: f3)), 349.228, accuracy: 0.01)
        // HAT: полутоны от C3, центр — C3.
        XCTAssertEqual(PitchKey.knob(Jambo.hat, 0.5, note: PitchKey.root), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PitchKey.knob(Jambo.hat, 0.5, note: PitchKey.root + 6), 0.75, accuracy: 1e-9)
    }

    func testLabels() {
        let kick: ParamDef = PitchKey.drumDefs[Jambo.drum]!
        XCTAssertEqual(kick.format(50), "C3", "сдвиг 0")
        XCTAssertEqual(kick.format(PitchKey.shifted(Jambo.drum, 50, note: 53)), "F3", "нота шага — как есть")
        XCTAssertEqual(kick.format(PitchKey.shifted(Jambo.drum, 75, note: 53)), "F4", "со сдвигом +12")
        XCTAssertEqual(PitchKey.sampleDef.format(0), "C3")
        XCTAssertEqual(PitchKey.sampleDef.format(PitchKey.shifted(nil, 0, note: 53)), "F3")
        XCTAssertEqual(PitchKey.snapped(Jambo.drum, 51), 50, accuracy: 1e-9)
        XCTAssertNotNil(PitchKey.drumDefs[Jambo.clap])
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
