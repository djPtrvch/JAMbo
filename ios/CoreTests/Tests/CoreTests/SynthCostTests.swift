import XCTest
@testable import Core

/// S14b: цена голоса каждого движка синта — время раздела Synth (RenderProfile) на один звучащий голос, мкс на блок 256.
/// Аккорд из 6 нот, ноты повторяются каждые 50 мс (ударные и KICK затихают сами). Печатает таблицу; отладочная
/// (`swift test`) и релизная сборка (`swift test -c release -Xswiftc -enable-testing`).
final class SynthCostTests: XCTestCase {
    func testEngineVoiceCost() {
        var lines: [String] = []
        for e in SynthEngines.all {
            var p = Project()
            p.tracks[0].setSynth(e.id)
            let c = AudioCore(master: false)
            c.installSynth()
            c.publish(p, tables: ["": WtTable.builtin("BASIC")])
            c.profile.enabled = true
            var bl = [Float](repeating: 0, count: 256)
            var br = [Float](repeating: 0, count: 256)
            var voices = 0
            var blocks = 0
            var id = 1
            var k = 0
            while k < 200 {
                if k % 10 == 0 {
                    for n in 0..<6 {
                        c.events.push(.noteOn(track: 0, note: 48 + n * 3, id: id, velocity: 1))
                        id += 1
                    }
                }
                c.render(frames: 256, left: &bl, right: &br)
                // Окно замера — последние 188 блоков.
                if k >= 200 - 188 {
                    voices += c.sampler.synth?.activeCount ?? 0
                    blocks += 1
                }
                k += 1
            }
            guard let s = c.profile.read() else { return XCTFail("нет окна замера") }
            let avgVoices: Double = Double(voices) / Double(max(1, blocks))
            let blockUs: Double = 256.0 / 48000 * 1e6
            let synthUs: Double = Double(s.avg[RenderProfile.synth]) * blockUs
            let perVoice: Double = avgVoices > 0 ? synthUs / avgVoices : 0
            let name: String = e.name.padding(toLength: 7, withPad: " ", startingAt: 0)
            lines.append("  " + name + String(format: "voices %4.1f  synth %7.1f µs  per voice %6.1f µs (%4.2f%%)",
                                                avgVoices, synthUs, perVoice, perVoice / blockUs * 100))
            XCTAssertGreaterThan(avgVoices, 0, e.name)
        }
        #if DEBUG
        let build = "debug"
        #else
        let build = "release"
        #endif
        print("synth voice cost (\(build)), block 256 = 5333 µs:\n" + lines.joined(separator: "\n"))
    }
}
