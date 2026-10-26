import XCTest
@testable import Core

final class ArrangeTests: XCTestCase {
    private func spans(_ t: Track) -> [[Int]] {
        return t.blocks.map { [$0.clip, $0.start, $0.length, $0.offset] }
    }

    func testAddBlockUsesClipLength() {
        var t = Track(index: 0)
        t.clips[1] = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 32, playFrom: 0, playTo: 1)
        t.addBlock(clip: 0, at: 0)
        t.addBlock(clip: 1, at: 16)
        XCTAssertEqual(spans(t), [[0, 0, 16, 0], [1, 16, 32, 0]])
        XCTAssertEqual(t.arrangeEnd, 48)
    }

    func testPlaceReplacesOverlapAndSplits() {
        var t = Track(index: 0)
        t.placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        t.placeBlock(ArrBlock(clip: 2, start: 16, length: 16))
        // Середина заменена: правая часть продолжает клип с шага 32.
        XCTAssertEqual(spans(t), [[0, 0, 16, 0], [2, 16, 16, 0], [0, 32, 32, 32]])
        t.placeBlock(ArrBlock(clip: 3, start: 8, length: 32))
        XCTAssertEqual(spans(t), [[0, 0, 8, 0], [3, 8, 32, 0], [0, 40, 24, 40]])
    }

    func testMoveResizeDuplicateDelete() {
        var t = Track(index: 0)
        t.placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        t.placeBlock(ArrBlock(clip: 1, start: 32, length: 16))
        var i = t.moveBlock(0, to: 40)
        XCTAssertEqual(spans(t), [[1, 32, 8, 0], [0, 40, 16, 0]])
        XCTAssertEqual(i, 1)
        i = t.resizeBlock(i, start: 36, end: 72)
        XCTAssertEqual(spans(t), [[1, 32, 4, 0], [0, 36, 36, -4]], "левый край сдвигает место в клипе")
        i = t.duplicateBlock(i)
        XCTAssertEqual(t.blocks[i].start, 72)
        t.deleteBlock(0)
        XCTAssertEqual(t.blocks.count, 2)
    }

    func testPasteAfterBlock() {
        var t = Track(index: 0)
        t.placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        t.placeBlock(ArrBlock(clip: 1, start: 16, length: 16))
        t.pasteBlock(after: 0, ArrBlock(clip: 4, start: 99, length: 8))
        XCTAssertEqual(spans(t), [[0, 0, 16, 0], [4, 16, 8, 0], [1, 24, 8, 8]])
    }

    func testInsertShiftsOnlyThisTrack() {
        var p = Project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 32))
        p.tracks[0].placeBlock(ArrBlock(clip: 1, start: 32, length: 16))
        p.tracks[1].placeBlock(ArrBlock(clip: 0, start: 32, length: 16))
        let i = p.tracks[0].insertBlock(clip: 2, at: 16)
        // Блок, через который проходит точка вставки, делится; правее — сдвиг на такт.
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 16, 0], [2, 16, 16, 0], [0, 32, 16, 16], [1, 48, 16, 0]])
        XCTAssertEqual(spans(p.tracks[1]), [[0, 32, 16, 0]])
        // Протяжка края вставленного: сдвиг пересчитывается.
        let j = p.tracks[0].resizeInserted(i, length: 24)
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 16, 0], [2, 16, 24, 0], [0, 40, 16, 16], [1, 56, 16, 0]])
        p.tracks[0].resizeInserted(j, length: 8)
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 16, 0], [2, 16, 8, 0], [0, 24, 16, 16], [1, 40, 16, 0]])
    }

    func testTrackMenuCopyPasteDuplicate() {
        var p = Project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 16, length: 16))
        p.tracks[0].placeBlock(ArrBlock(clip: 1, start: 48, length: 16))
        let copy = p.tracks[0].blocks
        p.tracks[1].placeBlock(ArrBlock(clip: 3, start: 0, length: 128))
        p.pasteBlocks(1, copy)
        XCTAssertEqual(p.tracks[1].blocks, copy)
        p.tracks[0].duplicateBlocks()
        XCTAssertEqual(spans(p.tracks[0]), [[0, 16, 16, 0], [1, 48, 16, 0], [0, 64, 16, 0], [1, 96, 16, 0]])
        p.setTrackColor(0, 3)
        XCTAssertEqual(p.tracks[0].color, 3)
        p.setTrackColor(0, 99)
        XCTAssertEqual(p.tracks[0].color, 3)
    }

    func testRowEditsFollowBlocks() {
        var p = Project()
        p.addRow(); p.addRow(); p.addRow()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        p.tracks[0].placeBlock(ArrBlock(clip: 1, start: 16, length: 16))
        p.tracks[0].placeBlock(ArrBlock(clip: 2, start: 32, length: 16))
        p.deleteRow(1)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.clip }, [0, 1], "блок удалённого клипа уходит, ниже — вверх")
        p.moveRow(0, to: 1)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.clip }, [1, 0])
        p.duplicateRow(0)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.clip }, [2, 0])
        p.pasteRow(0, p.copyRow(1))
        XCTAssertEqual(p.tracks[0].blocks.map { $0.clip }, [2], "клип заменён PASTE — его блоки уходят")
    }

    func testBlocksMoveWithTrack() {
        var p = Project()
        p.tracks[2].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        p.tracks[2].color = 5
        p.moveTrack(2, 0)
        XCTAssertEqual(p.tracks[0].blocks.count, 1)
        XCTAssertEqual(p.tracks[0].color, 5)
        let src = p.tracks[3]
        p.pasteTrack(0, src)
        XCTAssertEqual(p.tracks[0].blocks.count, 1, "PASTE дорожки — только настройки, блоки свои")
        XCTAssertEqual(p.tracks[0].color, 5)
    }

    func testMarkersAndLoop() {
        var p = Project()
        p.addMarker(at: 64, name: "  CHORUS LONG NAME  ")
        p.addMarker(at: 0, name: "INTRO")
        XCTAssertEqual(p.arrange.markers.map { $0.name }, ["INTRO", "CHORUS LONG "])
        XCTAssertEqual(p.arrange.markers[0].color, ArrPalette.defaultColor)
        XCTAssertEqual(p.section(at: 63), 0)
        XCTAssertEqual(p.section(at: 64), 1)
        let k = p.moveMarker(1, to: 0)
        XCTAssertEqual(p.arrange.markers.count, 1, "на занятом месте маркер заменяется")
        p.renameMarker(k, "VERSE")
        p.setMarkerColor(k, 4)
        XCTAssertEqual(p.arrange.markers[0], ArrMarker(at: 0, name: "VERSE", color: 4))
        p.deleteMarker(0)
        XCTAssertNil(p.section(at: 10))
        p.setLoop(64, 32)
        p.arrange.loop = true
        XCTAssertEqual([p.arrange.loopFrom, p.arrange.loopTo], [32, 64])
        p.setLoop(16, 16)
        XCTAssertFalse(p.arrange.loop)
    }

    func testSnap() {
        var a = Arrangement()
        XCTAssertEqual(a.grid, 2, "по умолчанию — 1/4")
        a.grid = 0
        XCTAssertEqual(a.snapped(7), 0)
        XCTAssertEqual(a.snapped(8), 16)
        a.grid = 2
        XCTAssertEqual(a.snapped(5), 4)
        a.snap = false
        XCTAssertEqual(a.snapped(5), 5)
        XCTAssertEqual(a.snapped(-3), 0)
    }

    func testCodingAndRepair() throws {
        var p = Project()
        p.tracks[0].placeBlock(ArrBlock(clip: 1, start: 16, length: 32, offset: 4))
        p.tracks[0].color = 9
        p.addMarker(at: 32, name: "DROP")
        p.setLoop(0, 64)
        p.arrange.loop = true
        p.arrange.grid = 3
        p.arrange.snap = false
        p.arrange.hideSteps = true
        let data = try JSONEncoder().encode(p)
        var q = try JSONDecoder().decode(Project.self, from: data)
        q.repair()
        XCTAssertEqual(q.tracks[0].blocks, p.tracks[0].blocks)
        XCTAssertEqual(q.tracks[0].color, 9)
        XCTAssertEqual(q.arrange, p.arrange)

        // Старый проект (версия 4, без полей аранжировки) — пустая аранжировка.
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj["arrange"] = nil
        obj["version"] = 4
        var tracks = obj["tracks"] as! [[String: Any]]
        for k in tracks.indices { tracks[k]["blocks"] = nil; tracks[k]["color"] = nil }
        obj["tracks"] = tracks
        var old = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: obj))
        old.repair()
        XCTAssertEqual(old.version, 5)
        XCTAssertTrue(old.tracks.allSatisfy { $0.blocks.isEmpty && $0.color == ArrPalette.defaultColor })
        XCTAssertEqual(old.arrange, Arrangement())

        // Испорченные данные: перекрытия, клип вне сетки, цвет и сетка вне пределов.
        var bad = Project()
        bad.tracks[0].blocks = [ArrBlock(clip: 0, start: 0, length: 32), ArrBlock(clip: 1, start: 16, length: 16),
                                ArrBlock(clip: 40, start: 64, length: 16)]
        bad.tracks[0].color = 77
        bad.arrange.grid = 9
        bad.arrange.loopFrom = 10
        bad.arrange.loop = true
        bad.repair()
        XCTAssertEqual(spans(bad.tracks[0]), [[0, 0, 16, 0], [1, 16, 16, 0]])
        XCTAssertEqual(bad.tracks[0].color, ArrPalette.defaultColor)
        XCTAssertEqual(bad.arrange.grid, 3)
        XCTAssertFalse(bad.arrange.loop)
    }

    func testSplitRange() {
        var p = Project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        p.tracks[1].placeBlock(ArrBlock(clip: 0, start: 16, length: 16))
        p.splitArrange(track: 0, 16, 48)
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 16, 0], [0, 16, 32, 16], [0, 48, 16, 48]])
        p.tracks[1].placeBlock(ArrBlock(clip: 0, start: 40, length: 16))
        p.splitArrange(track: 1, 16, 48)
        XCTAssertEqual(spans(p.tracks[1]), [[0, 16, 16, 0], [0, 40, 8, 0], [0, 48, 8, 8]], "только эта дорожка; на краю — без разреза")
    }

    func testSectionWithEnd() {
        var p = Project()
        let k = p.addMarker(at: 32, name: "DROP", end: 64)
        XCTAssertEqual(p.sectionEnd(k), 64)
        XCTAssertEqual(p.section(at: 40), k)
        XCTAssertNil(p.section(at: 64), "после конца секции — нет")
        let j = p.moveMarker(k, to: 48)
        XCTAssertEqual(p.arrange.markers[j].end, 80, "секция переезжает целиком")
        p.addMarker(at: 64, name: "OUT")
        XCTAssertEqual(p.sectionEnd(j), 64, "не дальше следующего маркера")
        p.deleteMarker(1)
        p.deleteMarker(0)
        XCTAssertTrue(p.arrange.markers.isEmpty)
    }

    /// Группа блоков: перенос (не левее нуля, блоки группы не затирают друг друга), DUPLICATE за группой, DELETE.
    func testBlockGroup() {
        var p = Project()
        p.tracks[0].blocks = []
        p.tracks[1].blocks = []
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 16, length: 16))
        p.tracks[1].placeBlock(ArrBlock(clip: 0, start: 8, length: 16))
        let sel: [(track: Int, block: Int)] = [(0, 0), (0, 1), (1, 0)]
        let moved = p.moveBlocks(sel, by: 8)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.start }, [8, 24])
        XCTAssertEqual(p.tracks[1].blocks.map { $0.start }, [16])
        XCTAssertEqual(moved.count, 3)
        p.moveBlocks(moved, by: -100)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.start }, [0, 16], "не левее нуля, сдвиг группы общий")
        XCTAssertEqual(p.tracks[1].blocks.map { $0.start }, [8])
        let all: [(track: Int, block: Int)] = [(0, 0), (0, 1), (1, 0)]
        let copies = p.duplicateBlocks(all)
        XCTAssertEqual(copies.count, 3)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.start }, [0, 16, 32, 48], "копии за группой: сдвиг 32")
        XCTAssertEqual(p.tracks[1].blocks.map { $0.start }, [8, 40])
        p.deleteBlocks(copies)
        XCTAssertEqual(p.tracks[0].blocks.map { $0.start }, [0, 16])
        XCTAssertEqual(p.tracks[1].blocks.map { $0.start }, [8])
    }

    /// Края секции: левый — не правее конца и не левее конца прежней; правый — не дальше следующей.
    func testSectionEdges() {
        var p = Project()
        p.addMarker(at: 0, name: "A", end: 16)
        p.addMarker(at: 32, name: "B", end: 64)
        p.setMarkerStart(1, 8)
        XCTAssertEqual(p.arrange.markers[1].at, 16, "не левее конца прежней")
        p.setMarkerStart(1, 70)
        XCTAssertEqual(p.arrange.markers[1].at, 63, "не правее своего конца")
        p.setMarkerEnd(0, 100)
        XCTAssertEqual(p.arrange.markers[0].end, 63, "не дальше следующей")
        p.setMarkerEnd(0, -5)
        XCTAssertEqual(p.arrange.markers[0].end, 1)
        p.setMarkerEnd(1, 128)
        XCTAssertEqual(p.arrange.markers[1].end, 128)
    }

    /// TO ARRANGE: N блоков длиной в свой клип, секция — имя строки на длину самого длинного × N; LOOP ROW — один проход.
    func testRowToArrange() {
        var p = Project()
        for t in p.tracks.indices { p.tracks[t].clips[2] = nil }
        p.tracks[0].clips[2] = Clip(pages: [Track.emptyPage()], length: 16, playFrom: 0, playTo: 0)
        p.tracks[1].clips[2] = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 32, playFrom: 0, playTo: 1)
        p.setScene(2, name: "Drop", repeats: 2)
        p.rowLoop = false
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        XCTAssertEqual(p.rowToArrange(2, at: nil), 80)
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 16, 0], [2, 16, 16, 0], [2, 32, 16, 0], [2, 48, 16, 0], [2, 64, 16, 0]],
                       "короткий клип повторяется до длины строки")
        XCTAssertEqual(spans(p.tracks[1]), [[2, 16, 32, 0], [2, 48, 32, 0]])
        XCTAssertEqual(p.arrange.markers.map { [$0.at, $0.end ?? -1] }, [[16, 80]])
        XCTAssertEqual(p.arrange.markers[0].name, "Drop")
        // С курсора: заменяет блоки и секции этих дорожек на участке; LOOP ROW — один проход.
        p.rowLoop = true
        p.tracks[2].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        XCTAssertEqual(p.rowToArrange(2, at: 0), 32)
        XCTAssertEqual(spans(p.tracks[0]), [[2, 0, 16, 0], [2, 16, 16, 0], [2, 32, 16, 0], [2, 48, 16, 0], [2, 64, 16, 0]])
        XCTAssertEqual(spans(p.tracks[1]), [[2, 0, 32, 0], [2, 32, 16, 16], [2, 48, 32, 0]], "правее участка — остаток прежнего блока")
        XCTAssertEqual(spans(p.tracks[2]), [[2, 0, 16, 0], [2, 16, 16, 0], [0, 32, 32, 32], [2, 64, 16, 0]],
                       "пустая ячейка — блоки по такту (допишут паттерн — зазвучит)")
        XCTAssertEqual(p.arrange.markers.map { [$0.at, $0.end ?? -1] }, [[0, 32]])
        // Пустая строка — ничего.
        XCTAssertNil(p.rowToArrange(5, at: nil))
    }

    /// Журнал SEND TO ARRANGE: блоки от запусков, тишина — пропуск, окно 32 такта (offset — место в проходе).
    func testJournalTake() {
        var j = ArrJournal()
        XCTAssertTrue(j.isEmpty)
        j.record(track: 0, slot: 0, start: 0)
        j.record(track: 0, slot: 1, start: 32)
        j.record(track: 1, slot: 2, start: 16)
        j.record(track: 1, slot: -1, start: 48)
        var r = j.take(now: 60)
        XCTAssertEqual(r.length, 64)
        XCTAssertEqual(spans(blocks: r.blocks[0]), [[0, 0, 32, 0], [1, 32, 32, 0]])
        XCTAssertEqual(spans(blocks: r.blocks[1]), [[2, 16, 32, 0]])
        j.record(track: 0, slot: 3, start: 1000)
        r = j.take(now: 1000)
        XCTAssertEqual(r.length, 512)
        XCTAssertEqual(spans(blocks: r.blocks[0]), [[1, 0, 504, 464], [3, 504, 8, 0]])
        XCTAssertTrue(r.blocks[1].isEmpty, "тишина и то, что кончилось до окна, — без блоков")
        j.move(0, 2)
        XCTAssertEqual(j.entries[2].last, ArrJournal.Entry(slot: 3, start: 1000))
    }

    func testSendToArrange() {
        var p = Project()
        p.tracks[0].clips[1] = Clip(pages: [Track.emptyPage()], length: 16, playFrom: 0, playTo: 0)
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        p.tracks[1].placeBlock(ArrBlock(clip: 0, start: 0, length: 64))
        let blocks: [[ArrBlock]] = [[ArrBlock(clip: 1, start: 0, length: 40, offset: 20)], [], []]
        XCTAssertEqual(p.sendToArrange(blocks, length: 48, at: nil), 112)
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 16, 0], [1, 64, 40, 4]])
        XCTAssertEqual(p.sendToArrange(blocks, length: 48, at: 8), 56)
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 8, 0], [1, 8, 40, 4], [1, 64, 40, 4]])
        XCTAssertEqual(spans(p.tracks[1]), [[0, 0, 64, 0]], "дорожка без блоков журнала не меняется")
        XCTAssertNil(p.sendToArrange([[], []], length: 48, at: nil))
    }

    private func spans(blocks: [ArrBlock]) -> [[Int]] {
        return blocks.map { [$0.clip, $0.start, $0.length, $0.offset] }
    }

    /// Запись с AUTO: запуск закрывает отрезок, тишина и таймлайн, скачок петли продолжает клип с того же места.
    func testRecorder() {
        var r = ArrRecorder()
        r.begin(at: 32, states: [(slot: 0, offset: 5), (slot: -1, offset: 0), nil])
        for p in 33...48 { r.step(p) }
        r.clip(track: 1, slot: 2)
        r.clip(track: 0, slot: -1)
        for p in 49..<64 { r.step(p) }
        r.step(32)
        r.clip(track: 1, slot: nil)
        r.step(33)
        let segs = r.finish()
        XCTAssertFalse(r.active)
        let list: [[Int]] = segs.map { [$0.track, $0.slot, $0.start, $0.end, $0.offset] }
        // Петля (64 → 32): отрезки продолжаются с места прохода 16; дорожка 1 ушла на таймлайн сразу — без отрезка.
        XCTAssertEqual(list, [[1, -1, 32, 48, 0], [0, 0, 32, 48, 5], [0, -1, 48, 64, 0], [1, 2, 48, 64, 0],
                              [0, -1, 32, 34, 16]])
        var p = Project()
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 128))
        p.tracks[1].clips[2] = Clip(pages: [Track.emptyPage()], length: 16, playFrom: 0, playTo: 0)
        p.applyRecording(segs)
        XCTAssertEqual(spans(p.tracks[0]), [[0, 0, 32, 0], [0, 34, 14, 7], [0, 64, 64, 64]])
        XCTAssertEqual(spans(p.tracks[1]), [[2, 48, 16, 0]])
    }
}
