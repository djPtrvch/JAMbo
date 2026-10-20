import XCTest
@testable import Core

/// S14a: «тяжёлый проект» — 8 дорожек (4 синта аккордами, 4 стерео-сэмпла на каждом шаге), посылы во все FX,
/// Sidechain, EQ с динамическими полосами на всех дорожках и мастере, весь мастер. Печатает время колбэка по разделам
/// (RenderProfile) — отладочная сборка (`swift test`) и релизная (`swift test -c release -Xswiftc -enable-testing`).
final class HeavyLoadTests: XCTestCase {
    static func heavyProject() -> Project {
        var p = Project()
        for t in 0..<8 {
            if t < 4 {
                // ANALOG и FM по очереди, аккорд из 4 нот длиной 4 шага на каждой доле.
                p.tracks[t].setSynth(t % 2 == 0 ? 17 : 18)
            } else {
                p.tracks[t].addSamples(["s\(t)"])
                p.tracks[t].params["decay"] = 2000
                p.tracks[t].params["filter"] = 30
                p.tracks[t].params["reso"] = 40
            }
            p.tracks[t].vol = -12
            p.tracks[t].params["reverb"] = 30
            p.tracks[t].params["delay"] = 25
            p.tracks[t].params["drive"] = 20
            if t != 4 { p.tracks[t].params["sidechain"] = 50 }
            var page: [Step] = Track.emptyPage()
            for s in 0..<16 {
                if t < 4 {
                    if s % 4 != 0 { continue }
                    page[s].on = true
                    page[s].len = 4
                    page[s].notes = [48 + t, 52 + t, 55 + t, 59 + t]
                } else {
                    page[s].on = true
                    page[s].notes = [48 + s % 5]
                }
            }
            p.tracks[t].pages = [page]
            // EQ: low cut, bell с источником (соседняя дорожка), high shelf.
            _ = p.addEqBand(t, freq: 80, gain: 0)
            let bell: Int = p.addEqBand(t, freq: 400 + Double(t) * 100, gain: -3)
            p.setEqDyn(t, bell, (t + 1) % 8 + 1)
            p.setEqDynParams(t, bell, thr: -40, range: -6)
            _ = p.addEqBand(t, freq: 8000, gain: 2)
        }
        p.fx["sc.source"] = 4
        let m: Int = EqSpec.masterChannel
        _ = p.addEqBand(m, freq: 60, gain: 1)
        let mb: Int = p.addEqBand(m, freq: 250, gain: -2)
        p.setEqDyn(m, mb, 5)
        p.setEqDynParams(m, mb, thr: -30, range: -4)
        _ = p.addEqBand(m, freq: 12000, gain: 1.5)
        p.master["sat.drive"] = 30
        p.master["cmp.threshold"] = -20
        p.master["clip.drive"] = 3
        p.master["lim.input"] = 3
        return p
    }

    /// Стерео-сэмпл 2 с: шум с огибающей и синус (разный у дорожек).
    static func sample(_ t: Int) -> SampleData {
        var rng: UInt32 = 0x1234_5678 &+ UInt32(t)
        var l = [Float](repeating: 0, count: 96000)
        var r = [Float](repeating: 0, count: 96000)
        for i in 0..<96000 {
            rng = rng &* 1_664_525 &+ 1_013_904_223
            let noise = Float(Int32(bitPattern: rng)) / Float(Int32.max)
            let env = Float(exp(-Double(i % 12000) / 3000))
            let tone = Float(sin(2 * Double.pi * Double(110 * (t - 2)) * Double(i) / 48000))
            l[i] = 0.4 * (noise * env + tone * 0.5)
            r[i] = 0.4 * (noise * env * 0.8 + tone * 0.5)
        }
        return SampleData(left: l, right: r)
    }

    func testHeavyProjectProfile() {
        let core = AudioCore()
        core.installSynth()
        var samples: [String: SampleData] = [:]
        for t in 4..<8 { samples["s\(t)"] = HeavyLoadTests.sample(t) }
        core.publish(HeavyLoadTests.heavyProject(), samples: samples)
        core.profile.enabled = true
        core.events.push(.play(true))
        let seconds = 4
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var finite = true
        let t0 = Date()
        var k = 0
        while k < seconds * 48000 / 256 {
            core.render(frames: 256, left: &bl, right: &br)
            if bl.contains(where: { !$0.isFinite }) || br.contains(where: { !$0.isFinite }) { finite = false }
            k += 1
        }
        let wall = Date().timeIntervalSince(t0)
        XCTAssertTrue(finite)
        XCTAssertGreaterThan(core.sampler.synth?.activeCount ?? 0, 8, "синты звучат")
        guard let s = core.profile.read() else { return XCTFail("нет окна замера") }
        XCTAssertEqual(s.blocks, 188, accuracy: 1, "окно — 1 с звука")
        let c = RenderProfile.count
        let sum: Float = s.avg[0..<c].reduce(0, +)
        XCTAssertEqual(sum, s.avg[c], accuracy: 1e-4, "разделы покрывают весь блок")
        #if DEBUG
        let build = "debug"
        #else
        let build = "release"
        #endif
        let realTime: Double = wall / Double(seconds) * 100
        var lines = ["heavy project (\(build)): " + String(format: "%.1f", realTime) + "% of real time over \(seconds) s"]
        let blockUs: Float = 256 / 48000 * 1e6
        for i in 0...c {
            let name = i < c ? RenderProfile.names[i] : "Total"
            let label: String = name.padding(toLength: 8, withPad: " ", startingAt: 0)
            lines.append("  " + label + String(format: "avg %5.1f%% (%6.1f µs)  peak %5.1f%%",
                                                 s.avg[i] * 100, s.avg[i] * blockUs, s.peak[i] * 100))
        }
        print(lines.joined(separator: "\n"))
    }

    /// Выключенный замер ничего не публикует; включённый — окно через 1 с звука.
    func testProfileOffAndOn() {
        let core = AudioCore(master: false)
        core.publish(Project())
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        for _ in 0..<200 { core.render(frames: 256, left: &bl, right: &br) }
        XCTAssertNil(core.profile.read())
        core.profile.enabled = true
        for _ in 0..<190 { core.render(frames: 256, left: &bl, right: &br) }
        let s = core.profile.read()
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.avg.count, RenderProfile.count + 1)
        XCTAssertGreaterThanOrEqual(s?.peak[RenderProfile.count] ?? -1, s?.avg[RenderProfile.count] ?? 0)
        XCTAssertGreaterThanOrEqual(s?.worst[RenderProfile.count] ?? -1, s?.peak[RenderProfile.count] ?? 0)
        // Сброс: наибольшее — заново, не больше пика окна, в котором он был.
        core.profile.resetWorst()
        for _ in 0..<190 { core.render(frames: 256, left: &bl, right: &br) }
        let r = core.profile.read()
        XCTAssertLessThanOrEqual(r?.worst[RenderProfile.count] ?? 1, (r?.peak[RenderProfile.count] ?? 0) + 1e-6)
    }
}
