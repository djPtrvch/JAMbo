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

    /// Две ячейки у дорожки 0: клип 0 — одна страница (16 шагов), клип 1 — две страницы, играет вторая (12 шагов).
    private func project() -> Project {
        var p = Project()
        p.tracks[0].clips[1] = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 28, playFrom: 1, playTo: 1)
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

    /// PASTE дорожки: только настройки скопированной (звук, ручки, имя), клипы сетки и ход игры — свои.
    func testPasteTrackKeepsOwnPatterns() {
        var p = project()
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].sample = "kick"
        p.tracks[0].params["pan"] = 30
        p.tracks[0].name = "Kick"
        p.addTrack()
        p.tracks[8].pages[0][5].on = true
        let copy = p.tracks[0]
        p.pasteTrack(8, copy)
        let t = p.tracks[8]
        XCTAssertEqual(t.sample, "kick")
        XCTAssertEqual(t.params["pan"], 30)
        XCTAssertEqual(t.name, "Kick")
        XCTAssertTrue(t.pages[0][5].on, "свой паттерн остался")
        XCTAssertFalse(t.pages[0][0].on, "паттерн исходной не скопирован")
        XCTAssertEqual(t.clips[1]?.pages.count, 1, "клипы сетки — свои (у исходной в строке 2 — две страницы)")
        XCTAssertTrue(t.stopped, "ход игры — свой")
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
        XCTAssertTrue((0..<3).allSatisfy { k in p.tracks.allSatisfy { $0.clipFilled(k) } }, "пустых ячеек нет")
        XCTAssertEqual(p.tracks[0].clips[2]?.pages.count, 1, "новый клип — свой пустой паттерн")
        p.tracks[0].pages[0][0].on = true
        p.tracks[1].stopped = true
        p.addRow()
        XCTAssertEqual(p.tracks[0].clips[3], p.tracks[0].clips[0], "COPY PLAYING — копия играющего клипа")
        XCTAssertFalse(p.tracks[1].clips[3]!.pages[0][0].on, "остановленная — пустой паттерн")
        // Копия независима: правка копии не меняет исходный клип.
        p.tracks[0].open = 3
        p.tracks[0].pages[0][0].on = false
        p.tracks[0].pages[0][1].locks["pan"] = 10
        XCTAssertTrue(p.tracks[0].clips[0]!.pages[0][0].on)
        XCTAssertNil(p.tracks[0].clips[0]!.pages[0][1].locks["pan"], "p-lock — только в своём клипе")
        p.tracks[0].open = 0
        p.setScene(1, name: "  Chorus  ", repeats: 99)
        XCTAssertEqual(p.scenes[1], SceneRow(name: "Chorus", repeats: 64))
        p.duplicateRow(1)
        XCTAssertEqual(p.scenes[2].name, "Chorus")
        XCTAssertEqual(p.visibleRows, 5)
        p.tracks[0].activate(2)
        XCTAssertEqual(p.tracks[0].open, 2, "открытый идёт за активным")
        p.deleteRow(2)
        XCTAssertTrue(p.tracks[0].stopped, "дорожка, игравшая строку, остановлена")
        XCTAssertEqual(p.visibleRows, 4)
        XCTAssertEqual(p.sceneName(0), "1")
        // DELETE клипа очищает только его паттерн.
        var t = p.tracks[2]
        t.clips[1]!.pages[0][0].on = true
        t.clips[0]!.pages[0][0].on = true
        t.clearClip(1)
        XCTAssertFalse(t.clips[1]!.pages[0][0].on)
        XCTAssertTrue(t.clips[0]!.pages[0][0].on, "другие клипы столбца не тронуты")
    }

    /// Перенос строки: клипы, имя и повторы едут вместе, активные ячейки и строка старта — за своими строками.
    func testMoveRow() {
        var p = Project()
        p.rows = 4
        p.fillRows()
        for k in 0..<4 { p.tracks[0].clips[k]!.pages[0][k].on = true }
        p.setScene(0, name: "A", repeats: 2)
        p.setScene(3, name: "D", repeats: 1)
        p.tracks[0].activate(0)
        p.tracks[1].activate(2)
        p.arrStart = 3
        p.moveRow(0, to: 2)
        XCTAssertEqual(p.scenes[2], SceneRow(name: "A", repeats: 2))
        XCTAssertTrue(p.tracks[0].clips[2]!.pages[0][0].on, "клип строки A — на новом месте")
        XCTAssertTrue(p.tracks[0].clips[0]!.pages[0][1].on, "строки между сдвинулись вверх")
        XCTAssertEqual(p.tracks[0].slot, 2, "активная ячейка — за своей строкой")
        XCTAssertEqual(p.tracks[0].open, 2)
        XCTAssertEqual(p.tracks[1].slot, 1)
        XCTAssertEqual(p.arrStart, 3, "строка старта вне переноса — на месте")
        p.moveRow(3, to: 0)
        XCTAssertEqual(p.scenes[0].name, "D")
        XCTAssertEqual(p.arrStart, 0, "строка старта — за своей строкой")
        XCTAssertEqual(p.tracks[0].slot, 3)
        p.moveRow(1, to: 9)
        XCTAssertEqual(p.scenes[0].name, "D", "за пределы видимых строк — без изменений")
    }

    /// Перетаскивание в другой столбец переносит шаги, а не номера страниц.
    func testClipCopyAcrossTracksCarriesSteps() {
        var p = Project()
        p.tracks[3].pages[0][4].on = true
        p.tracks[3].pages[0][4].locks["filter"] = 20
        p.rows = 4
        p.fillRows()
        let c = p.tracks[3].clips[0]
        p.tracks[5].setClip(2, c)
        p.tracks[3].setClip(3, c)
        XCTAssertTrue(p.tracks[5].clips[2]!.pages[0][4].on)
        XCTAssertEqual(p.tracks[5].clips[2]!.pages[0][4].locks["filter"], 20)
        XCTAssertTrue(p.tracks[3].clips[3]!.pages[0][4].on, "вниз через строку — тоже")
        p.tracks[3].clearClip(0)
        XCTAssertTrue(p.tracks[3].clips[3]!.pages[0][4].on, "копия не очищается вместе с исходным")
    }

    /// Снимок: у каждого клипа свои шаги — запуск клипа 1 играет его триги, не клипа 0.
    func testLaunchedClipPlaysOwnSteps() {
        var p = Project()
        p.tracks[0].pages[0][0].on = true
        let c = Clip()
        p.tracks[0].clips[1] = c
        p.tracks[0].clips[1]!.pages[0][2].on = true
        p.arrStart = 1
        p.rows = 2
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        let out = run(core, frames: 6000 * 8)
        let trigs = out.compactMap { if case .trig(0, let f) = $0 { return f } else { return nil } }
        XCTAssertEqual(trigs.first, 12000, "триг клипа 1 на шаге 2 (6000 кадров на шаг)")
    }
}

extension LaunchTests {
    private func runMix(_ core: AudioCore, frames: Int) -> [SeqOut] {
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

    /// Переход MIX во время игры: клипы нового проекта и PREV запускаются тапом.
    func testLaunchesDuringMix() {
        let last = Params.patternSlots - 1
        var old = Project()
        for t in 0..<3 { old.tracks[t].clips[0]!.pages[0][0].on = true }
        old.tracks[2].stopped = true
        var next = Project()
        for t in 0..<8 { next.tracks[t].clips[0]!.pages[0][4].on = true }
        let core = AudioCore()
        core.publish(old)
        core.events.push(.play(true))
        _ = runMix(core, frames: 6000 * 5)
        let made = old.mixed(into: next, playing: true, leaving: [])
        core.publish(made.0)
        core.events.push(.adoptPlay)
        _ = runMix(core, frames: 6000 * 3)
        // Дорожка 0 (играет PREV) → клип 0; дорожка 2 (стоит в PREV) → PREV; дорожка 5 (без PREV) → клип 0.
        core.events.push(.launch(track: 0, slot: 0))
        core.events.push(.launch(track: 2, slot: last))
        core.events.push(.launch(track: 5, slot: 0))
        let out = runMix(core, frames: 6000 * 40)
        for (t, k) in [(0, 0), (2, last), (5, 0)] {
            let c = out.compactMap { e -> (Int, Bool)? in
                if case .clip(let tt, let s, let st, _) = e, tt == t { return (s, st) } else { return nil }
            }
            XCTAssertEqual(c.first?.0, k, "дорожка \(t)")
            XCTAssertEqual(c.first?.1, false, "дорожка \(t)")
        }
    }
}
