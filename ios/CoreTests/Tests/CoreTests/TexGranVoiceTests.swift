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
        XCTAssertTrue(Jambo.mono(25) && !Jambo.mono(26) && Jambo.stereo(25) && Jambo.stereo(26))
        XCTAssertFalse(Jambo.stereo(24))
        let g = Params.grid(sound: "mi:25")
        XCTAssertEqual(g[0].label, "Color")
        XCTAssertEqual(g[0].format(40), "white")
        XCTAssertEqual(g[4].format(50), "15 /s")
        XCTAssertEqual(g[8].format(30), "30%")
        let h = Params.grid(sound: "mi:26")
        XCTAssertEqual(h[4].label, "Size")
        XCTAssertEqual(h[4].format(0), "10ms")
        XCTAssertEqual(h[4].format(100), "800ms")
        XCTAssertEqual(h[8].format(100), "×24.0")
        var t = Project().tracks[0]
        t.setSynth(25)
        XCTAssertEqual(t.params["harm"], 40)
        XCTAssertEqual(t.params["p4"], 30)
        t.setSynth(26)
        XCTAssertEqual(t.params["harm"], 8)
        XCTAssertEqual(t.params["timbre"], 62)
        XCTAssertEqual(t.params["morph"], 60)
        XCTAssertEqual(t.params["p4"], 25)
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

    /// GRANULAR полифоничен: аккорд — голос на ноту; каждая нота — своей высоты; после отпускания голоса дозвучали.
    func testGranularPoly() {
        let c = coreWithSample("pad", samples: ["pad": GranularEngineTests.pad])
        for (k, n) in [48, 51, 55].enumerated() { c.events.push(.noteOn(track: 0, note: n, id: k + 1, velocity: 1)) }
        let (l, r) = render(c, frames: 48000)
        XCTAssertEqual(c.sampler.synth?.activeCount, 3)
        XCTAssertFalse(l.contains { !$0.isFinite } || r.contains { !$0.isFinite })
        XCTAssertGreaterThan(rms(l), 0.005)
        for k in 1...3 { c.events.push(.noteOff(track: 0, id: k)) }
        _ = render(c, frames: 48000 * 8)
        XCTAssertEqual(c.sampler.synth?.activeCount, 0)
    }

    /// Уровень на выходе мастера (мастер по умолчанию): ручки по умолчанию, A3 удержана — RMS около 0,1 (±3 dB);
    /// DENSITY 1, SIZE 1, шесть нот (все голоса дорожки) — лимитер мастера не упирается (GR 0).
    func testGranularMasterLevel() {
        func run(_ k: [Double]?, notes: [Int]) -> (rms: Double, peak: Double, gr: Double) {
            var p = Project()
            p.tracks[0].setSynth(Jambo.granular)
            p.tracks[0].grain = "pad"
            if let k = k { for (j, id) in SynthEngines.knobIds.enumerated() { p.tracks[0].params[id] = k[j] } }
            let c = AudioCore(master: true)
            c.installSynth()
            c.publish(p, samples: ["pad": GranularEngineTests.pad])
            for (i, n) in notes.enumerated() { c.events.push(.noteOn(track: 0, note: n, id: i + 1, velocity: 1)) }
            _ = render(c, frames: 48000)
            var l: [Float] = [], r: [Float] = []
            var gr = 0.0
            for _ in 0..<(48000 * 4 / 256) {
                let (a, b) = render(c, frames: 256)
                l += a
                r += b
                gr = max(gr, Double(c.master.lim.frameGr))
            }
            let peak = Double(max(l.map { abs($0) }.max() ?? 0, r.map { abs($0) }.max() ?? 0))
            return ((rms(l) + rms(r)) / 2, peak, gr)
        }
        let d = run(nil, notes: [57])
        let dense = run([8, 100, 100, 25], notes: [57, 60, 62, 64, 67, 69])
        print(String(format: "GRANULAR master: default RMS %.3f (%.1f dBFS), peak %.2f, lim GR %.2f dB; dense ×6 RMS %.3f, peak %.3f, lim GR %.2f dB",
                     d.rms, 20 * log10(d.rms), d.peak, d.gr, dense.rms, dense.peak, dense.gr))
        XCTAssertLessThan(abs(20 * log10(d.rms / 0.1)), 3)
        XCTAssertLessThan(dense.gr, 0.01)
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
                       (Jambo.granular, [8.0, 100, 100, 25])] {
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

    /// Нагрузка GRANULAR по ТЗ: DENSITY 1, SIZE 1, пэд-источник, ноты держатся — 6 нот на одной дорожке (больше
    /// голосов у дорожки нет) и 8 нот на двух дорожках (по 4). Время раздела Synth на блок 256, % ядра и на ноту.
    func testGranularCost() {
        let blockUs: Double = 256.0 / 48000 * 1e6
        var lines: [String] = []
        for split in [[6], [4, 4]] {
            var p = Project()
            for (t, _) in split.enumerated() {
                p.tracks[t].setSynth(Jambo.granular)
                p.tracks[t].grain = "pad"
                for (j, id) in SynthEngines.knobIds.enumerated() { p.tracks[t].params[id] = [8.0, 100, 100, 25][j] }
            }
            let c = AudioCore(master: false)
            c.installSynth()
            c.publish(p, samples: ["pad": GranularEngineTests.pad])
            var id = 1
            for (t, n) in split.enumerated() {
                for k in 0..<n {
                    c.events.push(.noteOn(track: t, note: 57 + [0, 3, 5, 7, 10, 12][k], id: id, velocity: 1))
                    id += 1
                }
            }
            var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
            for _ in 0..<200 { c.render(frames: 256, left: &bl, right: &br) }
            c.profile.enabled = true
            for _ in 0..<400 { c.render(frames: 256, left: &bl, right: &br) }
            guard let s = c.profile.read() else { return XCTFail("нет окна замера") }
            let us: Double = Double(s.avg[RenderProfile.synth]) * blockUs
            let notes = split.reduce(0, +)
            lines.append(String(format: "  %d нот (%@): synth %7.1f µs/блок (%5.2f%% ядра, на ноту %5.2f%%), голосов %d",
                                notes, split.map { String($0) }.joined(separator: "+"), us, us / blockUs * 100,
                                us / blockUs * 100 / Double(notes), c.sampler.synth?.activeCount ?? 0))
        }
        #if DEBUG
        let build = "debug"
        #else
        let build = "release"
        #endif
        print("GRANULAR cost (\(build)):\n" + lines.joined(separator: "\n"))
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

    /// Фон иконки GRANULAR — огибающая настоящего сэмпла: громкая первая половина и тишина во второй видны на иконке.
    func testGranularIconFollowsSample() {
        let n = 48000
        let left: [Float] = (0..<n).map { i in i < n / 2 ? Float(sin(Double(i) * 0.05)) * 0.5 : 0 }
        let s = SampleData(left: left, right: nil)
        let peaks = EngineIcons.samplePeaks(s)
        XCTAssertEqual(peaks.count, 433)
        XCTAssertEqual(peaks.max() ?? 0, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(peaks[100], 0.9)
        XCTAssertEqual(peaks[400], 0)
        let v = IconValues(h: 0.1, t: 0.3, m: 0.5, q: 0.1)
        let real = EngineIcons.granularIcon(v, peaks: peaks)
        let fake = EngineIcons.granularIcon(v)
        XCTAssertNotEqual("\(real[0].rects)", "\(fake[0].rects)")
        // Серая волна (первый элемент): во второй половине поля столбиков почти нет высоты.
        let right = real[0].rects.filter { $0.x > 40 }
        XCTAssertLessThan(right.map { $0.h }.max() ?? 0, 1.0)
        let leftRects = real[0].rects.filter { $0.x < 25 }
        XCTAssertGreaterThan(leftRects.map { $0.h }.max() ?? 0, 30)
        XCTAssertEqual(EngineIcons.samplePeaks(SampleData(left: [Float](repeating: 0, count: 100), right: nil)).max(), 0)
    }
}
