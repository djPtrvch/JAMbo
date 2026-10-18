import XCTest
@testable import Core

/// LFO1–3, ENV и назначения (S4c): формы, ADSR, модуляция голоса, Chance и FX.
final class ModTests: XCTestCase {
    private func render(_ core: AudioCore, frames: Int) -> (l: [Float], trigs: [Int64]) {
        var l = [Float](repeating: 0, count: frames)
        var trigs: [Int64] = []
        var pos = 0
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            for i in 0..<n { l[pos + i] = bl[i] }
            pos += n
            while let m = core.sequencer.out.pop() { if case .trig(_, let f) = m { trigs.append(f) } }
        }
        return (l, trigs)
    }

    func testShapes() {
        XCTAssertEqual(ModEngine.shape(0, 0.25, 0), 1, accuracy: 1e-12)
        XCTAssertEqual(ModEngine.shape(1, 0.5, 0), 0, accuracy: 1e-12)
        XCTAssertEqual(ModEngine.shape(1, 0.25, 0), 1, accuracy: 1e-12)
        XCTAssertEqual(ModEngine.shape(2, 0, 0), -1, accuracy: 1e-12)
        XCTAssertEqual(ModEngine.shape(3, 0.6, 0), -1, accuracy: 1e-12)
        XCTAssertEqual(ModEngine.shape(4, 0.3, 0.42), 0.42, accuracy: 1e-12)
    }

    /// ADSR: атака 10 мс, Decay 100 мс до Sustain 40 %, Release 300 мс от конца гейта.
    func testEnvelope() {
        let core = AudioCore()
        core.publish(Project())
        var bl = [Float](repeating: 0, count: 256), br = bl
        core.render(frames: 256, left: &bl, right: &br)
        let m = core.mod
        m.trig(track: 0, at: 1000, gate: 48000)
        XCTAssertEqual(m.env(0, 1000), 0, accuracy: 1e-9)
        XCTAssertEqual(m.env(0, 1240), 0.5, accuracy: 1e-9, "середина атаки (5 мс)")
        XCTAssertEqual(m.env(0, 1000 + 480 + 2400), 0.7, accuracy: 1e-9, "середина Decay")
        XCTAssertEqual(m.env(0, 1000 + 20000), 0.4, accuracy: 1e-9, "Sustain")
        XCTAssertEqual(m.env(0, 49000 + 7200), 0.2, accuracy: 1e-9, "середина Release")
        XCTAssertEqual(m.env(0, 49000 + 20000), 0, accuracy: 1e-9)
    }

    /// LFO1 (Square, 1 Гц) со степенью −1 на Level: первые 0,5 с нота молчит, затем звучит полностью.
    func testLfoOnLevel() {
        let core = AudioCore()
        var p = Project()
        p.tracks[0].addSamples(["dc"])
        p.tracks[0].vol = 0
        p.tracks[0].params["lfo1.wave"] = 3
        p.tracks[0].params["lfo1.speed"] = 1
        p.tracks[0].assigns["level"] = ModAssign(lfo: 1, amount: -1)
        core.publish(p, samples: ["dc": SampleData(left: [Float](repeating: 1, count: 96000), right: nil)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 48000)
        XCTAssertLessThan(abs(o.l[12000]), 0.01, "LFO +1 — Level 0")
        XCTAssertEqual(o.l[36000], Float(cos(Double.pi / 4)), accuracy: 0.01, "LFO −1 — Level 100 %")
    }

    /// LFO на Chance: пока выход +1 (степень −1) — шаги не играют.
    func testLfoOnChance() {
        let core = AudioCore()
        var p = Project()
        for s in 0..<16 { p.tracks[0].pages[0][s].on = true; p.tracks[0].pages[0][s].notes = [48] }
        p.tracks[0].params["lfo1.wave"] = 3
        p.tracks[0].params["lfo1.speed"] = 0.5
        p.tracks[0].assigns["prob"] = ModAssign(lfo: 1, amount: -1)
        core.publish(p)
        core.events.push(.play(true))
        let o = render(core, frames: 96000 * 2)
        XCTAssertTrue(o.trigs.allSatisfy { $0 >= 48000 }, "первая секунда (полпериода 0,5 Гц) — Chance 0")
        XCTAssertGreaterThan(o.trigs.count, 10)
    }

    /// LFO дорожки на ручке FX (Rev Size).
    func testLfoOnFx() {
        let core = AudioCore()
        var p = Project()
        p.tracks[0].params["lfo1.wave"] = 3
        p.tracks[0].params["lfo1.speed"] = 1
        p.fxAssigns["rev.size"] = ModAssign(lfo: 1, amount: -0.5, track: 0)
        core.publish(p)
        _ = render(core, frames: 4096)
        XCTAssertEqual(core.fx.live[FxRack.revSize], 0, accuracy: 1e-6, "50 % − 0,5 хода")
        _ = render(core, frames: 24000)
        XCTAssertEqual(core.fx.live[FxRack.revSize], 100, accuracy: 1e-6, "50 % + 0,5 хода")
    }

    /// ENV запускается нотой секвенсора; выход для интерфейса — в outs.
    func testEnvFromSequencer() {
        let core = AudioCore()
        var p = Project()
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [48]
        core.publish(p)
        core.events.push(.play(true))
        _ = render(core, frames: 512)
        XCTAssertGreaterThan(core.mod.outs[3].load(), 0.5, "атака 10 мс прошла наполовину и больше")
    }
}
