import XCTest
@testable import Core

/// Синт на дорожке (#38): ключи «mi:<n>», сетка ручек движка.
final class SynthTests: XCTestCase {
    func testSynthKey() {
        XCTAssertEqual(SynthKey.key(6), "mi:6")
        XCTAssertEqual(SynthKey.engine("mi:0"), 0)
        XCTAssertEqual(SynthKey.engine("mi:7"), 7)
        XCTAssertNil(SynthKey.engine("mi:8"))
        XCTAssertNil(SynthKey.engine("mi:x"))
        XCTAssertNil(SynthKey.engine(""))
        XCTAssertNil(SynthKey.engine("3f2a9c"))
    }

    func testSynthGrid() {
        let va = Params.grid(sound: "mi:0")
        XCTAssertEqual(va[0].id, "harm")
        XCTAssertEqual(va[0].label, "Detune")
        XCTAssertEqual(va[4].id, "timbre")
        XCTAssertEqual(va[4].label, "Pulse width")
        XCTAssertEqual(va[8].id, "morph")
        XCTAssertEqual(va[12].id, "level")
        XCTAssertEqual(va[1].id, "attack")
        XCTAssertEqual(Params.grid(sound: "")[0].id, "pitch")
        // CHORDS: Harmonics — 11 пунктов, значение — середина пункта.
        let ch = Params.grid(sound: "mi:6")[0]
        XCTAssertEqual(ch.steps, 11)
        XCTAssertEqual(ch.format(ch.fromNorm(0.4)), "m7")
        XCTAssertEqual(ch.fromNorm(0), 100.0 / 22, accuracy: 1e-9)
        XCTAssertEqual(Params.grid(sound: "mi:7")[0].format(50), "Phoneme")
    }

    func testDefaultsAndSetSynth() {
        var t = Track(index: 0)
        XCTAssertEqual(t.params["harm"], 50)
        XCTAssertEqual(t.params["morph"], 50)
        t.setSynth(3)
        XCTAssertEqual(t.sample, "mi:3")
        XCTAssertEqual(Params.grid(sound: t.sample)[0].label, "Formant ratio")
    }

    // MARK: — голоса синта (звук)

    /// Таблицы с a0 приложения (55/48000, без сдвига ноты).
    private static let appResources: PlaitsResources? = PlaitsResources.load(dir: PlaitsGolden.tablesDir)

    private func core(_ p: Project) throws -> AudioCore {
        let c = AudioCore()
        c.installSynth(try XCTUnwrap(SynthTests.appResources))
        c.publish(p)
        return c
    }

    /// Дорожка 1 — синт e, громкость 0 dB.
    private func synthProject(_ e: Int, _ params: [String: Double] = [:]) -> Project {
        var p = Project()
        p.tracks[0].setSynth(e)
        p.tracks[0].vol = 0
        for (k, v) in params { p.tracks[0].params[k] = v }
        return p
    }

    private func render(_ c: AudioCore, frames: Int) -> [Float] {
        var l = [Float](repeating: 0, count: frames)
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < frames {
            let n = min(256, frames - pos)
            c.render(frames: n, left: &bl, right: &br)
            for i in 0..<n { l[pos + i] = bl[i] }
            pos += n
        }
        return l
    }

    private func rms(_ x: [Float], _ center: Int, _ half: Int = 240) -> Float {
        var s: Float = 0
        for i in (center - half)..<(center + half) { s += x[i] * x[i] }
        return (s / Float(2 * half)).squareRoot()
    }

    /// Почти синус: ADDITIVE с одной гармоникой (центр — первая, крутизна наибольшая).
    private let sine: [String: Double] = ["harm": 0, "timbre": 0, "morph": 100]

    func testA4Is440() throws {
        let c = try core(synthProject(4, sine))
        c.events.push(.noteOn(track: 0, note: 69, id: 1, velocity: 1))
        let x = render(c, frames: 48000)
        // Частота по переходам через ноль (с интерполяцией) на 0,25…1 с.
        var first = -1.0, last = -1.0, count = 0
        for i in 12000..<47999 where x[i] <= 0 && x[i + 1] > 0 {
            let t = Double(i) + Double(-x[i] / (x[i + 1] - x[i]))
            if first < 0 { first = t }
            last = t
            count += 1
        }
        let hz = Double(count - 1) / ((last - first) / 48000)
        XCTAssertEqual(hz, 440, accuracy: 0.2)
        XCTAssertFalse(x.contains { !$0.isFinite })
    }

    func testAttackAndRelease() throws {
        let c = try core(synthProject(4, sine.merging(["attack": 200, "decay": 400]) { $1 }))
        c.events.push(.noteOn(track: 0, note: 60, id: 1, velocity: 1))
        var x = render(c, frames: 24000)
        let held = rms(x, 20000)
        XCTAssertGreaterThan(held, 0.05)
        // Атака 200 мс линейно: на 100 мс — половина.
        XCTAssertEqual(rms(x, 4800) / held, 0.5, accuracy: 0.06)
        c.events.push(.noteOff(track: 0, id: 1))
        x = render(c, frames: 48000)
        // Decay 400 мс как Release: τ = 100 мс.
        XCTAssertEqual(rms(x, 4800) / held, Float(exp(-1.0)), accuracy: 0.05)
        XCTAssertEqual(c.sampler.synth?.activeCount, 0, "после хвоста голос замолчал")
    }

    func testSeventhNoteSteals() throws {
        let c = try core(synthProject(0))
        for k in 0..<7 { c.events.push(.noteOn(track: 0, note: 48 + k, id: k + 1, velocity: 1)) }
        _ = render(c, frames: 4800)
        let s = try XCTUnwrap(c.sampler.synth)
        XCTAssertEqual(s.activeCount, 6)
        var notes: [Int] = []
        for v in 0..<SynthVoices.perTrack where s.active[v] != 0 { notes.append(s.note[v]) }
        XCTAssertEqual(notes.sorted(), [49, 50, 51, 52, 53, 54], "первую ноту украла седьмая")
    }

    func testStepNoteStopsAndStepSound() throws {
        // Дорожка без звука, у шага — свой звук «mi:2» (FM).
        var p = Project()
        p.tracks[0].vol = 0
        p.tracks[0].params["decay"] = 100
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [60]
        p.tracks[0].pages[0][0].sound = "mi:2"
        p.tracks[0].length = 64
        let c = try core(p)
        c.events.push(.play(true))
        let x = render(c, frames: 14000)
        XCTAssertGreaterThan(rms(x, 1200), 0.01, "свой звук шага — синт")
        XCTAssertEqual(c.sampler.synth?.activeCount, 0, "нота в 1 шаг: атака, Decay 100 мс, хвост 0,25 с — тишина")
        XCTAssertEqual(c.sampler.synth?.engine[0], 2)
    }

    func testEngineChangeRetriggersHeldNote() throws {
        var p = synthProject(0)
        let c = try core(p)
        c.events.push(.noteOn(track: 0, note: 57, id: 3, velocity: 1))
        _ = render(c, frames: 4800)
        p.tracks[0].setSynth(3)
        c.publish(p)
        let x = render(c, frames: 4800)
        let s = try XCTUnwrap(c.sampler.synth)
        var engines: [Int] = []
        for v in 0..<SynthVoices.perTrack where s.active[v] != 0 { engines.append(s.engine[v]) }
        XCTAssertEqual(engines, [3], "держащаяся нота звучит новым движком, прежний голос погас")
        XCTAssertGreaterThan(rms(x, 4000), 0.01)
    }

    func testMuteSilences() throws {
        var p = synthProject(1)
        let c = try core(p)
        c.events.push(.noteOn(track: 0, note: 60, id: 1, velocity: 1))
        _ = render(c, frames: 4800)
        p.tracks[0].mute = true
        c.publish(p)
        let x = render(c, frames: 4800)
        XCTAssertLessThan(rms(x, 4000), 1e-4)
    }

    /// Нагрузка: 8 дорожек × 6 голосов (живые ноты), 1 с звука; печатает долю реального времени.
    func testLoad48SynthVoices() throws {
        var p = Project()
        for t in 0..<8 { p.tracks[t].setSynth(t) }
        let c = try core(p)
        for t in 0..<8 {
            for k in 0..<6 { c.events.push(.noteOn(track: t, note: 48 + k * 3, id: t * 10 + k, velocity: 1)) }
        }
        let t0 = Date()
        let x = render(c, frames: 48000)
        let load = Date().timeIntervalSince(t0)
        print(String(format: "synth load: 48 voices — %.1f%% of one core", load * 100))
        XCTAssertEqual(c.sampler.synth?.activeCount, 48)
        XCTAssertFalse(x.contains { !$0.isFinite })
    }
}
