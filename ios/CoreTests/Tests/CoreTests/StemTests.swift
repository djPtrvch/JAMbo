import XCTest
@testable import Core

/// Запись стемов (S11d): начало с PLAY, конец на границах проходов — как stems.ts веба, с точностью до отсчёта.
final class StemTests: XCTestCase {
    /// Шаг при 120 BPM — 6000 кадров, клип в одну страницу — 16 шагов.
    private let step = 6000
    private let pass = 16 * 6000

    private struct Run {
        var l: [Float] = []
        var r: [Float] = []
        var stems: [Int: SampleData] = [:]
        var ended = false
    }

    private func run(_ core: AudioCore, _ col: StemCollector, frames: Int, into o: inout Run) {
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            o.l.append(contentsOf: bl[0..<n])
            o.r.append(contentsOf: br[0..<n])
            while let e = core.sequencer.out.pop() { if case .ended = e { o.ended = true } }
            for s in col.poll(core.sequencer.stemRing) {
                XCTAssertEqual(s.dropped, 0)
                XCTAssertNil(o.stems[s.channel], "стем канала — один")
                o.stems[s.channel] = s.data
            }
            pos += n
        }
    }

    /// Дорожка 0 — постоянный сигнал на шаге 0 (держится весь проход), громкость 0 dB.
    private func project(_ edit: (inout Project) -> Void = { _ in }) -> Project {
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [48]
        p.tracks[0].pages[0][0].len = 16
        edit(&p)
        return p
    }

    private func start(_ p: Project, master: Bool = false, arm: [Int]) -> AudioCore {
        let core = AudioCore(master: master)
        core.publish(p, samples: ["k": SampleData(left: [Float](repeating: 1, count: 48000 * 20), right: nil)])
        core.sequencer.stemRing.prepare()
        for c in arm { core.events.push(.stemArm(channel: c, on: true)) }
        core.events.push(.play(true))
        return core
    }

    func testTrackStemIsOnePassSampleAccurate() {
        let core = start(project(), arm: [0])
        var o = Run()
        run(core, StemCollector(), frames: pass * 3, into: &o)
        let s = try! XCTUnwrap(o.stems[0])
        XCTAssertEqual(s.frames, pass, "клип по кругу — один проход")
        // Одна дорожка без посылов и мастера: стем совпадает с выходом по отсчётам.
        var diff: Float = 0
        for i in 0..<pass { diff = max(diff, abs(s.left[i] - o.l[i]), abs(s.right[i] - o.r[i])) }
        XCTAssertLessThan(diff, 1e-6)
        XCTAssertGreaterThan(s.left[1000], 0.5)
        XCTAssertTrue(core.sequencer.playing, "запись кончилась — игра продолжается")
        XCTAssertNil(o.stems[1], "дорожка не готова — не пишется")
        XCTAssertNil(o.stems[StemRing.master])
    }

    func testMutedTrackStemIsSilent() {
        let core = start(project { $0.tracks[0].mute = true }, arm: [0])
        var o = Run()
        run(core, StemCollector(), frames: pass * 2, into: &o)
        let s = try! XCTUnwrap(o.stems[0])
        XCTAssertEqual(s.frames, pass)
        XCTAssertEqual(s.channel(0).map { abs($0) }.max() ?? 1, 0, accuracy: 1e-6, "стем — после mute/solo")
    }

    /// Строки по сетке: строка 0 — 3 повтора, строка 1 — 1; стем A, A, A, B — до места, где строки пошли по кругу.
    private func arranged() -> Project {
        return project { p in
            p.rows = 2
            p.rowLoop = false
            p.fillRows()
            p.scenes[0].repeats = 3
            p.scenes[1].repeats = 1
        }
    }

    func testArrangedRowsRecordAsPlayed() {
        let core = start(arranged(), arm: [0])
        var o = Run()
        run(core, StemCollector(), frames: pass * 6, into: &o)
        XCTAssertEqual(o.stems[0]?.frames, pass * 4)
        XCTAssertTrue(core.sequencer.playing)
    }

    func testLoopRowRecordsOnce() {
        let core = start(project { p in
            p.rows = 2
            p.fillRows()
            p.scenes[0].repeats = 3
        }, arm: [0])
        var o = Run()
        run(core, StemCollector(), frames: pass * 3, into: &o)
        XCTAssertEqual(o.stems[0]?.frames, pass, "LOOP ROW — строка по кругу пишется один раз")
    }

    func testTapDuringRecordingFinishesPass() {
        let core = start(arranged(), arm: [0])
        var o = Run()
        let col = StemCollector()
        run(core, col, frames: step * 3, into: &o)
        XCTAssertEqual(col.recording, [0])
        core.events.push(.stemFinish(channel: 0))
        run(core, col, frames: pass * 2, into: &o)
        XCTAssertEqual(o.stems[0]?.frames, pass, "дописан до конца прохода")
        XCTAssertTrue(core.sequencer.playing)
        XCTAssertFalse(core.sequencer.stemRules.armed[0], "готовность снята")
    }

    func testPlayDuringRecordingFinishesAndStops() {
        let core = start(arranged(), arm: [0])
        var o = Run()
        let col = StemCollector()
        run(core, col, frames: step * 3, into: &o)
        core.events.push(.stopAfterStems)
        run(core, col, frames: pass * 2, into: &o)
        XCTAssertEqual(o.stems[0]?.frames, pass)
        XCTAssertFalse(core.sequencer.playing)
        XCTAssertTrue(o.ended, "интерфейс узнаёт об остановке")
    }

    func testStopAfterStemsWithoutRecordingStopsAtOnce() {
        let core = start(project(), arm: [])
        var o = Run()
        run(core, StemCollector(), frames: step, into: &o)
        core.events.push(.stopAfterStems)
        run(core, StemCollector(), frames: 256, into: &o)
        XCTAssertFalse(core.sequencer.playing)
        XCTAssertTrue(o.ended)
    }

    func testStopEndsStemAtStopFrame() {
        let core = start(arranged(), arm: [0])
        var o = Run()
        let col = StemCollector()
        run(core, col, frames: 256 * 100, into: &o)
        core.events.push(.play(false))
        run(core, col, frames: 2560, into: &o)
        XCTAssertEqual(o.stems[0]?.frames, 256 * 100, "стоп — стем кончается в кадре остановки")
    }

    func testEndPredictionAtPassEnd() {
        let core = start(project(), arm: [0])
        var o = Run()
        let col = StemCollector()
        run(core, col, frames: step * 2, into: &o)
        XCTAssertEqual(col.endAt[0], Int64(pass), "конец стема виден — граница прохода")
    }

    func testMasterStemAllClipsSeen() {
        let core = start(project(), master: true, arm: [StemRing.master])
        var o = Run()
        run(core, StemCollector(), frames: pass * 3, into: &o)
        let s = try! XCTUnwrap(o.stems[StemRing.master])
        XCTAssertEqual(s.frames, pass, "все играющие клипы записаны — конец прохода")
        var diff: Float = 0
        for i in 0..<pass { diff = max(diff, abs(s.left[i] - o.l[i])) }
        XCTAssertLessThan(diff, 1e-6, "мастер — конечный выход")
    }

    func testMasterArrangedEndsAtWrap() {
        let core = start(arranged(), master: true, arm: [StemRing.master, 0])
        var o = Run()
        run(core, StemCollector(), frames: pass * 6, into: &o)
        XCTAssertEqual(o.stems[StemRing.master]?.frames, pass * 4)
        XCTAssertEqual(o.stems[0]?.frames, pass * 4)
    }

    /// Без строк: запущен другой клип (12 шагов) — стем A, B; дальше B по кругу — конец.
    func testQueuedClipRecordedThenEndsOnRepeat() {
        let core = start(project { p in
            p.tracks[0].clips[1] = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 28, playFrom: 1, playTo: 1)
        }, arm: [0])
        var o = Run()
        let col = StemCollector()
        run(core, col, frames: step * 3, into: &o)
        core.events.push(.launch(track: 0, slot: 1))
        run(core, col, frames: pass * 3, into: &o)
        XCTAssertEqual(o.stems[0]?.frames, pass + 12 * step)
    }

    func testStoppedTrackEndsStem() {
        let core = start(project(), arm: [0])
        var o = Run()
        let col = StemCollector()
        run(core, col, frames: step * 3, into: &o)
        core.events.push(.launch(track: 0, slot: Launcher.stop))
        run(core, col, frames: pass * 2, into: &o)
        XCTAssertEqual(o.stems[0]?.frames, pass, "дорожка остановилась на границе прохода — там же конец")
    }
}
