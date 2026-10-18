import XCTest
@testable import Core

/// Посылы дорожек, шины эффектов, Sidechain и p-lock FX играющих шагов (S4b).
final class FxRoutingTests: XCTestCase {
    private func render(_ core: AudioCore, frames: Int) -> (l: [Float], r: [Float]) {
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        var pos = 0
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            for i in 0..<n {
                l[pos + i] = bl[i]
                r[pos + i] = br[i]
            }
            pos += n
        }
        return (l, r)
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        let s = x.reduce(0.0) { $0 + Double($1) * Double($1) }
        return sqrt(s / Double(max(1, x.count)))
    }

    /// Шум 0,1 с (моно).
    private func burst() -> SampleData {
        var rnd = FxRandom(5)
        return SampleData(left: (0..<4800).map { _ in Float(rnd.next() * 2 - 1) * 0.5 }, right: nil)
    }

    private func project(sends: [String: Double]) -> Project {
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        for (id, v) in sends { p.tracks[0].params[id] = v }
        return p
    }

    /// Хвост после конца ноты есть только с посылом (Reverb, Delay, Drive — у Drive хвоста нет, зато сигнал громче).
    func testSendsReachEffects() {
        func tail(_ sends: [String: Double]) -> Double {
            let core = AudioCore(master: false)
            core.publish(project(sends: sends), samples: ["k": burst()])
            core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
            let o = render(core, frames: 30000)
            return rms(o.l[12000..<30000])
        }
        XCTAssertLessThan(tail([:]), 1e-6, "без посылов — тишина после ноты")
        XCTAssertGreaterThan(tail(["reverb": 100]), 1e-3, "хвост реверба")
        XCTAssertGreaterThan(tail(["delay": 100]), 1e-3, "повторы дилея (1/8 при 120 BPM — 0,25 с)")
    }

    /// Посылы — после громкости и mute: заглушённая дорожка в эффекты не посылает.
    func testMutedTrackDoesNotSend() {
        let core = AudioCore(master: false)
        var p = project(sends: ["reverb": 100])
        p.tracks[0].mute = true
        core.publish(p, samples: ["k": burst()])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 30000)
        XCTAssertLessThan(rms(o.l[0..<30000]), 1e-5)
    }

    /// MUTE TAILS (S9d): заглушили единственный источник Delay во время повтора — следующие повторы обрываются;
    /// без настройки — доигрывают.
    func testMuteTailsCutsDelayRepeats() {
        func second(_ cut: Bool) -> Double {
            let core = AudioCore(master: false)
            var p = project(sends: ["delay": 100])
            core.publish(p, samples: ["k": burst()], muteTails: cut)
            core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
            _ = render(core, frames: 12800)
            p.tracks[0].mute = true
            core.publish(p, samples: ["k": burst()], muteTails: cut)
            let o = render(core, frames: 20000)
            // Второй повтор — через 0,5 с после ноты (кадры 24000…28800 от начала).
            return rms(o.l[11200..<16000])
        }
        let ring = second(false)
        XCTAssertGreaterThan(ring, 1e-3, "без MUTE TAILS повторы доигрывают")
        XCTAssertLessThan(second(true), ring * 0.5)
    }

    /// Sidechain: нота источника (дорожка 1, заглушена) приглушает дорожку 2 и отпускает за RELEASE.
    func testSidechainDucksOtherTrack() {
        let core = AudioCore(master: false)
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].mute = true
        p.tracks[1].addSamples(["dc"])
        p.tracks[1].vol = 0
        p.tracks[1].params["sidechain"] = 100
        p.fx["sc.source"] = 0
        p.fx["sc.attack"] = 5
        p.fx["sc.release"] = 150
        core.publish(p, samples: ["k": burst(), "dc": SampleData(left: [Float](repeating: 1, count: 96000), right: nil)])
        core.events.push(.noteOn(track: 1, note: 48, id: 1, velocity: 1))
        var o = render(core, frames: 4800)
        let level = o.l[4700]
        XCTAssertGreaterThan(level, 0.5)
        core.events.push(.noteOn(track: 0, note: 48, id: 2, velocity: 1))
        o = render(core, frames: 9600 + 4800)
        // ATTACK 5 мс (240 кадров) — полное приглушение; через ATTACK + RELEASE (≈ 7440) — уровень вернулся.
        XCTAssertLessThan(o.l[400], level * 0.05, "приглушена")
        XCTAssertEqual(o.l[9000], level, accuracy: 0.01, "вернулась")
    }

    /// P-lock FX играющего шага (любой дорожки) действует на время шага.
    func testFxLockWhileStepPlays() {
        let core = AudioCore(master: false)
        var p = Project()
        p.tracks[0].pages[0][0].locks["rev.size"] = 10
        core.publish(p)
        core.events.push(.play(true))
        _ = render(core, frames: 512)
        XCTAssertEqual(core.fx.live[FxRack.revSize], 10, accuracy: 1e-6, "шаг 1 с p-lock")
        _ = render(core, frames: 6000)
        XCTAssertEqual(core.fx.live[FxRack.revSize], 40, accuracy: 1e-6, "шаг 2 — значение клипа (по умолчанию 40 %)")
        XCTAssertEqual(core.fx.live[FxRack.revHpf], Params.revHpfNew, accuracy: 1e-6, "новый проект — LOW CUT 120 Гц")
    }
}
