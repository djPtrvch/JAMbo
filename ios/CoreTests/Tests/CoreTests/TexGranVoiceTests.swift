import XCTest
@testable import Core

/// TEXTURE и GRANULAR в голосе синта (AudioCore): моно, стерео-выход, Pan — баланс, окно активности после отпускания.
final class TexGranVoiceTests: XCTestCase {
    func core(_ e: Int, _ params: [String: Double] = [:], edit: ((inout Project) -> Void)? = nil) -> AudioCore {
        var p = Project()
        p.tracks[0].setSynth(e)
        p.tracks[0].vol = 0
        for (k, v) in params { p.tracks[0].params[k] = v }
        edit?(&p)
        let c = AudioCore(master: false)
        c.installSynth()
        c.publish(p)
        return c
    }

    func render(_ c: AudioCore, frames: Int) -> ([Float], [Float]) {
        var l = [Float](repeating: 0, count: frames), r = [Float](repeating: 0, count: frames)
        var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < frames {
            let n = min(256, frames - pos)
            c.render(frames: n, left: &bl, right: &br)
            for i in 0..<n {
                l[pos + i] = bl[i]
                r[pos + i] = br[i]
            }
            pos += n
        }
        return (l, r)
    }

    func rms(_ x: [Float]) -> Double {
        var s = 0.0
        for v in x { s += Double(v) * Double(v) }
        return sqrt(s / Double(max(1, x.count)))
    }

    func testTable() {
        XCTAssertEqual(SynthEngines.engine(25)?.name, "TEXTURE")
        XCTAssertEqual(SynthEngines.engine(26)?.name, "GRANULAR")
        XCTAssertTrue(Jambo.mono(25) && Jambo.mono(26) && Jambo.stereo(25) && Jambo.stereo(26))
        XCTAssertFalse(Jambo.stereo(24))
        let g = Params.grid(sound: "mi:25")
        XCTAssertEqual(g[0].label, "Color")
        XCTAssertEqual(g[0].format(40), "white")
        XCTAssertEqual(g[4].format(50), "15 /s")
        XCTAssertEqual(g[8].format(30), "30%")
        let h = Params.grid(sound: "mi:26")
        XCTAssertEqual(h[4].label, "Size")
        XCTAssertEqual(h[4].format(0), "5ms")
        XCTAssertEqual(h[4].format(100), "500ms")
        XCTAssertEqual(h[8].format(55), "15 /s")
        var t = Project().tracks[0]
        t.setSynth(25)
        XCTAssertEqual(t.params["harm"], 40)
        XCTAssertEqual(t.params["p4"], 30)
        t.setSynth(26)
        XCTAssertEqual(t.params["harm"], 12)
        XCTAssertEqual(t.params["morph"], 55)
    }

    /// Аккорд — один голос; каналы различаются (панорама событий); NaN нет.
    func testTextureMonoStereo() {
        let c = core(Jambo.texture)
        for (k, n) in [57, 60, 64].enumerated() { c.events.push(.noteOn(track: 0, note: n, id: k + 1, velocity: 1)) }
        let (l, r) = render(c, frames: 48000)
        XCTAssertEqual(c.sampler.synth?.activeCount, 1)
        XCTAssertFalse(l.contains { !$0.isFinite } || r.contains { !$0.isFinite })
        XCTAssertGreaterThan(rms(l), 0.005)
        var diff = 0.0
        for i in 0..<l.count { diff += abs(Double(l[i] - r[i])) }
        XCTAssertGreaterThan(diff, 10)
    }

    /// Pan до упора влево — правый канал молчит (баланс стерео-входа); в центре — оба канала.
    func testTextureBalance() {
        let c = core(Jambo.texture, ["pan": -64])
        c.events.push(.noteOn(track: 0, note: 57, id: 1, velocity: 1))
        let (l, r) = render(c, frames: 24000)
        XCTAssertGreaterThan(rms(l), 0.005)
        XCTAssertLessThan(rms(r), 1e-6)
    }

    /// Отпустили: события ещё рождаются attack + 1,7·Decay, потом голос дозвучал и замолчал.
    func testTextureReleaseWindow() {
        let c = core(Jambo.texture, ["attack": 2, "decay": 200])
        c.events.push(.noteOn(track: 0, note: 57, id: 1, velocity: 1))
        _ = render(c, frames: 24000)
        c.events.push(.noteOff(track: 0, id: 1))
        _ = render(c, frames: 48000)
        XCTAssertEqual(c.sampler.synth?.activeCount, 0)
    }

    // MARK: — GRANULAR

    func coreWithSample(_ grain: String, samples: [String: SampleData]) -> AudioCore {
        var p = Project()
        p.tracks[0].setSynth(Jambo.granular)
        p.tracks[0].vol = 0
        p.tracks[0].grain = grain
        let c = AudioCore(master: false)
        c.installSynth()
        c.publish(p, samples: samples)
        return c
    }

    /// Со своим сэмплом — звучит (стерео), без него — тишина; NaN нет.
    func testGranularSource() {
        let demo = GranularEngineTests.demo
        let c = coreWithSample("demo", samples: ["demo": demo])
        c.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let (l, r) = render(c, frames: 48000)
        XCTAssertFalse(l.contains { !$0.isFinite } || r.contains { !$0.isFinite })
        XCTAssertGreaterThan(rms(l), 0.005)
        XCTAssertGreaterThan(rms(r), 0.005)
        let q = coreWithSample("", samples: ["demo": demo])
        q.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let (l2, _) = render(q, frames: 24000)
        XCTAssertLessThan(rms(l2), 1e-9)
        // Сэмпл есть в проекте, но не загружен — тоже тишина.
        let m = coreWithSample("missing", samples: [:])
        m.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        XCTAssertLessThan(rms(render(m, frames: 24000).0), 1e-9)
    }

    /// Сэмпл GRANULAR — в проекте (ключи сэмплов, файл), пресете и звуке клипа; прежние файлы без поля грузятся.
    func testGranularStorage() throws {
        var p = Project()
        p.tracks[0].setSynth(Jambo.granular)
        p.tracks[0].grain = "abc"
        XCTAssertTrue(p.sampleKeys.contains("abc"))
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(back.tracks[0].grain, "abc")
        let pr = p.tracks[0].preset(named: "G")
        XCTAssertEqual(pr?.grain, "abc")
        var t = Project().tracks[1]
        t.applyItem(FolderItem(preset: pr!))
        XCTAssertEqual(t.grain, "abc")
        XCTAssertEqual(SynthEngines.engine(SynthKey.engine(t.sample) ?? -1)?.name, "GRANULAR")
        let snd = p.tracks[0].sound
        XCTAssertEqual(snd.grain, "abc")
        XCTAssertEqual(try JSONDecoder().decode(TrackSound.self, from: JSONEncoder().encode(snd)), snd)
        // Звук без сэмпла GRANULAR — поле не пишется (как прежде), прежний звук без поля читается.
        let plain = Project().tracks[0].sound
        XCTAssertNil(plain.grain)
        let old = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("grain"))
        XCTAssertEqual(try JSONDecoder().decode(TrackSound.self, from: old), plain)
        // Пресет других движков — без сэмпла.
        var a = Project().tracks[0]
        a.setSynth(Jambo.texture)
        XCTAssertNil(a.preset(named: "T")?.grain)
    }

    // MARK: — нагрузка

    /// Цена голоса на плотном краю (TEXTURE DENSITY 1, GRANULAR DENSITY 1 и SIZE 1 с демо-сэмплом): время раздела
    /// Synth на блок 256; один голос и все 16 дорожек сразу. Печатает строки для отчёта.
    func testCost() {
        let blockUs: Double = 256.0 / 48000 * 1e6
        var lines: [String] = []
        for (e, k) in [(Jambo.texture, [40.0, 100, 0, 0]), (Jambo.texture, [40.0, 100, 100, 100]),
                       (Jambo.granular, [50.0, 100, 100, 50])] {
            for tracks in [1, 16] {
                var p = Project()
                while p.tracks.count < tracks { p.tracks.append(p.tracks[0]) }
                for t in 0..<tracks {
                    p.tracks[t].id = t + 1
                    p.tracks[t].setSynth(e)
                    p.tracks[t].grain = "demo"
                    for (j, id) in SynthEngines.knobIds.enumerated() { p.tracks[t].params[id] = k[j] }
                }
                let c = AudioCore(master: false)
                c.installSynth()
                c.publish(p, samples: ["demo": GranularEngineTests.demo])
                c.profile.enabled = true
                var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
                for t in 0..<tracks { c.events.push(.noteOn(track: t, note: 48, id: t + 1, velocity: 1)) }
                for _ in 0..<200 { c.render(frames: 256, left: &bl, right: &br) }
                guard let s = c.profile.read() else { return XCTFail("нет окна замера") }
                let us: Double = Double(s.avg[RenderProfile.synth]) * blockUs
                let name: String = SynthEngines.engine(e)!.name + " \(k.map { Int($0) })"
                lines.append(String(format: "  %@ × %d: synth %7.1f µs/блок (%5.2f%% ядра, на голос %5.2f%%)",
                                    name, tracks, us, us / blockUs * 100, us / blockUs * 100 / Double(tracks)))
            }
        }
        #if DEBUG
        let build = "debug"
        #else
        let build = "release"
        #endif
        print("TEXGRAN cost (\(build)):\n" + lines.joined(separator: "\n"))
    }

    // MARK: — иконки

    /// Сетка ручек (по 4 значения): без NaN, в поле 64×64; каждая ручка меняет иконку.
    func testIcons() {
        let knob: [Double] = [0, 1.0 / 3, 2.0 / 3, 1]
        for e in [Jambo.texture, Jambo.granular] {
            for h in knob { for t in knob { for m in knob { for q in knob {
                let els = EngineIcons.elements(e, IconValues(h: h, t: t, m: m, q: q))
                XCTAssertFalse(els.isEmpty)
                for el in els {
                    for r in el.rects {
                        XCTAssertTrue(r.x.isFinite && r.y.isFinite && r.w.isFinite && r.h.isFinite)
                        XCTAssertTrue(r.x >= 0 && r.y >= 0 && r.x + r.w <= 64.01 && r.y + r.h <= 64.01, "\(e) \(r)")
                    }
                    for y in el.wave + el.waveBot { XCTAssertTrue(y.isFinite && y >= 0 && y <= 64) }
                }
            } } } }
            func sig(_ v: IconValues) -> String {
                let els = EngineIcons.elements(e, v)
                return "\(els.map { $0.rects })\(els.map { $0.wave })"
            }
            let base = IconValues(h: 0.5, t: 0.5, m: 0.5, q: 0.5)
            for kp in [\IconValues.h, \IconValues.t, \IconValues.m, \IconValues.q] {
                var v = base
                v[keyPath: kp] = 0.9
                XCTAssertNotEqual(sig(v), sig(base), "\(e) \(kp)")
            }
        }
    }
}
