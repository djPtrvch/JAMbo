import XCTest
@testable import Core

final class SequencerTests: XCTestCase {
    /// Прогнать ядро на `frames` кадров блоками по block; вернуть левый канал и сообщения секвенсора.
    private func run(_ core: AudioCore, frames: Int, block: Int = 256) -> (audio: [Float], out: [SeqOut]) {
        var audio = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: block)
        var out: [SeqOut] = []
        var pos = 0
        while pos < frames {
            let n = min(block, frames - pos)
            audio.withUnsafeMutableBufferPointer { a in
                right.withUnsafeMutableBufferPointer { r in
                    core.render(frames: n, left: a.baseAddress! + pos, right: r.baseAddress!)
                }
            }
            while let e = core.sequencer.out.pop() { out.append(e) }
            pos += n
        }
        return (audio, out)
    }

    private func trigs(_ out: [SeqOut], track: Int = 0) -> [Int64] {
        return out.compactMap { if case .trig(let t, let f) = $0, t == track { return f } else { return nil } }
    }

    private func project(_ edit: (inout Project) -> Void) -> Project {
        var p = Project()
        edit(&p)
        return p
    }

    func testStepsAreSampleAccurate() {
        let core = AudioCore()
        core.publish(project { p in
            for s in stride(from: 0, to: 16, by: 4) { p.tracks[0].pages[0][s].on = true }
        })
        core.events.push(.play(true))
        let r = run(core, frames: 48000 * 2 + 100, block: 128)
        // 120 BPM: шаг 1/16 = 6000 кадров, триги на 0, 4, 8, 12, 16… → каждые 24000 кадров.
        XCTAssertEqual(trigs(r.out), [0, 24000, 48000, 72000, 96000])
    }

    func testMetronomeClickStartsOnBeat() {
        let core = AudioCore()
        core.publish(Project())
        core.events.push(.metronome(true))
        core.events.push(.play(true))
        let r = run(core, frames: 30000, block: 256)
        XCTAssertNotEqual(r.audio[1], 0, "первый щелчок — сразу")
        // Тишина: Delay, как в вебе, добавляет 1e-18 против денормалов (ниже −240 dB).
        XCTAssertEqual(r.audio[23999], 0, accuracy: 1e-12, "между щелчками тишина")
        XCTAssertNotEqual(r.audio[24001], 0, "вторая доля — ровно на 24000")
        // Акцент (начало такта) громче обычной доли.
        let first = r.audio[0..<200].map(abs).max()!
        let second = r.audio[24000..<24200].map(abs).max()!
        XCTAssertGreaterThan(first, second)
    }

    func testRatchetAndSwing() {
        let core = AudioCore()
        core.publish(project { p in
            p.tracks[0].pages[0][0].on = true
            p.tracks[0].pages[0][0].locks["ratchet"] = 3 // 4 удара
            p.tracks[0].pages[0][1].on = true
            p.tracks[0].params["swing"] = 75
        })
        core.events.push(.play(true))
        let r = run(core, frames: 12000)
        // Рэтчет 4 на шаге 0: через 1500; свинг 75 % — нечётный шаг позже на половину шага (3000).
        XCTAssertEqual(trigs(r.out), [0, 1500, 3000, 4500, 9000])
    }

    func testChanceZeroNeverPlays() {
        let core = AudioCore()
        core.publish(project { p in
            p.tracks[0].pages[0][0].on = true
            p.tracks[0].pages[0][0].locks["prob"] = 0
            p.tracks[1].pages[0][0].on = true
        })
        core.events.push(.play(true))
        let r = run(core, frames: 48000 * 4)
        XCTAssertEqual(trigs(r.out, track: 0).count, 0)
        XCTAssertEqual(trigs(r.out, track: 1).count, 2)
    }

    /// Смена темпа на ходу: новый темп — со следующего шага, доля не прыгает.
    func testTempoChangeKeepsPhase() {
        let core = AudioCore()
        core.publish(project { p in
            for s in 0..<16 { p.tracks[0].pages[0][s].on = true }
        })
        core.events.push(.play(true))
        var r = run(core, frames: 13000) // шаги 0, 1, 2 (на 0, 6000, 12000)
        XCTAssertEqual(trigs(r.out), [0, 6000, 12000])
        core.events.push(.tempo(60))
        r = run(core, frames: 24000)
        // Шаг 3 — через 6000 после шага 2 по прежнему темпу (он уже назначен), дальше — по 12000.
        XCTAssertEqual(trigs(r.out), [18000, 30000])
    }

    func testPatternLengthAndPages() {
        var t = Track(index: 0)
        t.pages = [Track.emptyPage(), Track.emptyPage(), Track.emptyPage()]
        t.playTo = 2
        t.length = 40
        XCTAssertEqual(t.playLen, 40)
        XCTAssertEqual(t.playIndex(39), 39)
        XCTAssertEqual(t.playIndex(40), 0)
        t.playTo = 1
        XCTAssertEqual(t.playLen, 32)
        t.playFrom = 2
        t.playTo = 2
        XCTAssertEqual(t.playLen, 8)
        XCTAssertEqual(t.playIndex(9), 33)
        XCTAssertTrue(t.outside(2 * 16 + 8))
        // Снимок для колбэка считает так же.
        var p = Project()
        p.tracks[0] = t
        let snap = SeqSnapshot(p)
        XCTAssertEqual(snap.data.playLen(0), 8)
        XCTAssertEqual(snap.data.playIndex(0, 9), 33)
    }

    func testStopClearsAndRestartsFromStepZero() {
        let core = AudioCore()
        core.publish(project { p in p.tracks[0].pages[0][0].on = true })
        core.events.push(.play(true))
        _ = run(core, frames: 10000)
        core.events.push(.play(false))
        let quiet = run(core, frames: 100000)
        XCTAssertEqual(trigs(quiet.out).count, 0)
        core.events.push(.play(true))
        let again = run(core, frames: 1000)
        XCTAssertEqual(trigs(again.out), [110000], "первый шаг — в первом кадре блока после PLAY")
    }

    func testSnapshotsAreReleased() {
        let before = SeqSnapshot.liveCount
        let core = AudioCore()
        for k in 0..<10 {
            var p = Project()
            p.tracks[0].pages[0][k].on = true
            core.publish(p)
            _ = run(core, frames: 256)
        }
        // Прежние снимки держатся keepAlive секунд (их сэмплы могут дочитывать гаснущие голоса).
        core.releaseRetired()
        XCTAssertGreaterThan(SeqSnapshot.liveCount - before, 1)
        core.releaseRetired(now: Date.timeIntervalSinceReferenceDate + 10)
        XCTAssertEqual(SeqSnapshot.liveCount - before, 1, "в памяти только текущий снимок")
        XCTAssertEqual(Params.noteName(48), "C3")
        XCTAssertEqual(Params.noteName(37), "C#2")
    }
}
