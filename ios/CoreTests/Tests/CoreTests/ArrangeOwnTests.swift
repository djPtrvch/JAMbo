import XCTest
@testable import Core

/// Этап 1 (решение пользователя): у блока аранжировки своя копия клипа — сетка его не меняет, он — сетку.
final class ArrangeOwnTests: XCTestCase {
    private let step = 6000

    private func run(_ core: AudioCore, steps: Int) -> [SeqOut] {
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        var out: [SeqOut] = []
        var pos = 0
        while pos < steps * step {
            let n = min(256, steps * step - pos)
            core.render(frames: n, left: &l, right: &r)
            while let e = core.sequencer.out.pop() { out.append(e) }
            pos += n
        }
        return out
    }

    private func trigSteps(_ out: [SeqOut]) -> [Int] {
        // Позиция шага, на котором дорожка 0 сыграла триг (trig идёт за step).
        var cur: Int = -1
        var got: [Int] = []
        for e in out {
            if case .step(let t, let p) = e, t == 0 { cur = p }
            if case .trig(let t, _) = e, t == 0 { got.append(cur) }
        }
        return got
    }

    func testOwnCopyIgnoresGrid() {
        var p = Project()
        for t in 1..<8 { p.tracks[t].clips[0] = nil }
        var c = Clip(pages: [Track.emptyPage()], length: 16)
        c.pages[0][0].on = true
        c.pages[0][8].on = true
        p.tracks[0].clips[0] = c
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        XCTAssertTrue(p.ownArrPatterns())
        XCTAssertFalse(p.ownArrPatterns(), "второй раз — уже копии")
        XCTAssertEqual(p.tracks[0].blocks[0].pattern, c)
        // Правка клипа в сетке — блок играет свою копию (триги на 0 и 8, не на 4).
        p.tracks[0].clips[0]!.pages[0][0].on = false
        p.tracks[0].clips[0]!.pages[0][4].on = true
        let core = AudioCore()
        core.publish(p)
        core.events.push(.arrange(on: true, from: 0))
        core.events.push(.play(true))
        let out = run(core, steps: 15)
        XCTAssertEqual(trigSteps(out), [0, 8])
        let cells: [Int] = out.compactMap { if case .clip(let t, let s, _, _) = $0, t == 0 { return s } else { return nil } }
        XCTAssertTrue(cells.contains(SeqData.slots), "ячейка блока — после ячеек сетки")
    }

    func testSplitKeepsCopy() {
        var t = Track(index: 0)
        var c = Clip()
        c.pages[0][3].on = true
        t.blocks = [ArrBlock(clip: 0, start: 0, length: 32, pattern: c)]
        t.splitArrange(at: 16)
        XCTAssertEqual(t.blocks.count, 2)
        XCTAssertEqual(t.blocks[1].pattern, c, "правая часть — та же копия")
    }

    func testCodingKeepsPattern() throws {
        var c = Clip()
        c.pages[0][5].on = true
        let b = ArrBlock(clip: 2, start: 16, length: 16, pattern: c)
        let back = try JSONDecoder().decode(ArrBlock.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(back, b)
    }
}

/// Этап 2: запись «по факту» — в блок попадают шаги, которые звучали; не прошедший Chance — без трига, прошедший —
/// Chance 100 %; длинный отрезок — блоками по 128 шагов.
final class ArrangeFiredTests: XCTestCase {
    func testFiredSteps() {
        var p = Project()
        var c = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 32, playFrom: 0, playTo: 0)
        c.pages[0][0].on = true
        c.pages[0][4].on = true
        c.pages[0][4].locks["prob"] = 50
        c.pages[1][0].on = true
        p.tracks[0].clips[0] = c
        // Таймлайн 0…15 — страница 1 (шаги 0…15), 16…19 — переключили на страницу 2 (шаги 16…19).
        var played: [Int: Int] = [:]
        for x in 0..<16 { played[x] = x }
        for x in 16..<20 { played[x] = 16 + (x - 16) }
        let fired: Set<Int> = [0, 16]
        let seg = ArrRecorder.Seg(track: 0, slot: 0, start: 0, end: 20, offset: 0)
        var pp: [[Int: Int]] = [[Int: Int]](repeating: [:], count: Params.maxTracks)
        var ff: [Set<Int>] = [Set<Int>](repeating: [], count: Params.maxTracks)
        pp[0] = played
        ff[0] = fired
        p.applyRecording([seg], played: pp, fired: ff)
        XCTAssertEqual(p.tracks[0].blocks.count, 1)
        let b: ArrBlock = p.tracks[0].blocks[0]
        let own: Clip = try! XCTUnwrap(b.pattern)
        XCTAssertEqual(own.length, 20)
        XCTAssertTrue(own.pages[0][0].on)
        XCTAssertFalse(own.pages[0][4].on, "Chance не прошёл — без трига")
        XCTAssertTrue(own.pages[1][0].on, "страница 2 — как играли")
        // Прошедший шаг с p-lock Chance — 100.
        var c2 = c
        c2.pages[0][0].locks["prob"] = 30
        p.tracks[0].clips[0] = c2
        p.tracks[0].blocks = []
        p.applyRecording([seg], played: pp, fired: ff)
        XCTAssertEqual(p.tracks[0].blocks[0].pattern?.pages[0][0].locks["prob"], 100)
    }

    func testLongSplitsIntoBlocks() {
        var p = Project()
        var c = Clip()
        c.pages[0][0].on = true
        p.tracks[0].clips[0] = c
        var pp: [[Int: Int]] = [[Int: Int]](repeating: [:], count: Params.maxTracks)
        for x in 0..<300 { pp[0][x] = x % 16 }
        let ff: [Set<Int>] = [Set<Int>](repeating: Set((0..<300).filter { $0 % 16 == 0 }), count: Params.maxTracks)
        p.applyRecording([ArrRecorder.Seg(track: 0, slot: 0, start: 0, end: 300, offset: 0)], played: pp, fired: ff)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.length }, [128, 128, 44])
        XCTAssertEqual(p.tracks[0].blocks.map { $0.start }, [0, 128, 256])
        XCTAssertTrue(p.tracks[0].blocks[2].pattern!.pages[0][0].on)
    }
}

/// Колбэк сообщает о шагах, прошедших Chance (fired), — только о них.
final class FiredOutTests: XCTestCase {
    func testFiredOnlyWhenChancePasses() {
        var p = Project()
        for t in 1..<8 { p.tracks[t].clips[0] = nil }
        var c = Clip()
        c.pages[0][0].on = true
        c.pages[0][2].on = true
        c.pages[0][2].locks["prob"] = 0
        p.tracks[0].clips[0] = c
        let core = AudioCore()
        core.publish(p)
        core.events.push(.play(true))
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        var got: [Int] = []
        var pos = 0
        while pos < 6000 * 4 {
            core.render(frames: 256, left: &l, right: &r)
            while let e = core.sequencer.out.pop() {
                if case .fired(let t, let s) = e, t == 0 { got.append(s) }
            }
            pos += 256
        }
        XCTAssertEqual(got, [0], "шаг 2 с Chance 0 % — не сработал")
    }
}

/// Этап 3: STEPS аранжировщика правит копию блока, сетка не меняется.
final class ArrangeEditBlockTests: XCTestCase {
    func testEditBlockCopy() throws {
        var t = Track(index: 0)
        t.blocks = [ArrBlock(clip: 0, start: 0, length: 16, pattern: Clip())]
        t.editBlock = 0
        t.toggleStep(3, notes: [36])
        XCTAssertTrue(try XCTUnwrap(t.blocks[0].pattern).pages[0][3].on, "шаг — в копии блока")
        XCTAssertFalse(t.clips[0]!.pages[0][3].on, "сетка — без изменений")
        XCTAssertTrue(t.pages[0][3].on, "секвенсор видит копию")
        t.editBlock = nil
        XCTAssertFalse(t.pages[0][3].on, "вне аранжировщика — клип сетки")
        // Номер вне блоков — клип сетки.
        t.editBlock = 5
        XCTAssertFalse(t.pages[0][3].on)
        // Копия в файл не пишется.
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(t))
        XCTAssertNil(back.editBlock)
    }
}
