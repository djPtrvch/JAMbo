import XCTest
@testable import Core

final class ArrangePlayTests: XCTestCase {
    /// Шаг при 120 BPM, 48 кГц — 6000 кадров.
    private let step = 6000

    private func run(_ core: AudioCore, steps: Int) -> [SeqOut] {
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        var out: [SeqOut] = []
        var pos = 0
        let frames = steps * step
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &l, right: &r)
            while let e = core.sequencer.out.pop() { out.append(e) }
            pos += n
        }
        return out
    }

    private func clips(_ out: [SeqOut], track: Int) -> [[Int]] {
        return out.compactMap {
            if case .clip(let t, let s, let st, let start) = $0, t == track { return [s, st ? 1 : 0, start] }
            return nil
        }
    }

    /// Позиции шагов дорожки (pos = p·16 + s), по тикам.
    private func steps(_ out: [SeqOut], track: Int) -> [Int] {
        return out.compactMap { if case .step(let t, let p) = $0, t == track { return p } else { return nil } }
    }

    private func cursor(_ out: [SeqOut]) -> [Int] {
        return out.compactMap { if case .arrange(let p) = $0 { return p } else { return nil } }
    }

    /// Дорожка 0: клип 0 — 16 шагов, клип 1 — 8 шагов; остальные дорожки пустые.
    private func project() -> Project {
        var p = Project()
        p.tracks[0].clips[1] = Clip(pages: [Track.emptyPage()], length: 8)
        for t in 1..<8 { p.tracks[t].clips[0] = nil }
        return p
    }

    private func start(_ p: Project, from: Int = 0) -> AudioCore {
        let core = AudioCore()
        core.publish(p)
        core.events.push(.arrange(on: true, from: from))
        core.events.push(.play(true))
        return core
    }

    func testBlocksPlayExactlyWithRepeatAndCut() {
        var p = project()
        // Клип 1 (8 шагов) с шага 4 длиной 12: повтор; клип 0 с шага 20 длиной 6: обрыв.
        p.tracks[0].placeBlock(ArrBlock(clip: 1, start: 4, length: 12))
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 20, length: 6))
        let out = run(start(p), steps: 30)
        XCTAssertEqual(clips(out, track: 0), [[0, 1, 0], [1, 0, 4], [1, 1, 16], [0, 0, 20]])
        let s = steps(out, track: 0)
        XCTAssertEqual(Array(s[4..<16]), [0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3], "клип с начала блока, по кругу")
        XCTAssertEqual(Array(s[16..<20]), [-1, -1, -1, -1], "между блоками — тишина")
        XCTAssertEqual(Array(s[20..<26]), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(s.count, 27, "на тике 26 (конец последнего блока) — стоп")
        XCTAssertEqual(s[26], -1)
    }

    func testStopsAtEndAndStartsFromCursor() {
        var p = project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 32))
        let out = run(start(p, from: 24), steps: 20)
        XCTAssertEqual(cursor(out).first, 24)
        XCTAssertEqual(steps(out, track: 0).first, 8, "с позиции курсора — середина клипа")
        XCTAssertTrue(out.contains { if case .ended = $0 { return true } else { return false } })
        XCTAssertEqual(cursor(out).last, 32, "стоп на конце последнего блока")
    }

    func testOffsetContinuesClip() {
        var p = project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 4, offset: 10))
        let out = run(start(p), steps: 4)
        XCTAssertEqual(Array(steps(out, track: 0).prefix(4)), [10, 11, 12, 13])
    }

    func testLoop() {
        var p = project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        p.setLoop(4, 8)
        p.arrange.loop = true
        let out = run(start(p), steps: 14)
        XCTAssertEqual(cursor(out).prefix(14).map { $0 }, [0, 1, 2, 3, 4, 5, 6, 7, 4, 5, 6, 7, 4, 5])
        XCTAssertEqual(Array(steps(out, track: 0).prefix(12)), [0, 1, 2, 3, 4, 5, 6, 7, 4, 5, 6, 7], "клип идёт за курсором")
        XCTAssertFalse(out.contains { if case .ended = $0 { return true } else { return false } })
    }

    func testGridClipLeavesTimelineAndReturn() {
        var p = project()
        p.tracks[1].clips[0] = Clip()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        p.tracks[1].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        let core = start(p)
        _ = run(core, steps: 4)
        // Клип 1 из сетки на дорожке 0: стартует в конце прохода клипа 0 (тик 16), дорожка уходит с таймлайна.
        core.events.push(.launch(track: 0, slot: 1))
        var out = run(core, steps: 20)
        XCTAssertTrue(out.contains { if case .follow(0, false) = $0 { return true } else { return false } })
        XCTAssertFalse(out.contains { if case .follow(1, false) = $0 { return true } else { return false } })
        XCTAssertEqual(clips(out, track: 0), [[1, 0, 16]])
        // Возврат к таймлайну — сразу, с позиции курсора (тик 24 → шаг 8 клипа 0).
        core.events.push(.returnToArrange(track: -1))
        out = run(core, steps: 2)
        XCTAssertTrue(out.contains { if case .follow(0, true) = $0 { return true } else { return false } })
        XCTAssertEqual(clips(out, track: 0).first?[0], 0)
        XCTAssertEqual(steps(out, track: 0).first, 8)
    }

    func testPatternsModeIgnoresTimeline() {
        var p = project()
        p.tracks[0].placeBlock(ArrBlock(clip: 1, start: 0, length: 4))
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        let out = run(core, steps: 20)
        XCTAssertEqual(steps(out, track: 0).prefix(16).map { $0 }, Array(0..<16), "сетка: клип 0 строки старта")
        XCTAssertFalse(out.contains { if case .ended = $0 { return true } else { return false } })
        XCTAssertEqual(cursor(out).prefix(3).map { $0 }, [0, 1, 2], "курсор идёт и в сетке")
    }

    func testLeaveArrangeKeepsClipsPlaying() {
        var p = project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 8))
        let core = start(p)
        _ = run(core, steps: 3)
        core.events.push(.leaveArrange)
        let out = run(core, steps: 16)
        XCTAssertTrue(out.contains { if case .follow(0, false) = $0 { return true } else { return false } })
        XCTAssertFalse(out.contains { if case .ended = $0 { return true } else { return false } }, "MIX: не стоп в конце")
        XCTAssertEqual(Array(steps(out, track: 0).prefix(6)), [3, 4, 5, 6, 7, 8], "клип играет дальше за концом блока")
    }

    func testSeekWhilePlaying() {
        var p = project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        let core = start(p, from: 20)
        _ = run(core, steps: 3)
        core.events.push(.seekArrange(0))
        let out = run(core, steps: 3)
        XCTAssertEqual(Array(cursor(out).prefix(3)), [0, 1, 2], "курсор — в начало со следующего шага")
        XCTAssertEqual(Array(steps(out, track: 0).prefix(3)), [0, 1, 2], "клип — с места курсора")
    }

    /// Автоматизация (S15f): значение кривой — вместо ручки, пока дорожка на таймлайне; рука и стоп — ручка.
    func testAutomationOverridesKnob() {
        var p = project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        p.tracks[0].setAuto("reverb", [ArrAutoPoint(x: 0, y: 0), ArrAutoPoint(x: 32, y: 1)])
        p.tracks[0].setAuto("prob", [ArrAutoPoint(x: 0, y: 0), ArrAutoPoint(x: 64, y: 0)])
        let core = start(p)
        let rv: Int = VoiceParam.reverb
        _ = run(core, steps: 16)
        let mid: Float = core.sampler.sound!.params[rv]
        XCTAssertEqual(mid, 50, accuracy: 2, "середина прямой 0…100 % на шаге 16")
        // Chance 0 на всей кривой — ни одного трига.
        let out = run(core, steps: 8)
        XCTAssertFalse(out.contains { if case .trig(0, _) = $0 { return true } else { return false } })
        core.events.push(.autoHold(track: 0, target: rv, on: true))
        _ = run(core, steps: 1)
        XCTAssertEqual(core.sampler.sound!.params[rv], 0, "палец на ручке — значение ручки")
        core.events.push(.autoHold(track: 0, target: rv, on: false))
        _ = run(core, steps: 1)
        XCTAssertGreaterThan(core.sampler.sound!.params[rv], 70)
        core.events.push(.play(false))
        _ = run(core, steps: 1)
        XCTAssertEqual(core.sampler.sound!.params[rv], 0, "стоп — значение ручки")
    }

    /// Дорожка играет сетку — кривая не действует.
    func testAutomationOnlyOnTimeline() {
        var p = project()
        p.tracks[0].setAuto("reverb", [ArrAutoPoint(x: 0, y: 1), ArrAutoPoint(x: 32, y: 1)])
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        _ = run(core, steps: 4)
        XCTAssertEqual(core.sampler.sound!.params[VoiceParam.reverb], 0)
    }

    func testLaneValue() {
        let l = ArrAutoLane(param: "filter", points: [ArrAutoPoint(x: 4, y: 0.2), ArrAutoPoint(x: 8, y: 1)])
        XCTAssertNil(l.value(at: 3.9))
        XCTAssertEqual(l.value(at: 6)!, 0.6, accuracy: 1e-9)
        XCTAssertNil(l.value(at: 8.1))
        var t = Track(index: 0)
        t.setAuto("filter", [ArrAutoPoint(x: 8, y: 2), ArrAutoPoint(x: 1, y: -1)])
        XCTAssertEqual(t.autos[0].points, [ArrAutoPoint(x: 1, y: 0), ArrAutoPoint(x: 8, y: 1)])
        t.setAuto("nope", [])
        XCTAssertEqual(t.autos.count, 1)
    }

    /// Запись ручки (S15f3): прямая упрощается до концов, кусок заменяет точки на своём участке.
    func testRecordAuto() {
        let line: [ArrAutoPoint] = (0...20).map { ArrAutoPoint(x: Double($0), y: Double($0) / 20) }
        XCTAssertEqual(ArrAutoLane.simplify(line, tol: 0.01).count, 2)
        let bend: [ArrAutoPoint] = [ArrAutoPoint(x: 0, y: 0), ArrAutoPoint(x: 1, y: 1), ArrAutoPoint(x: 2, y: 0)]
        XCTAssertEqual(ArrAutoLane.simplify(bend, tol: 0.01).count, 3)
        var t = Track(index: 0)
        t.setAuto("filter", [ArrAutoPoint(x: 0, y: 0.5), ArrAutoPoint(x: 8, y: 0.5), ArrAutoPoint(x: 32, y: 0.5)])
        t.recordAuto("filter", line.map { ArrAutoPoint(x: $0.x + 4, y: $0.y) })
        XCTAssertEqual(t.autos[0].points.map { $0.x }, [0, 4, 24, 32])
        t.recordAuto("pan", [ArrAutoPoint(x: 1, y: 0.2), ArrAutoPoint(x: 2, y: 0.3)])
        XCTAssertEqual(t.autos.count, 2)
    }
}
