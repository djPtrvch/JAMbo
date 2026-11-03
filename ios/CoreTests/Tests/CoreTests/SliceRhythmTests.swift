import XCTest
@testable import Core

/// Случайная нарезка (SHIFT + RANDOM на дорожке с нарезанным сэмплом): брейк, роли LOW/MID/HIGH по стилю, LONG без
/// наложения, длины нот, запись, роль маркера в проекте.
final class SliceRhythmTests: XCTestCase {
    private func pieces(_ lens: [Double], roles: [SliceRhythm.Role?]? = nil) -> [SliceRhythm.Piece] {
        return lens.enumerated().map { k, l in
            SliceRhythm.Piece(note: 60 + k, len: l, role: roles?[k] ?? nil)
        }
    }

    /// Ноты страницы не накладываются: каждая кончается не позже следующей (в своей группе — по нотам).
    private func noOverlap(_ evs: [SliceRhythm.Event], notes: Set<Int>, len n: Int, _ msg: String) {
        let own: [SliceRhythm.Event] = evs.filter { notes.contains($0.note) }.sorted { $0.step < $1.step }
        for (i, e) in own.enumerated() {
            XCTAssertGreaterThanOrEqual(e.len, 1, msg)
            let next: Int = i + 1 < own.count ? own[i + 1].step : n
            XCTAssertLessThanOrEqual(e.step + e.len, next, msg)
        }
    }

    func testBreakBase() {
        var g = SystemRandomNumberGenerator()
        let ps = pieces([2, 2, 1, 1, 2, 4, 1.3, 3])
        for _ in 0..<300 {
            let pat = SliceRhythm.pattern(ps, lens: [16], using: &g)
            let evs = pat[0]
            XCTAssertEqual(evs.first?.step, 0)
            XCTAssertEqual(evs.first?.note, 60, "шаг 1 — первый кусок")
            noOverlap(evs, notes: Set(60...67), len: 16, "брейк")
            // Куски подряд: каждый своей длиной до следующего, страница заполнена.
            for (i, e) in evs.enumerated() {
                let next: Int = i + 1 < evs.count ? evs[i + 1].step : 16
                XCTAssertEqual(e.step + e.len, next)
                let full: Int = ps[e.note - 60].steps
                XCTAssertLessThanOrEqual(e.len, full)
                if e.step % 4 == 0 { XCTAssertEqual(e.vel, 127) }
            }
        }
    }

    func testBreakPagesAndFill() {
        var g = SystemRandomNumberGenerator()
        let ps = pieces([1, 1, 2, 1, 1, 2])
        for _ in 0..<200 {
            let pat = SliceRhythm.pattern(ps, lens: [16, 16, 16, 7], using: &g)
            XCTAssertEqual(pat.count, 4)
            for (p, evs) in pat.enumerated() {
                let n: Int = [16, 16, 16, 7][p]
                XCTAssertFalse(evs.isEmpty)
                XCTAssertTrue(evs.allSatisfy { $0.step < n }, "в пределах длины страницы")
                noOverlap(evs, notes: Set(60...65), len: n, "страница \(p)")
            }
            XCTAssertTrue(pat[3].contains { $0.step >= 3 }, "сбивка в последних 4 шагах")
        }
    }

    func testAvoid() {
        var g = SystemRandomNumberGenerator()
        let ps = pieces([1, 1, 1, 1])
        let a = SliceRhythm.pattern(ps, lens: [16], using: &g)
        let code = SliceRhythm.code(a[0])
        var same = 0
        for _ in 0..<50 where SliceRhythm.code(SliceRhythm.pattern(ps, lens: [16], avoid: code, using: &g)[0]) == code {
            same += 1
        }
        XCTAssertEqual(same, 0)
    }

    func testKitRoles() {
        var g = SystemRandomNumberGenerator()
        // 60 — LOW, 61 — MID, 62, 63 — HIGH, 64 — без роли (в ките не играет).
        let ps = pieces([1, 2, 0.5, 0.5, 1], roles: [.low, .mid, .high, .high, nil])
        for _ in 0..<200 {
            let evs = SliceRhythm.pattern(ps, style: 0, lens: [16], using: &g)[0]
            let low = Set(evs.filter { $0.note == 60 }.map { $0.step })
            XCTAssertTrue(low.isSuperset(of: [0, 4, 8, 12]), "House: LOW на каждую долю")
            let mid = Set(evs.filter { $0.note == 61 }.map { $0.step })
            XCTAssertTrue(mid.isSuperset(of: [4, 12]), "MID — на местах SNARE")
            XCTAssertFalse(evs.contains { $0.note == 64 }, "кусок без роли в ките не играет")
            XCTAssertTrue(evs.allSatisfy { $0.vel != nil }, "у каждой ноты своя velocity")
            noOverlap(evs, notes: [60], len: 16, "LOW")
            noOverlap(evs, notes: [61], len: 16, "MID")
            noOverlap(evs, notes: [62, 63], len: 16, "HIGH")
        }
    }

    func testLongNeverOverlaps() {
        var g = SystemRandomNumberGenerator()
        // Длинный пэд (40 шагов) поверх брейка из двух кусков; и короткий LONG (6 шагов).
        for long in [40.0, 6.0] {
            let ps = pieces([1, 1, long], roles: [nil, nil, .long])
            for _ in 0..<100 {
                let pat = SliceRhythm.pattern(ps, lens: [16, 16, 16], using: &g)
                for evs in pat {
                    let l = evs.filter { $0.note == 62 }
                    XCTAssertEqual(l.first?.step, 0)
                    XCTAssertEqual(l.count, long > 8 ? 1 : 2)
                    noOverlap(evs, notes: [62], len: 16, "LONG")
                    XCTAssertTrue(evs.contains { $0.note == 60 || $0.note == 61 }, "брейк остаётся")
                }
            }
        }
        // Только LONG — без ритма.
        let only = SliceRhythm.pattern(pieces([30], roles: [.long]), lens: [16], using: &g)[0]
        XCTAssertEqual(only.map { $0.step }, [0])
        XCTAssertEqual(only.first?.len, 16)
    }

    func testWriteAndRoleCoding() throws {
        var t = Track(index: 0)
        t.sample = "loop.caf"
        XCTAssertFalse(t.sliced)
        t.addSlice("loop.caf", at: 0)
        t.addSlice("loop.caf", at: 0.5)
        XCTAssertTrue(t.sliced)
        t.setSliceRole("loop.caf", 1, role: .long)
        XCTAssertEqual(t.sliceMarks("loop.caf")[1].role, 3)
        t.withStep(3) { s in s.on = true; s.notes = [40] }
        let pat: [[SliceRhythm.Event]] = [[SliceRhythm.Event(step: 0, note: 60, len: 2, vel: 127),
                                           SliceRhythm.Event(step: 0, note: 62, len: 16, vel: 100),
                                           SliceRhythm.Event(step: 2, note: 61, len: 1, vel: 90)]]
        t.writeSlices(pat, pages: 0...0)
        XCTAssertFalse(t.pages[0][3].on, "прежние шаги стёрты")
        XCTAssertEqual(t.pages[0][0].notes, [60, 62])
        XCTAssertEqual(t.pages[0][0].noteLen(0), 2)
        XCTAssertEqual(t.pages[0][0].noteLen(1), 16)
        XCTAssertEqual(t.pages[0][0].locks["level"], 127, "p-lock — самая сильная нота")
        XCTAssertEqual(t.pages[0][2].noteVel(0), 90)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(back.sliceMarks("loop.caf")[1].role, 3)
        XCTAssertNil(back.sliceMarks("loop.caf")[0].role)
        t.setSliceRole("loop.caf", 1, role: nil)
        XCTAssertNil(t.sliceMarks("loop.caf")[1].role)
    }
}
