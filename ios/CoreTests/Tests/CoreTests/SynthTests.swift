import XCTest
@testable import Core

/// Синт на дорожке (#38): ключи «mi:<n>», сетка ручек движка.
final class SynthTests: XCTestCase {
    func testSynthKey() {
        XCTAssertEqual(SynthKey.key(17), "mi:17")
        // Движков Mutable Instruments (0–15) нет: такие ключи — не синт.
        XCTAssertNil(SynthKey.engine("mi:0"))
        XCTAssertNil(SynthKey.engine("mi:15"))
        XCTAssertTrue(SynthKey.isRemoved("mi:3"))
        XCTAssertFalse(SynthKey.isRemoved("mi:17"))
        XCTAssertFalse(SynthKey.isRemoved(""))
        XCTAssertEqual(SynthKey.engine("mi:16"), 16)
        XCTAssertEqual(SynthKey.engine("mi:19"), 19)
        XCTAssertEqual(SynthKey.engine("mi:20"), 20)
        XCTAssertNil(SynthKey.engine("mi:24"))
        XCTAssertNil(SynthKey.engine("mi:x"))
        XCTAssertNil(SynthKey.engine(""))
        XCTAssertNil(SynthKey.engine("3f2a9c"))
    }

    func testSynthGrid() {
        let an = Params.grid(sound: "mi:17")
        XCTAssertEqual(an[0].id, "harm")
        XCTAssertEqual(an[0].label, "Wave A")
        XCTAssertEqual(an[4].id, "timbre")
        XCTAssertEqual(an[4].label, "Wave B")
        XCTAssertEqual(an[4].steps, 4)
        XCTAssertEqual(an[8].id, "morph")
        XCTAssertEqual(an[8].label, "Detune")
        XCTAssertEqual(an[12].id, "p4")
        XCTAssertEqual(an[12].label, "Mix")
        XCTAssertEqual(Params.grid(sound: "mi:16")[12].label, "Click")
        XCTAssertEqual(Params.grid(sound: "mi:16")[8].label, "Drive")
        XCTAssertEqual(Params.grid(sound: "mi:18")[12].label, "Feedback")
        let wt = Params.grid(sound: "mi:19")
        XCTAssertEqual(wt[8].label, "Unison")
        XCTAssertEqual(wt[8].steps, 3)
        XCTAssertEqual(wt[8].format(50), "3")
        XCTAssertEqual(wt[12].label, "Detune")
        XCTAssertEqual(wt[12].format(50), "30 ct")
        XCTAssertEqual(an[15].id, "level")
        XCTAssertEqual(an[15].label, "Velocity")
        XCTAssertEqual(an[1].id, "attack")
        XCTAssertEqual(Params.grid(sound: "")[0].id, "pitch")
        XCTAssertEqual(Params.grid(sound: "mi:3")[0].id, "pitch", "звук без движка — не синт")
        XCTAssertEqual(SynthEngines.all.map(\.id), [16, 17, 18, 19, 20, 21, 22, 23])
        XCTAssertEqual(SynthEngines.count, 24)
        XCTAssertEqual(SynthEngines.all.filter(\.decay).map(\.name), ["KICK", "SNARE", "HAT", "CLAP", "PERC"])
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
        t.setSynth(18)
        XCTAssertEqual(t.sample, "mi:18")
        XCTAssertEqual(Params.grid(sound: t.sample)[0].label, "Ratio")
    }

    /// Проект и пресеты со звуками движков Mutable Instruments загружаются пустыми (S12); свои движки остаются.
    func testRemovedEnginesLoadEmpty() throws {
        var p = Project()
        p.tracks[0].sample = "mi:3"
        p.tracks[0].params["harm"] = 70
        p.tracks[1].sample = "mi:17"
        var st = Step()
        st.on = true
        st.notes = [60]
        st.sound = "mi:12"
        st.locks = ["harm": 20, "decay": 300]
        st.soundLocks = ["harm"]
        p.tracks[1].clips[0]!.pages[0][0] = st
        p.tracks[1].folder = Folder(items: [FolderItem(preset: SynthPreset(name: "Old", sound: "mi:5", params: [:])),
                                            FolderItem(preset: SynthPreset(name: "New", sound: "mi:18", params: [:]))])
        let data = try JSONEncoder().encode(p)
        var q = try JSONDecoder().decode(Project.self, from: data)
        q.repair()
        XCTAssertEqual(q.tracks[0].sample, "")
        XCTAssertEqual(q.tracks[0].params["harm"], 70, "ручки дорожки остаются")
        XCTAssertEqual(q.tracks[1].sample, "mi:17")
        let s0 = try XCTUnwrap(q.tracks[1].clips[0]?.pages[0][0])
        XCTAssertNil(s0.sound, "пресет-лок снят — шаг играет звук дорожки")
        XCTAssertNil(s0.soundLocks)
        XCTAssertEqual(s0.locks, ["decay": 300], "p-lock пресета сняты, ручной остался")
        XCTAssertEqual(q.tracks[1].folder.items.map { $0.preset?.sound }, ["", "mi:18"])
        var t = Track(index: 2)
        t.applyItem(FolderItem(sample: "mi:9"))
        XCTAssertEqual(t.sample, "", "прежняя папка: ключ без движка — пустой звук")
    }

    // MARK: — голоса синта (звук)

    private func core(_ p: Project) throws -> AudioCore {
        let c = AudioCore(master: false)
        c.installSynth()
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

    /// Синус: ANALOG по умолчанию (WAVE Sine, без DETUNE и SUB).
    private let sine: [String: Double] = [:]

    func testAttackAndRelease() throws {
        let c = try core(synthProject(17, sine.merging(["attack": 200, "decay": 400]) { $1 }))
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
        let c = try core(synthProject(17))
        for k in 0..<7 { c.events.push(.noteOn(track: 0, note: 48 + k, id: k + 1, velocity: 1)) }
        _ = render(c, frames: 4800)
        let s = try XCTUnwrap(c.sampler.synth)
        XCTAssertEqual(s.activeCount, 6)
        var notes: [Int] = []
        for v in 0..<SynthVoices.perTrack where s.active[v] != 0 { notes.append(s.note[v]) }
        XCTAssertEqual(notes.sorted(), [49, 50, 51, 52, 53, 54], "первую ноту украла седьмая")
    }

    func testStepNoteStopsAndStepSound() throws {
        // Дорожка без звука, у шага — свой звук «mi:18» (FM).
        var p = Project()
        p.tracks[0].vol = 0
        p.tracks[0].params["decay"] = 100
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [60]
        p.tracks[0].pages[0][0].sound = "mi:18"
        p.tracks[0].length = 64
        let c = try core(p)
        c.events.push(.play(true))
        let x = render(c, frames: 14000)
        XCTAssertGreaterThan(rms(x, 1200), 0.01, "свой звук шага — синт")
        XCTAssertEqual(c.sampler.synth?.activeCount, 0, "нота в 1 шаг: атака, Decay 100 мс, хвост 0,25 с — тишина")
        XCTAssertEqual(c.sampler.synth?.engine[0], 18)
    }

    /// Звук движка, которого нет (mi:3 — Mutable Instruments): тишина, голоса синта не заняты.
    func testRemovedEngineSilent() throws {
        var p = Project()
        p.tracks[0].vol = 0
        p.tracks[0].sample = "mi:3"
        let c = try core(p)
        c.events.push(.noteOn(track: 0, note: 60, id: 1, velocity: 1))
        let x = render(c, frames: 4800)
        XCTAssertEqual(c.sampler.synth?.activeCount, 0)
        XCTAssertLessThan(peak(x, 0, 4800), 1e-6)
    }

    func testEngineChangeRetriggersHeldNote() throws {
        var p = synthProject(17)
        let c = try core(p)
        c.events.push(.noteOn(track: 0, note: 57, id: 3, velocity: 1))
        _ = render(c, frames: 4800)
        p.tracks[0].setSynth(18)
        c.publish(p)
        let x = render(c, frames: 4800)
        let s = try XCTUnwrap(c.sampler.synth)
        var engines: [Int] = []
        for v in 0..<SynthVoices.perTrack where s.active[v] != 0 { engines.append(s.engine[v]) }
        XCTAssertEqual(engines, [18], "держащаяся нота звучит новым движком, прежний голос погас")
        XCTAssertGreaterThan(rms(x, 4000), 0.01)
    }

    func testMuteSilences() throws {
        var p = synthProject(18)
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
        // ANALOG и FM по очереди (WTABLE без таблицы молчит, DRUM монофонична).
        for t in 0..<8 { p.tracks[t].setSynth(t % 2 == 0 ? 17 : 18) }
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

    // MARK: — свои движки (#43)

    private func peak(_ x: [Float], _ from: Int, _ to: Int) -> Float {
        var m: Float = 0
        for i in from..<to { m = max(m, abs(x[i])) }
        return m
    }

    /// ANALOG при выборе с другого звука — синусы A и B без DETUNE, MIX 50 %; KICK подрезает Decay до 1000 мс.
    func testSetSynthInitAndDecayMax() {
        var t = Track(index: 0)
        t.params["harm"] = 80
        t.params["timbre"] = 70
        t.params["decay"] = 3000
        t.setSynth(17)
        XCTAssertEqual(t.params["harm"], 12.5)
        XCTAssertEqual(t.params["timbre"], 12.5)
        XCTAssertEqual(t.params["morph"], 0)
        XCTAssertEqual(t.params["p4"], 50)
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
        let c = AudioCore(master: false)
        c.installSynth()
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
