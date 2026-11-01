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
        c.pages[0][4].locks["filter"] = 40
        c.pages[0][4].notes = [50]
        c.pages[0][4].sound = "kick2"
        c.pages[0][6].locks["filter"] = 20
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
        // Проход клипа — 16 шагов: блоки по 16 (решение пользователя), у каждого своя копия.
        XCTAssertEqual(p.tracks[0].blocks.map { $0.length }, [16, 4])
        let own: Clip = try! XCTUnwrap(p.tracks[0].blocks[0].pattern)
        XCTAssertEqual(own.length, 16)
        XCTAssertTrue(own.pages[0][0].on)
        XCTAssertEqual(own.pages[0][4], Step(), "Chance не прошёл — пустой шаг, без p-lock")
        XCTAssertEqual(own.pages[0][6].locks["filter"], 20, "p-lock шага без трига — остаётся")
        XCTAssertTrue(p.tracks[0].blocks[1].pattern!.pages[0][0].on, "страница 2 — как играли")
        // Прошедший шаг с p-lock Chance — 100.
        var c2 = c
        c2.pages[0][0].locks["prob"] = 30
        p.tracks[0].clips[0] = c2
        p.tracks[0].blocks = []
        p.applyRecording([seg], played: pp, fired: ff)
        XCTAssertEqual(p.tracks[0].blocks[0].pattern?.pages[0][0].locks["prob"], 100)
    }

    /// Правка шагов во время записи (решение пользователя 2.11): каждый проход — как прозвучал; живые ноты — на свои шаги
    /// (к нотам шага, с длиной и силой), в тишине — блоками по такту.
    func testHeardStepsAndLiveNotes() {
        var p = Project()
        var c = Clip(pages: [Track.emptyPage()], length: 16, playFrom: 0, playTo: 0)
        c.pages[0][0].on = true
        c.pages[0][0].notes = [48]
        p.tracks[0].clips[0] = c
        var rec = ArrRecorder()
        var states: [(slot: Int, offset: Int)?] = [(slot: 0, offset: 0), (slot: -1, offset: 0)]
        states += [(slot: Int, offset: Int)?](repeating: nil, count: Params.maxTracks - 2)
        rec.begin(at: 0, states: states)
        // Такт 1: шаг 4 пуст; на такте 2 поставили шаг 4 и убрали шаг 0.
        var on4 = Step()
        on4.on = true
        on4.notes = [50]
        for x in 0..<32 {
            rec.step(x)
            let pos: Int = x % 16
            var st: Step = c.pages[0][pos]
            if x >= 16 && pos == 4 { st = on4 }
            if x >= 16 && pos == 0 { st = Step() }
            rec.notePlayed(track: 0, pos: pos, step: st)
            if st.on { rec.noteFired(track: 0) }
        }
        // Живые ноты: на дорожке 0 — шаг 8 (к пустому) и шаг 0 (к триггеру), на дорожке 1 (тишина) — шаг 20.
        let a: Int? = rec.liveNote(track: 0, at: 8, notes: [60], velocity: 0.5)
        rec.liveLength(a!, 3)
        _ = rec.liveNote(track: 0, at: 0, notes: [55], velocity: nil)
        _ = rec.liveNote(track: 1, at: 20, notes: [40], velocity: nil)
        XCTAssertNil(rec.liveNote(track: 2, at: 3, notes: [40], velocity: nil), "дорожка не пишется")
        let segs = rec.finish()
        p.applyRecording(segs, played: rec.played, fired: rec.fired, heard: rec.heard, live: rec.live)
        let b0: Clip = try! XCTUnwrap(p.tracks[0].blocks[0].pattern)
        let b1: Clip = try! XCTUnwrap(p.tracks[0].blocks[1].pattern)
        XCTAssertEqual(b0.pages[0][0].notes, [48, 55], "живая нота — к нотам шага")
        XCTAssertFalse(b0.pages[0][4].on, "такт 1 — без поставленного позже шага")
        XCTAssertTrue(b0.pages[0][8].on)
        XCTAssertEqual(b0.pages[0][8].notes, [60])
        XCTAssertEqual(b0.pages[0][8].len, 3)
        XCTAssertEqual(b0.pages[0][8].noteVel(0) ?? -1, 64, accuracy: 0.5, "сила — Level × velocity")
        XCTAssertFalse(b1.pages[0][0].on, "такт 2 — без убранного шага")
        XCTAssertEqual(b1.pages[0][4].notes, [50], "такт 2 — с поставленным шагом")
        XCTAssertEqual(p.tracks[1].blocks.map { [$0.start, $0.length] }, [[16, 16]], "тишина — такт с нотой")
        XCTAssertEqual(p.tracks[1].blocks[0].pattern?.pages[0][4].notes, [40])
    }

    /// ARRANGE REC START (2.11): по умолчанию — с плейхеда; прежние настройки записи читаются без потерь.
    func testRecordSettingsArrStart() throws {
        let old = #"{"quantize":false,"overdub":true,"autoRec":false}"#.data(using: .utf8)!
        let r: RecordSettings = try JSONDecoder().decode(RecordSettings.self, from: old)
        XCTAssertFalse(r.quantize)
        XCTAssertTrue(r.overdub)
        XCTAssertFalse(r.autoRec)
        XCTAssertFalse(r.arrFromStart)
        var n = RecordSettings()
        n.arrFromStart = true
        let back: RecordSettings = try JSONDecoder().decode(RecordSettings.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back, n)
    }

    /// Показ идущей записи: отрезки — законченные и идущий до конца текущего шага.
    func testRecorderCurrent() {
        var rec = ArrRecorder()
        var states: [(slot: Int, offset: Int)?] = [(slot: 0, offset: 0)]
        states += [(slot: Int, offset: Int)?](repeating: nil, count: Params.maxTracks - 1)
        XCTAssertTrue(rec.current.isEmpty)
        rec.begin(at: 4, states: states)
        rec.step(5)
        rec.step(6)
        XCTAssertEqual(rec.current.map { [$0.track, $0.start, $0.end] }, [[0, 4, 7]])
        rec.clip(track: 0, slot: 1)
        rec.step(7)
        XCTAssertEqual(rec.current.map { [$0.slot, $0.start, $0.end] }, [[0, 4, 6], [1, 6, 8]])
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
        // Клип в такт — блоки по такту.
        XCTAssertEqual(p.tracks[0].blocks.count, 19)
        XCTAssertEqual(p.tracks[0].blocks.last?.length, 12)
        XCTAssertEqual(p.tracks[0].blocks[1].start, 16)
        XCTAssertTrue(p.tracks[0].blocks[18].pattern!.pages[0][0].on)
    }

    func testBlocksByPatternLength() {
        var p = Project()
        // Клип в 2 такта — блоки по 2 такта; запись с середины клипа — первый блок до конца прохода.
        p.tracks[0].clips[0] = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 32, playFrom: 0, playTo: 1)
        p.tracks[0].clips[0]!.pages[0][0].on = true
        p.applyRecording([ArrRecorder.Seg(track: 0, slot: 0, start: 0, end: 72, offset: 8)])
        XCTAssertEqual(p.tracks[0].blocks.map { [$0.start, $0.length, $0.offset] }, [[24, 32, 0], [56, 16, 0]], "начало прохода без тригов — пусто")
        // Длинный клип (8 страниц) — не длиннее 8 тактов.
        var t = Track(index: 0)
        t.clips[0] = Clip(pages: [[Step]](repeating: Track.emptyPage(), count: 8), length: 128, playFrom: 0, playTo: 7)
        t.clips[0]!.pages[0][0].on = true
        t.addBlock(clip: 0, at: 0, length: 300)
        XCTAssertEqual(t.blocks.map { $0.length }, [128, 128, 44])
    }

    func testEmptyBlocksNotWritten() {
        // Участок клипа без тригов — без блока: клип в 2 такта, триг только в 1-м, запись со 2-го такта.
        var p = Project()
        p.tracks[0].clips[0] = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 32, playFrom: 0, playTo: 1)
        p.tracks[0].clips[0]!.pages[0][0].on = true
        p.applyRecording([ArrRecorder.Seg(track: 0, slot: 0, start: 0, end: 64, offset: 16)])
        XCTAssertEqual(p.tracks[0].blocks.map { [$0.start, $0.length] }, [[16, 32], [48, 16]])
        // Запись «по факту»: такты, где ничего не прозвучало (mute, Chance), — пусто.
        var q = Project()
        q.tracks[0].clips[0] = Clip()
        q.tracks[0].clips[0]!.pages[0][0].on = true
        var pp: [[Int: Int]] = [[Int: Int]](repeating: [:], count: Params.maxTracks)
        for x in 0..<48 { pp[0][x] = x % 16 }
        var ff: [Set<Int>] = [Set<Int>](repeating: [], count: Params.maxTracks)
        ff[0] = [0, 32]
        q.applyRecording([ArrRecorder.Seg(track: 0, slot: 0, start: 0, end: 48, offset: 0)], played: pp, fired: ff)
        XCTAssertEqual(q.tracks[0].blocks.map { $0.start }, [0, 32])
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
