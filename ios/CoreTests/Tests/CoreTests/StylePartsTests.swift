import XCTest
@testable import Core

/// Случайные партии House, Breaks, Trap, Pop, Ambient (StyleParts.swift, StyleRoles.swift).
final class StylePartsTests: XCTestCase {
    typealias M = MelodyRhythm
    let scale: Int = 1
    let root: Int = 9
    let roles: [M.Role] = [.bass, .lead, .keys, .pad, .arp]

    func inScale(_ note: Int) -> Bool {
        return Scales.all[scale].steps.contains(((note - root) % 12 + 12) % 12)
    }

    func part(_ role: M.Role, _ ps: Int, pages: Int, kicks: [Set<Int>]? = nil, single: Bool = false,
              arp: TrackArp = TrackArp(), using g: inout Rng) -> (pat: [[SliceRhythm.Event]], degrees: [Int], kind: Int) {
        let d: [Int] = M.styleProgression(ps, scale: scale, avoid: nil, using: &g)
        let kind: Int = M.styleKind(ps, using: &g)
        let oct: Int = role == .bass ? 1 : 3
        let pat = M.stylePart(role, style: ps, lens: Array(repeating: 16, count: pages), degrees: d, kind: kind,
                              scale: scale, root: root, octave: oct, kicks: kicks, single: single, arp: arp, using: &g)
        return (pat, d, kind)
    }

    func testStyles() {
        XCTAssertEqual(M.partStyle(0, bpm: 124), 0)
        XCTAssertNil(M.partStyle(1, bpm: 130), "Techno — свой генератор")
        XCTAssertEqual(M.partStyle(2, bpm: 140), 1)
        XCTAssertEqual(M.partStyle(2, bpm: 172), 1, "D&B убран — Breaks при любом темпе")
        XCTAssertEqual(M.partStyle(3, bpm: 140), 2)
        XCTAssertEqual(M.partStyle(3, bpm: 90), 2, "R&B убран — Trap при любом темпе")
        XCTAssertEqual(M.partStyle(4, bpm: 110), 3)
        XCTAssertEqual(M.partStyle(5, bpm: 80), 4)
        XCTAssertEqual(M.styleKick(1), [0, 2, 10])
        XCTAssertEqual(M.styleKick(4), [])
    }

    func testProgressionAndKind() {
        var g = SystemRandomNumberGenerator()
        for ps in 0..<5 {
            var set: Int = 0
            for _ in 0..<1000 {
                let d: [Int] = M.styleProgression(ps, scale: scale, avoid: [1, 7, 6, 7], using: &g)
                XCTAssertEqual(d.first == 1 || M.styleTable(M.styleProgs[ps]).rows.contains(d), true)
                XCTAssertEqual(d.count, ps == 4 ? 2 : 4)
                XCTAssertNotEqual(d, [1, 7, 6, 7])
                if M.styleTable(M.styleProgs[ps]).rows.contains(d) {
                    set += 1
                } else {
                    for i in 1..<d.count { XCTAssertNotEqual(d[i], d[i - 1], "\(d)") }
                }
                let k: Int = M.styleKind(ps, using: &g)
                XCTAssertTrue(M.styleTable(M.styleKinds[ps]).rows.contains([k]))
            }
            XCTAssertGreaterThan(set, 580, "~75 % — из набора")
        }
    }

    /// Все ноты в гамме и в пределах страниц, не длиннее 32 шагов.
    func testInScaleAndPages() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<60 {
            for ps in 0..<5 {
                for role in roles {
                    for pages in 1...4 {
                        let r = part(role, ps, pages: pages, using: &g)
                        XCTAssertEqual(r.pat.count, pages)
                        for (pi, page) in r.pat.enumerated() {
                            for e in page {
                                XCTAssertTrue(inScale(e.note), "\(ps) \(role)")
                                XCTAssertTrue((0...127).contains(e.note))
                                XCTAssertTrue((0..<16).contains(e.step))
                                XCTAssertGreaterThanOrEqual(e.len, 1)
                                XCTAssertLessThanOrEqual(e.len, 32)
                                XCTAssertLessThanOrEqual(pi * 16 + e.step + e.len, pages * 16, "за выбранные страницы")
                                XCTAssertTrue((1...127).contains(e.vel ?? 0))
                            }
                        }
                    }
                }
            }
        }
    }

    /// House, Breaks: BASS, KEYS, LEAD — мимо бочки (своей сетки и дорожки KICK).
    func testAvoidKicks() {
        var g = SystemRandomNumberGenerator()
        let own: [Set<Int>] = [[0, 6, 12], [1, 8], [0, 4, 8, 12], [3, 10]]
        for _ in 0..<200 {
            for ps in 0..<2 {
                for role in [M.Role.bass, .keys, .lead] {
                    for kicks in [nil, own] {
                        let r = part(role, ps, pages: 4, kicks: kicks, using: &g)
                        for (pi, page) in r.pat.enumerated() {
                            let k: Set<Int> = kicks?[pi] ?? M.styleKick(ps)
                            for e in page { XCTAssertFalse(k.contains(e.step), "\(ps) \(role) \(e.step)") }
                        }
                    }
                }
            }
        }
    }

    /// Trap: 808 — ровно на шагах бочки (последняя страница — до шага 12), шаг 1 — корень; ноты не накладываются.
    func testTrapBass() {
        var g = SystemRandomNumberGenerator()
        let own: [Set<Int>] = [[0, 7, 10], [0, 3, 10, 14], [0, 10], [0, 6, 11, 13]]
        for _ in 0..<200 {
            for kicks in [nil, own] {
                let r = part(.bass, 2, pages: 4, kicks: kicks, using: &g)
                for (pi, page) in r.pat.enumerated() {
                    var k: Set<Int> = kicks?[pi] ?? [0, 10]
                    if pi == 3 { k = k.filter { $0 < 12 } }
                    XCTAssertEqual(Set(page.map { $0.step }), k)
                    let s: [SliceRhythm.Event] = page.sorted { $0.step < $1.step }
                    for i in 1..<Swift.max(1, s.count) { XCTAssertLessThanOrEqual(s[i - 1].step + s[i - 1].len, s[i].step) }
                    let first: SliceRhythm.Event? = s.first { $0.step == 0 }
                    let rn: Int = Scales.note(scale: scale, root: root, octave: 1,
                                              degree: Chords.degreeIndex(r.degrees[pi % r.degrees.count], scale: scale))
                    XCTAssertEqual(first?.note, rn, "шаг 1 — корень")
                }
            }
        }
    }

    /// Ноты BASS (Breaks, Pop) и LEAD (Pop) не накладываются; у Pop бас на шаге 1 каждой страницы.
    func testNoOverlap() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            for (role, ps) in [(M.Role.bass, 1), (.bass, 3), (.lead, 3), (.bass, 0)] {
                let r = part(role, ps, pages: 4, using: &g)
                var all: [(Int, Int)] = []
                for (pi, page) in r.pat.enumerated() {
                    for e in page { all.append((pi * 16 + e.step, e.len)) }
                    if role == .bass && ps == 3 { XCTAssertTrue(page.contains { $0.step == 0 }, "шаг 1 играет") }
                }
                all.sort { $0.0 < $1.0 }
                for i in 1..<Swift.max(1, all.count) { XCTAssertLessThanOrEqual(all[i - 1].0 + all[i - 1].1, all[i].0) }
            }
        }
    }

    /// PAD: аккорд — звуки одного типа kind от корня отрезка; без CHORD — одна нота; KEYS — тоже звуки аккорда.
    func testChordTones() {
        var g = SystemRandomNumberGenerator()
        let steps: [Int] = Scales.all[scale].steps
        for _ in 0..<200 {
            for ps in 0..<5 {
                for role in [M.Role.pad, .keys] {
                    let r = part(role, ps, pages: 4, using: &g)
                    let offs: Set<Int> = Set(Scales.chordDegrees[r.kind])
                    for (pi, page) in r.pat.enumerated() {
                        for st in Set(page.map { $0.step }) {
                            let notes: [Int] = page.filter { $0.step == st }.map { $0.note }
                            let ci: Int = ps == 4 ? (pi < 2 ? 0 : 1) : pi
                            let k: Int = Chords.degreeIndex(r.degrees[ci % r.degrees.count], scale: scale)
                            for x in notes {
                                let deg: Int = steps.firstIndex(of: ((x - root) % 12 + 12) % 12) ?? -1
                                let off: Int = ((deg - k) % 7 + 7) % 7
                                XCTAssertTrue(offs.map { $0 % 7 }.contains(off), "\(ps) \(role) \(notes)")
                            }
                        }
                    }
                    let one = part(.pad, ps, pages: 2, single: true, using: &g)
                    for page in one.pat { XCTAssertLessThanOrEqual(Set(page.map { $0.step }).count, page.count) }
                    for page in one.pat {
                        for st in Set(page.map { $0.step }) { XCTAssertEqual(page.filter { $0.step == st }.count, 1) }
                    }
                }
            }
        }
    }

    /// ARP: Breaks и Ambient — ритм из ячеек стиля; House, Trap, Pop — все шаги сетки RATE (Trap — в 13–16
    /// последней страницы каждая вторая).
    func testArpRhythm() {
        var g = SystemRandomNumberGenerator()
        let cells: [[Set<Int>]] = [1, 4].map { ps in M.styleTable(M.styleArpCells[ps]).rows.map { Set($0) } }
        for _ in 0..<100 {
            for ps in 0..<5 {
                var a = TrackArp()
                a.rate = [0, 2].randomElement(using: &g) ?? 2
                let every: Int = Arp.gridSteps[a.rate]
                let r = part(.arp, ps, pages: 3, arp: a, using: &g)
                for (pi, page) in r.pat.enumerated() {
                    let st: Set<Int> = Set(page.map { $0.step })
                    for s in st { XCTAssertEqual(s % every, 0, "на сетке RATE") }
                    if ps == 1 || ps == 4 {
                        XCTAssertTrue(cells[ps == 1 ? 0 : 1].contains { st.isSubset(of: $0) })
                    } else if ps != 2 || pi < 2 {
                        XCTAssertEqual(st.count, 16 / every, "все шаги сетки")
                    }
                }
            }
        }
    }

    /// Из p-lock — только Level.
    func testOnlyVelocityLocks() {
        var g = SystemRandomNumberGenerator()
        var t = Track(index: 0)
        t.sample = "mi:24"
        t.pages = [Track.emptyPage(), Track.emptyPage()]
        t.length = 32
        var ids = Set<String>()
        for _ in 0..<20 {
            for ps in 0..<5 {
                for role in roles {
                    let d: [Int] = M.styleProgression(ps, scale: scale, avoid: nil, using: &g)
                    t.writeStylePart(role, style: ps, pages: 0...1, degrees: d, kind: M.styleKind(ps, using: &g),
                                     scale: scale, root: root, octave: 3, kicks: nil, using: &g)
                    ids.formUnion(t.pages.flatMap { $0 }.flatMap { $0.locks.keys })
                }
            }
        }
        XCTAssertTrue(ids.isSubset(of: ["level"]), "\(ids)")
    }
}
