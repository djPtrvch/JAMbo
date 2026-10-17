import XCTest
@testable import Core

/// Синт на дорожке (#38): ключи «mi:<n>», сетка ручек движка.
final class SynthTests: XCTestCase {
    func testSynthKey() {
        XCTAssertEqual(SynthKey.key(6), "mi:6")
        XCTAssertEqual(SynthKey.engine("mi:0"), 0)
        XCTAssertEqual(SynthKey.engine("mi:7"), 7)
        XCTAssertEqual(SynthKey.engine("mi:15"), 15)
        XCTAssertEqual(SynthKey.engine("mi:19"), 19)
        XCTAssertNil(SynthKey.engine("mi:20"))
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
        // MI DRUMS: 11–15 — ручка 1.3 «OUT→AUX», затухают сами.
        XCTAssertEqual(Params.grid(sound: "mi:13")[0].label, "Attack & overdrive")
        XCTAssertEqual(Params.grid(sound: "mi:13")[8].label, "OUT→AUX")
        XCTAssertEqual(Params.grid(sound: "mi:8")[8].label, "Grain length")
        XCTAssertEqual(SynthEngines.all.filter(\.decay).map(\.name), ["STRING", "MODAL", "KICK", "SNARE", "HI-HAT", "DRUM"])
        // Свои движки: PITCH в Гц и Decay до 1000 мс у DRUM, WAVE ступенчатая у ANALOG, RATIO ×N.NN у FM.
        let drum = Params.grid(sound: "mi:16")
        XCTAssertEqual(drum[0].label, "Pitch")
        XCTAssertEqual(drum[0].format(50), "55 Hz")
        XCTAssertEqual(drum[5].id, "decay")
        XCTAssertEqual(drum[5].max, 1000)
        XCTAssertEqual(Params.grid(sound: "mi:17")[0].steps, 4)
        XCTAssertEqual(Params.grid(sound: "mi:17")[0].format(12.5), "Sine")
        XCTAssertEqual(Params.grid(sound: "mi:18")[0].format(25), "×1.00")
        XCTAssertEqual(Params.grid(sound: "mi:18")[5].max, Params.grid(sound: "")[5].max)
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

    /// Нагрузка MI DRUMS: 8 дорожек × 6 голосов движков 8–15 (Decay 4000 мс — звучат всю секунду).
    func testLoad48DrumVoices() throws {
        var p = Project()
        for t in 0..<8 {
            p.tracks[t].setSynth(8 + t)
            p.tracks[t].params["decay"] = 4000
        }
        let c = try core(p)
        for t in 0..<8 {
            for k in 0..<6 { c.events.push(.noteOn(track: t, note: 36 + k * 5, id: t * 10 + k, velocity: 1)) }
        }
        let t0 = Date()
        let x = render(c, frames: 48000)
        let load = Date().timeIntervalSince(t0)
        print(String(format: "drum load: 48 voices — %.1f%% of one core", load * 100))
        XCTAssertFalse(x.contains { !$0.isFinite })
    }

    // MARK: — MI DRUMS (#42)

    private func peak(_ x: [Float], _ from: Int, _ to: Int) -> Float {
        var m: Float = 0
        for i in from..<to { m = max(m, abs(x[i])) }
        return m
    }

    /// KICK затухает сам: живая нота держится, а звук гаснет по Decay; голос замолкает по тишине.
    func testKickDecaysWhileHeld() throws {
        let c = try core(synthProject(13, ["decay": 300]))
        c.events.push(.noteOn(track: 0, note: 36, id: 1, velocity: 1))
        let x = render(c, frames: 96000)
        let hit = peak(x, 0, 4800)
        XCTAssertGreaterThan(hit, 0.05)
        XCTAssertLessThan(peak(x, 72000, 96000), hit * 0.01, "клавиша держится, но бочка затухла")
        XCTAssertFalse(x.contains { !$0.isFinite })
        c.events.push(.noteOff(track: 0, id: 1))
        _ = render(c, frames: 24000)
        XCTAssertEqual(c.sampler.synth?.activeCount, 0)
    }

    /// Decay → Morph Plaits: длинный Decay — хвост громче.
    func testDecayKnobSetsLength() throws {
        func tail(_ decay: Double) throws -> Float {
            let c = try core(synthProject(13, ["decay": decay]))
            c.events.push(.noteOn(track: 0, note: 36, id: 1, velocity: 1))
            return rms(render(c, frames: 48000), 24000, 2400)
        }
        let short = try tail(100), long = try tail(4000)
        XCTAssertGreaterThan(long, short * 10)
    }

    /// Ручка 1.3 у KICK — OUT→AUX: 0 — бочка 808 (OUT), 100 — синтетическая (AUX); 50 — смесь.
    func testOutToAux() throws {
        func hit(_ morph: Double) throws -> [Float] {
            let c = try core(synthProject(13, ["morph": morph, "decay": 500]))
            c.events.push(.noteOn(track: 0, note: 36, id: 1, velocity: 1))
            return render(c, frames: 9600)
        }
        let out = try hit(0), aux = try hit(100), mix = try hit(50)
        XCTAssertGreaterThan(peak(out, 0, 9600), 0.05)
        XCTAssertGreaterThan(peak(aux, 0, 9600), 0.05)
        var diff: Float = 0, mixErr: Float = 0
        for i in 0..<9600 {
            diff = max(diff, abs(out[i] - aux[i]))
            mixErr = max(mixErr, abs(mix[i] - (out[i] + aux[i]) / 2))
        }
        XCTAssertGreaterThan(diff, 0.05, "OUT и AUX — разные бочки")
        XCTAssertLessThan(mixErr, 1e-3, "50 % — половина OUT и половина AUX")
    }

    /// Все MI DRUMS звучат и без NaN (ноты 36 и 60, ручки по умолчанию).
    func testAllDrumsSound() throws {
        for e in 8..<16 {
            for n in [36, 60] {
                let c = try core(synthProject(e))
                c.events.push(.noteOn(track: 0, note: n, id: 1, velocity: 1))
                let x = render(c, frames: 24000)
                XCTAssertFalse(x.contains { !$0.isFinite }, "\(SynthEngines.all[e].name) \(n)")
                XCTAssertGreaterThan(peak(x, 0, 24000), 0.01, "\(SynthEngines.all[e].name) \(n)")
            }
        }
    }

    // MARK: — свои движки (#43)

    /// ANALOG при выборе с другого звука — синус без DETUNE и SUB; DRUM подрезает Decay до 1000 мс.
    func testSetSynthInitAndDecayMax() {
        var t = Track(index: 0)
        t.params["harm"] = 80
        t.params["timbre"] = 70
        t.params["decay"] = 3000
        t.setSynth(17)
        XCTAssertEqual(t.params["harm"], 12.5)
        XCTAssertEqual(t.params["timbre"], 0)
        XCTAssertEqual(t.params["morph"], 0)
        t.params["harm"] = 60
        t.setSynth(17)
        XCTAssertEqual(t.params["harm"], 60, "тот же движок — ручки не сбрасываются")
        XCTAssertEqual(t.params["decay"], 3000)
        t.setSynth(16)
        XCTAssertEqual(t.params["decay"], 1000)
    }

    /// ANALOG, синус: A4 = 440 Гц с точностью до дрейфа (±3 цента).
    func testAnalogA4() throws {
        var p = synthProject(17)
        p.tracks[0].setSynth(17)
        let c = try core(p)
        c.events.push(.noteOn(track: 0, note: 69, id: 1, velocity: 1))
        let x = render(c, frames: 48000)
        var first = -1.0, last = -1.0, count = 0
        for i in 12000..<47999 where x[i] <= 0 && x[i + 1] > 0 {
            let t = Double(i) + Double(-x[i] / (x[i + 1] - x[i]))
            if first < 0 { first = t }
            last = t
            count += 1
        }
        let hz = Double(count - 1) / ((last - first) / 48000)
        XCTAssertEqual(hz, 440, accuracy: 440 * 0.0018)
    }

    /// DRUM монофонична: аккорд — один голос; все свои движки звучат и без NaN.
    func testJamboEnginesSound() throws {
        let c = try core(synthProject(16))
        let chord: [Int16] = [36, 40, 43]
        for (k, n) in chord.enumerated() { c.events.push(.noteOn(track: 0, note: Int(n), id: k + 1, velocity: 1)) }
        let x = render(c, frames: 4800)
        XCTAssertEqual(c.sampler.synth?.activeCount, 1)
        XCTAssertGreaterThan(peak(x, 0, 4800), 0.05)
        for e in [17, 18] {
            let c = try core(synthProject(e))
            c.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
            let y = render(c, frames: 9600)
            XCTAssertFalse(y.contains { !$0.isFinite }, "\(e)")
            XCTAssertGreaterThan(peak(y, 4800, 9600), 0.05, "\(e)")
        }
    }

    // MARK: — WTABLE (#44)

    /// WTABLE: без готовой таблицы молчит (как в вебе), с BASIC звучит; таблица — у дорожки.
    func testWavetableOnTrack() throws {
        var p = synthProject(19)
        XCTAssertEqual(p.tracks[0].table, "")
        let silent = try core(p)
        silent.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        XCTAssertLessThan(peak(render(silent, frames: 9600), 0, 9600), 1e-6)

        let basic = WtTable.builtin("BASIC")
        let c = AudioCore()
        c.installSynth(try XCTUnwrap(SynthTests.appResources))
        c.publish(p, tables: ["": basic])
        c.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let x = render(c, frames: 9600)
        XCTAssertFalse(x.contains { !$0.isFinite })
        XCTAssertGreaterThan(peak(x, 4800, 9600), 0.05)

        p.tracks[0].table = WavetableKey.builtin("METAL")
        XCTAssertEqual(p.tracks[0].table, "builtin:METAL")
        XCTAssertEqual(WavetableKey.name(p.tracks[0].table), "METAL")
        XCTAssertEqual(WavetableKey.name(""), "BASIC")
    }

    /// Кадр таблицы в окне синта: BASIC, POSITION 0 — синус (четверть периода — пик, y = 32 − 26).
    func testTableFrame() {
        let els = EngineIcons.tableFrame(WtTable.builtin("BASIC"), position: 0, warp: 0)
        XCTAssertEqual(els.count, 2)
        guard case .line(let x, let y) = els[1].cmds[32] else { return XCTFail("нет точки") }
        XCTAssertEqual(x, 18, accuracy: 1e-9)
        XCTAssertEqual(y, 6, accuracy: 0.05)
    }
}
