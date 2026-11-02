import XCTest
@testable import Core

/// Случайный ритм ударных (SHIFT + CHORD): роли движков, основа, короткие страницы, вариации, сбивка, запись.
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
        for _ in 0..<300 {
            let k = DrumRhythm.base(.kick, len: 16, using: &g)
            XCTAssertEqual(k.first?.step, 0)
            XCTAssertTrue(k.allSatisfy { $0.vel == nil }, "у KICK нет velocity")
            XCTAssertTrue(k.allSatisfy { [0, 4, 8, 10, 12, 14, 15].contains($0.step) })
            let s = DrumRhythm.base(.snare, len: 16, using: &g)
            XCTAssertTrue(s.contains(DrumRhythm.Hit(step: 4, vel: 127)))
            XCTAssertTrue(s.contains(DrumRhythm.Hit(step: 12, vel: 127)))
            for h in s where h.step != 4 && h.step != 12 {
                XCTAssertTrue((38...58).contains(h.vel ?? 0), "призрачный удар тихий")
            }
            let p = DrumRhythm.base(.perc, len: 16, using: &g)
            XCTAssertTrue((3...7).contains(p.count))
            for r in roles where r != .kick {
                for h in DrumRhythm.base(r, len: 16, using: &g) {
                    let v: Double = h.vel ?? 0
                    XCTAssertTrue(v == 127 || (38...108).contains(v))
                    if h.step % 4 == 0 { XCTAssertEqual(v, 127, "доля — 100 %") }
                }
            }
        }
    }

    func testShortPagesFilled() {
        var g = SystemRandomNumberGenerator()
        for r in roles {
            for len in 1...16 {
                for _ in 0..<30 {
                    let b = DrumRhythm.base(r, len: len, using: &g)
                    XCTAssertFalse(b.isEmpty, "\(r) len \(len)")
                    XCTAssertTrue(b.allSatisfy { $0.step >= 0 && $0.step < len })
                }
            }
        }
    }

    func testPatternPages() {
        var g = SystemRandomNumberGenerator()
        for r in roles {
            for _ in 0..<100 {
                let one = DrumRhythm.pattern(r, lens: [7], using: &g)
                XCTAssertEqual(one.count, 1)
                XCTAssertFalse(one[0].isEmpty)
                XCTAssertTrue(one[0].allSatisfy { $0.step < 7 })
                // 23 шага: 16 + 7 — вторая страница со сбивкой в шагах 4–7.
                let two = DrumRhythm.pattern(r, lens: [16, 7], using: &g)
                XCTAssertTrue(two[1].allSatisfy { $0.step < 7 })
                XCTAssertTrue(two[1].contains { $0.step >= 3 }, "сбивка в последних 4 шагах")
                XCTAssertEqual(two[1].filter { $0.step < 3 }.map { $0.step },
                               two[0].filter { $0.step < 3 }.map { $0.step }, "до сбивки — основа")
                let four = DrumRhythm.pattern(r, lens: [16, 16, 16, 16], using: &g)
                XCTAssertTrue(four.allSatisfy { !$0.isEmpty })
                XCTAssertEqual(four[3].filter { $0.step < 12 }, four[0].filter { $0.step < 12 })
                for p in 1...2 {
                    let a = Set(four[0].map { $0.step }), b = Set(four[p].map { $0.step })
                    XCTAssertLessThanOrEqual(a.symmetricDifference(b).count, 2, "вариация — 1–2 удара")
                }
                if r == .kick { XCTAssertTrue(four.allSatisfy { $0.first?.step == 0 }) }
                if r == .snare {
                    for p in 0..<3 { XCTAssertTrue(four[p].contains { $0.step == 4 } && four[p].contains { $0.step == 12 }) }
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
