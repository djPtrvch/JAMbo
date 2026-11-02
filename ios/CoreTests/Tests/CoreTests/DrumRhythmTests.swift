import XCTest
@testable import Core

/// Случайный ритм ударных (SHIFT + CHORD): роли движков, стили, основа, короткие страницы, вариации, сбивка, запись.
final class DrumRhythmTests: XCTestCase {
    private let roles: [DrumRhythm.Role] = [.kick, .snare, .hat, .clap, .perc]

    func testRoles() {
        XCTAssertEqual(DrumRhythm.role(engine: 16), .kick)
        XCTAssertEqual(DrumRhythm.role(engine: 20), .snare)
        XCTAssertEqual(DrumRhythm.role(engine: 21), .hat)
        XCTAssertEqual(DrumRhythm.role(engine: 22), .clap)
        XCTAssertEqual(DrumRhythm.role(engine: 23), .perc)
        XCTAssertNil(DrumRhythm.role(engine: 17))
        XCTAssertNil(DrumRhythm.role(engine: nil))
    }

    func testBaseRules() {
        var g = SystemRandomNumberGenerator()
        XCTAssertEqual(DrumRhythm.styles, ["HOUSE", "BREAKS", "D&B", "TRAP", "AFRO", "MINIMAL"])
        for _ in 0..<300 {
            for st in 0..<DrumRhythm.styles.count {
                let k = DrumRhythm.base(.kick, style: st, len: 16, using: &g)
                XCTAssertEqual(k.first?.step, 0, "KICK на шаге 1, стиль \(st)")
                XCTAssertTrue(k.allSatisfy { $0.vel == nil }, "у KICK нет velocity")
                for r in roles where r != .kick {
                    for h in DrumRhythm.base(r, style: st, len: 16, using: &g) {
                        let v: Double = h.vel ?? 0
                        XCTAssertTrue(v == 127 || (38...108).contains(v))
                        if h.step % 4 == 0 { XCTAssertEqual(v, 127, "доля — 100 %") }
                    }
                }
            }
            // HOUSE: бочка на каждую долю, HAT на офбитах.
            let hk = Set(DrumRhythm.base(.kick, style: 0, len: 16, using: &g).map { $0.step })
            XCTAssertTrue(hk.isSuperset(of: [0, 4, 8, 12]))
            let hh = Set(DrumRhythm.base(.hat, style: 0, len: 16, using: &g).map { $0.step })
            XCTAssertTrue(hh.isSuperset(of: [2, 6, 10, 14]))
            // D&B: бочка 1 и 11, малый 5 и 13.
            let dk = Set(DrumRhythm.base(.kick, style: 2, len: 16, using: &g).map { $0.step })
            XCTAssertTrue(dk.isSuperset(of: [0, 10]))
            for st in [0, 1, 2] {
                let s = DrumRhythm.base(.snare, style: st, len: 16, using: &g)
                XCTAssertTrue(s.contains(DrumRhythm.Hit(step: 4, vel: 127)))
                XCTAssertTrue(s.contains(DrumRhythm.Hit(step: 12, vel: 127)))
                for h in s where h.step != 4 && h.step != 12 {
                    XCTAssertTrue((38...58).contains(h.vel ?? 0), "призрачный удар тихий")
                }
            }
            // TRAP: малый и хлопок на 9.
            XCTAssertTrue(DrumRhythm.base(.snare, style: 3, len: 16, using: &g).contains { $0.step == 8 })
            XCTAssertEqual(DrumRhythm.base(.clap, style: 3, len: 16, using: &g).map { $0.step }, [8])
            // AFRO: евклид — число ударов в пределах.
            XCTAssertTrue((3...5).contains(DrumRhythm.base(.kick, style: 4, len: 16, using: &g).count))
            XCTAssertTrue((5...11).contains(DrumRhythm.base(.hat, style: 4, len: 16, using: &g).count))
            XCTAssertTrue((3...7).contains(DrumRhythm.base(.perc, style: 0, len: 16, using: &g).count))
            // MINIMAL: малый и хлопок на 13, бочка 1 и иногда 11.
            XCTAssertEqual(DrumRhythm.base(.snare, style: 5, len: 16, using: &g).map { $0.step }, [12])
            XCTAssertTrue(DrumRhythm.base(.kick, style: 5, len: 16, using: &g).allSatisfy { [0, 10].contains($0.step) })
            XCTAssertTrue((2...3).contains(DrumRhythm.base(.perc, style: 5, len: 16, using: &g).count))
        }
    }

    func testProjectKeepsStyle() throws {
        var t = Track(index: 0)
        t.drumStyle = 3
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(Track.self, from: data).drumStyle, 3)
        // Старый проект без поля — HOUSE.
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj["drumStyle"] = nil
        let old = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(try JSONDecoder().decode(Track.self, from: old).drumStyle, 0)
    }

    func testShortPagesFilled() {
        var g = SystemRandomNumberGenerator()
        for r in roles {
            for len in 1...16 {
                for _ in 0..<30 {
                    let b = DrumRhythm.base(r, style: Int.random(in: 0..<6), len: len, using: &g)
                    XCTAssertFalse(b.isEmpty, "\(r) len \(len)")
                    XCTAssertTrue(b.allSatisfy { $0.step >= 0 && $0.step < len })
                }
            }
        }
    }

    func testPatternPages() {
        var g = SystemRandomNumberGenerator()
        for r in roles {
            for i in 0..<120 {
                let st: Int = i % 6
                let one = DrumRhythm.pattern(r, style: st, lens: [7], using: &g)
                XCTAssertEqual(one.count, 1)
                XCTAssertFalse(one[0].isEmpty)
                XCTAssertTrue(one[0].allSatisfy { $0.step < 7 })
                // 23 шага: 16 + 7 — вторая страница со сбивкой в шагах 4–7.
                let two = DrumRhythm.pattern(r, style: st, lens: [16, 7], using: &g)
                XCTAssertTrue(two[1].allSatisfy { $0.step < 7 })
                XCTAssertTrue(two[1].contains { $0.step >= 3 }, "сбивка в последних 4 шагах")
                XCTAssertEqual(two[1].filter { $0.step < 3 }.map { $0.step },
                               two[0].filter { $0.step < 3 }.map { $0.step }, "до сбивки — основа")
                let four = DrumRhythm.pattern(r, style: st, lens: [16, 16, 16, 16], using: &g)
                XCTAssertTrue(four.allSatisfy { !$0.isEmpty })
                XCTAssertEqual(four[3].filter { $0.step < 12 }, four[0].filter { $0.step < 12 })
                for p in 1...2 {
                    let a = Set(four[0].map { $0.step }), b = Set(four[p].map { $0.step })
                    XCTAssertLessThanOrEqual(a.symmetricDifference(b).count, 2, "вариация — 1–2 удара")
                }
                if r == .kick { XCTAssertTrue(four.allSatisfy { $0.first?.step == 0 }) }
                if r == .snare {
                    let main: [Int] = [[4, 12], [4, 12], [4, 12], [8], [], [12]][st]
                    for p in 0..<3 { XCTAssertTrue(main.allSatisfy { m in four[p].contains { $0.step == m } }, "стиль \(st)") }
                }
            }
        }
    }

    func testAvoidLast() {
        var g = SystemRandomNumberGenerator()
        var same: Int = 0
        var last: [Int]? = nil
        for _ in 0..<200 {
            let p = DrumRhythm.pattern(.kick, lens: [16], avoid: last, using: &g)
            let steps: [Int] = p[0].map { $0.step }
            if steps == last { same += 1 }
            last = steps
        }
        XCTAssertLessThan(same, 3)
    }

    func testEuclid() {
        XCTAssertEqual(DrumRhythm.euclid(4, 16, rot: 0), [0, 4, 8, 12])
        XCTAssertEqual(DrumRhythm.euclid(3, 8, rot: 0).count, 3)
        XCTAssertEqual(DrumRhythm.euclid(5, 16, rot: 3).count, 5)
    }

    func testWriteDrums() {
        var t = Track(index: 0)
        t.pages = [Track.emptyPage(), Track.emptyPage(), Track.emptyPage()]
        t.toggleStep(40, notes: [60])
        t.toggleStep(3, notes: [60])
        let pat: [[DrumRhythm.Hit]] = [[DrumRhythm.Hit(step: 0, vel: nil), DrumRhythm.Hit(step: 5, vel: 90)],
                                       [DrumRhythm.Hit(step: 2, vel: 127)]]
        t.writeDrums(pat, note: 36, pages: 0...1)
        XCTAssertTrue(t.pages[0][0].on)
        XCTAssertEqual(t.pages[0][0].notes, [36])
        XCTAssertNil(t.pages[0][0].locks["level"])
        XCTAssertEqual(t.pages[0][5].locks["level"], 90)
        XCTAssertFalse(t.pages[0][3].on, "прежние шаги стёрты")
        XCTAssertEqual(t.pages[1][2].locks["level"], 127)
        XCTAssertTrue(t.pages[2][8].on, "страница вне range не тронута")
    }
}
