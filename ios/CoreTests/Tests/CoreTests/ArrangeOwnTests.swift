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
