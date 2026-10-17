import XCTest
@testable import Core

/// Голоса синта в ядре: звук слота Plaits через цепочку голоса (огибающая, Level, Pan, громкость микшера).
final class SynthTests: XCTestCase {
    private let center: Float = Float(cos(Double.pi / 4))

    private func render(_ core: AudioCore, frames: Int) -> (l: [Float], r: [Float]) {
        var l = [Float](repeating: 0, count: frames), r = [Float](repeating: 0, count: frames)
        var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            for i in 0..<n { l[pos + i] = bl[i]; r[pos + i] = br[i] }
            pos += n
        }
        return (l, r)
    }

    private func project(_ engine: Int) -> Project {
        var p = Project()
        p.tracks[0].sample = SynthEngines.key(engine)
        p.tracks[0].vol = 0
        p.tracks[0].params["decay"] = 4000
        return p
    }

    /// Живая нота: после атаки выход = голос Plaits (те же блоки) · cos(π/4) (ADDITIVE — фильтр 20 кГц в центре
    /// ручки Filter его почти не меняет).
    func testLiveNoteMatchesPlaitsVoice() {
        let core = AudioCore(plaits: PlaitsTests.lut)
        core.publish(project(4))
        core.events.push(.noteOn(track: 0, note: 57, id: 1, velocity: 1))
        let o = render(core, frames: 2560)
        let ref = PlaitsVoice(lut: PlaitsTests.lut)
        ref.set(engine: 4, note: 57 + PlaitsSelfTest.noteShift, harmonics: 0.5, timbre: 0.5, morph: 0.5, accent: 0.8, aux: 0)
        ref.trigger()
        var want = [Float]()
        for _ in 0..<10 {
            var pos = 0
            while pos < 256 {
                let m = min(24, 256 - pos)
                ref.render(m)
                ref.release()
                for i in 0..<m { want.append(ref.output[i]) }
                pos += m
            }
        }
        // Фильтр в центре ручки — LP 20 кГц: чуть сдвигает фазу верхних гармоник; уровень и форма те же.
        var xx = 0.0, yy = 0.0, xy = 0.0
        for i in 200..<2560 {
            let x = Double(o.l[i]), y = Double(want[i] * center)
            xx += x * x; yy += y * y; xy += x * y
        }
        XCTAssertEqual(10 * log10(xx / yy), 0, accuracy: 0.5, "уровень")
        XCTAssertGreaterThan(xy / (xx * yy).squareRoot(), 0.98, "форма")
        XCTAssertGreaterThan((xx / 2360).squareRoot(), 0.05, "звучит")
        XCTAssertEqual(o.l[10], o.r[10], accuracy: 1e-6, "по центру")
        XCTAssertLessThan(abs(o.l[24]), abs(want[24] * center) * 0.35, "атака 2 мс")
    }

    /// Седьмая нота при шести слотах: самый старый голос гаснет, новая нота — через 8 мс; NaN нет.
    func testSevenNotesStealSlot() {
        let core = AudioCore(plaits: PlaitsTests.lut)
        var p = project(2)
        p.tracks[0].params["decay"] = 200
        core.publish(p)
        for k in 0..<6 { core.events.push(.noteOn(track: 0, note: 48 + k * 2, id: k + 1, velocity: 1)) }
        _ = render(core, frames: 4800)
        XCTAssertEqual(core.sampler.activeCount, 6)
        core.events.push(.noteOn(track: 0, note: 72, id: 9, velocity: 1))
        let o = render(core, frames: 4800)
        XCTAssertEqual(core.sampler.activeCount, 6, "прежний голос слота замолчал")
        XCTAssertFalse(o.l.contains { !$0.isFinite })
        for k in 0..<6 { core.events.push(.noteOff(track: 0, id: k + 1)) }
        core.events.push(.noteOff(track: 0, id: 9))
        _ = render(core, frames: 48000)
        XCTAssertEqual(core.sampler.activeCount, 0, "после Decay голоса освобождаются")
    }

    /// Шаг секвенсора на синте: нота в 1 шаг — Decay сразу после атаки; p-lock Timbre шага действует.
    func testStepWithLock() {
        let core = AudioCore(plaits: PlaitsTests.lut)
        var p = project(4)
        p.tracks[0].params["decay"] = 100
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [60]
        p.tracks[0].pages[0][0].locks["timbre"] = 10
        core.publish(p)
        core.events.push(.play(true))
        let o = render(core, frames: 12000)
        let early = o.l[200..<1200].map { abs($0) }.max() ?? 0
        let late = o.l[11000..<12000].map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(early, 0.05)
        XCTAssertLessThan(late, early * 0.01, "Decay 100 мс: через 0,23 с почти тишина")
    }

    /// Смена движка на звучащей живой ноте: нота сразу звучит новым движком (прежний голос гаснет).
    func testEngineChangeRetriggers() {
        let core = AudioCore(plaits: PlaitsTests.lut)
        var p = project(0)
        core.publish(p)
        core.events.push(.noteOn(track: 0, note: 60, id: 1, velocity: 1))
        _ = render(core, frames: 2400)
        XCTAssertEqual(core.sampler.activeCount, 1)
        p.tracks[0].sample = SynthEngines.key(6)
        core.publish(p)
        _ = render(core, frames: 256)
        XCTAssertEqual(core.sampler.activeCount, 2, "прежний гаснет, новый звучит")
        _ = render(core, frames: 2400)
        XCTAssertEqual(core.sampler.activeCount, 1, "одна нота — новым движком")
    }

    /// SPEECH: ступенчатая 1.1 уходит в Plaits точкой пункта.
    func testSpeechHarmPoints() {
        XCTAssertEqual(SynthEngines.plaitsParams(7, harm: 16.7, timbre: 50, morph: 50, decayMs: 500).h, 0)
        XCTAssertEqual(SynthEngines.plaitsParams(7, harm: 50, timbre: 50, morph: 50, decayMs: 500).h, 1.0 / 6, accuracy: 1e-6)
        XCTAssertEqual(SynthEngines.plaitsParams(7, harm: 83.3, timbre: 50, morph: 50, decayMs: 500).h, 1.0 / 3, accuracy: 1e-6)
        let g = SynthEngines.grid(7)[0]
        XCTAssertEqual(g.fromNorm(0.9), 100.0 * 2.5 / 3, accuracy: 1e-9, "ручка встаёт на середину пункта")
        XCTAssertEqual(g.format(50), "Phoneme")
        XCTAssertEqual(Params.grid(sound: "mi:5")[0].label, "Bank")
        XCTAssertEqual(Params.grid(sound: "")[0].label, "Pitch")
    }
}
