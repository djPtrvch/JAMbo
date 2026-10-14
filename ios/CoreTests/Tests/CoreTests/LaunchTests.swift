import XCTest
@testable import Core

final class LaunchTests: XCTestCase {
    /// Прогнать ядро на frames кадров; сообщения секвенсора.
    private func run(_ core: AudioCore, frames: Int) -> [SeqOut] {
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        var out: [SeqOut] = []
        var pos = 0
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &l, right: &r)
            while let e = core.sequencer.out.pop() { out.append(e) }
            pos += n
        }
        return out
    }

    private func clips(_ out: [SeqOut], track: Int) -> [(slot: Int, stopped: Bool, start: Int)] {
        return out.compactMap { if case .clip(let t, let s, let st, let start) = $0, t == track { return (s, st, start) } else { return nil } }
    }

    private func scenes(_ out: [SeqOut]) -> [(row: Int, start: Int)] {
        return out.compactMap { if case .scene(let r, let s, _) = $0, r >= 0 { return (r, s) } else { return nil } }
    }

    /// Две ячейки у дорожки 0: клип 0 — страница 0 (длина паттерна 12), клип 1 — страница 1.
    private func project() -> Project {
        var p = Project()
        p.tracks[0].addPage()
        p.tracks[0].setPlayPages(0, 0)
        p.tracks[0].clips[1] = Clip(playFrom: 1, playTo: 1)
        p.tracks[0].length = 28 // страница 0 — 16, страница 1 — 12
        return p
    }

    func testQueuedClipStartsAtEndOfPass() {
        let core = AudioCore()
        core.publish(project())
        core.events.push(.play(true))
        _ = run(core, frames: 6000 * 3)
        core.events.push(.launch(track: 0, slot: 1))
        let out = run(core, frames: 6000 * 20)
        let c = clips(out, track: 0)
        XCTAssertEqual(c.first?.slot, 1)
        XCTAssertEqual(c.first?.start, 16, "клип 0 (16 шагов) доиграл — с тика 16")
        let steps: [Int] = out.compactMap { if case .step(0, let pos) = $0 { return pos } else { return nil } }
        XCTAssertTrue(steps.contains(16), "играет страница 1 (шаг 16)")
    }

    func testStoppedTrackStartsAtBar() {
        var p = project()
        p.tracks[0].stopped = true
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        _ = run(core, frames: 6000 * 5)
        core.events.push(.launch(track: 0, slot: 1))
        let out = run(core, frames: 6000 * 20)
        XCTAssertEqual(clips(out, track: 0).first?.start, 16, "остановленная — с начала такта")
    }

    func testQueueToggleCancelsAndStop() {
        let core = AudioCore()
        core.publish(project())
        core.events.push(.play(true))
        _ = run(core, frames: 6000)
        core.events.push(.launch(track: 0, slot: 1))
        core.events.push(.launch(track: 0, slot: 1)) // повторный тап — отмена
        var out = run(core, frames: 6000 * 20)
        XCTAssertTrue(clips(out, track: 0).isEmpty)
        core.events.push(.launch(track: 0, slot: Launcher.stop))
        out = run(core, frames: 6000 * 20)
        XCTAssertEqual(clips(out, track: 0).first?.stopped, true)
    }

    func testScenesWithRepeatsAndLoopToStart() {
        var p = project()
        p.rows = 2
        p.rowLoop = false
        p.scenes[0].repeats = 2
        p.fillRows()
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        let out = run(core, frames: 6000 * 70)
        let s = scenes(out)
        // Строка 0 — с тика 0 (строка старта), 2 прохода по 16 → строка 1 с 32 (её проход 16, 1 повтор) → снова 0 с 48.
        XCTAssertEqual(s.map { $0.row }, [0, 1, 0])
        XCTAssertEqual(s.map { $0.start }, [0, 32, 48])
    }

    func testAtTheEndStopEndsTransport() {
        var p = project()
        p.rows = 2
        p.rowLoop = false
        p.arrEndStop = true
        p.fillRows()
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        let out = run(core, frames: 6000 * 40)
        XCTAssertTrue(out.contains { if case .ended = $0 { return true } else { return false } })
        XCTAssertFalse(core.sequencer.playing)
    }

    func testLoopRowKeepsRow() {
        var p = project()
        p.rows = 2
        p.fillRows()
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        let out = run(core, frames: 6000 * 80)
        XCTAssertEqual(scenes(out).map { $0.row }, [0], "LOOP ROW — строка повторяется")
    }

    func testSceneTapStartsAtBarAndSwitchAtPass() {
        var p = project()
        p.rows = 3
        p.fillRows()
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        _ = run(core, frames: 6000 * 3)
        core.events.push(.scene(row: 2, atPass: false))
        var out = run(core, frames: 6000 * 20)
        XCTAssertEqual(scenes(out).first?.row, 2)
        XCTAssertEqual(scenes(out).first?.start, 16)
        core.events.push(.scene(row: 1, atPass: true))
        out = run(core, frames: 6000 * 40)
        let s = scenes(out).first
        XCTAssertEqual(s?.row, 1)
        XCTAssertEqual(s?.start, 32, "стрелки SWITCH — в конце прохода строки 2 (16 шагов)")
    }

    func testClipAndRowEdits() {
        var p = Project()
        p.rows = 3
        p.fillRows()
        XCTAssertTrue((0..<3).allSatisfy { k in p.tracks.allSatisfy { $0.clipFilled(k) } }, "пустых ячеек нет")
        XCTAssertEqual(p.tracks[0].pages.count, 3, "новые клипы — на новых пустых страницах")
        XCTAssertEqual(p.tracks[0].clips[2]?.playFrom, 2)
        p.tracks[1].stopped = true
        p.addRow()
        XCTAssertEqual(p.tracks[0].clips[3], p.tracks[0].clips[0], "COPY PLAYING — копия играющего клипа")
        XCTAssertEqual(p.tracks[1].clips[3]?.playFrom, 3, "остановленная — пустой паттерн")
        p.setScene(1, name: "  Chorus  ", repeats: 99)
        XCTAssertEqual(p.scenes[1], SceneRow(name: "Chorus", repeats: 64))
        p.duplicateRow(1)
        XCTAssertEqual(p.scenes[2].name, "Chorus")
        XCTAssertEqual(p.visibleRows, 5)
        p.tracks[0].activate(2)
        p.deleteRow(2)
        XCTAssertTrue(p.tracks[0].stopped, "дорожка, игравшая строку, остановлена")
        XCTAssertEqual(p.visibleRows, 4)
        XCTAssertEqual(p.sceneName(0), "1")
        var t = p.tracks[2]
        t.pages[t.clips[1]!.playFrom][0].on = true
        t.clearClip(1)
        XCTAssertFalse(t.pages[t.clips[1]!.playFrom][0].on)
        t.setPlayPages(0, 0)
        XCTAssertEqual(t.clips[t.slot]?.playTo, 0, "диапазон активного клипа — в его ячейке")
    }
}
