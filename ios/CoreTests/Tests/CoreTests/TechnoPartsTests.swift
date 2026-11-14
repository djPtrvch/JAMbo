import XCTest
@testable import Core

/// Случайные BASS, PAD, LEAD в стиле Techno (hypnotic; TechnoParts.swift, HypnoticLead.swift).
final class TechnoPartsTests: XCTestCase {
    typealias M = MelodyRhythm
    let style: Int = 1
    let bpm: Double = 130
    let scale: Int = 1
    let root: Int = 9

    func inScale(_ note: Int) -> Bool {
        return Scales.all[scale].steps.contains(((note - root) % 12 + 12) % 12)
    }

    func progressions(using g: inout Rng) -> [[Int]] {
        return [[1], [1, 7], [1, 6], M.technoProgression(using: &g)]
    }

    func testProgression() {
        var g = SystemRandomNumberGenerator()
        var one: Int = 0
        for _ in 0..<2000 {
            let d: [Int] = M.technoProgression(using: &g)
            XCTAssertTrue(M.isTechnoProgression(d))
            if d == [1] { one += 1 }
        }
        XCTAssertTrue((1250...1550).contains(one), "~70 % — один аккорд")
        XCTAssertFalse(M.isTechnoProgression([1, 6, 4, 5]))
        // Смена — целыми страницами посередине; одна страница — один аккорд.
        XCTAssertEqual((0..<4).map { M.technoChord(page: $0, pages: 4, chords: 2) }, [0, 0, 1, 1])
        XCTAssertEqual((0..<2).map { M.technoChord(page: $0, pages: 2, chords: 2) }, [0, 1])
        XCTAssertEqual(M.technoChord(page: 0, pages: 1, chords: 2), 0)
    }

    func testBass() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            for pages in 1...4 {
                for d in progressions(using: &g) {
                    let lens: [Int] = Array(repeating: 16, count: pages)
                    let pat = M.bass(style: style, bpm: bpm, lens: lens, degrees: d, scale: scale, root: root,
                                     octave: 1, using: &g)
                    XCTAssertEqual(pat.count, pages, "ничего за пределами выбранных страниц")
                    var all: Int = 0
                    var roots: Int = 0
                    for (pi, page) in pat.enumerated() {
                        let ci: Int = M.technoChord(page: pi, pages: pages, chords: d.count)
                        let rootNote: Int = Scales.note(scale: scale, root: root, octave: 1,
                                                        degree: Chords.degreeIndex(d[ci], scale: scale))
                        var others: Int = 0
                        for e in page {
                            XCTAssertTrue(inScale(e.note))
                            XCTAssertTrue((0..<16).contains(e.step))
                            XCTAssertEqual(e.len, 1)
                            XCTAssertFalse(M.defaultKick.contains(e.step), "мимо бочки")
                            if e.note == rootNote { roots += 1 } else {
                                others += 1
                                XCTAssertGreaterThanOrEqual(e.step, 7, "не-корень — на шагах 8–16")
                            }
                            if e.step % 4 == 2 { XCTAssertEqual(e.vel, 127) } else { XCTAssertNotNil(e.chance) }
                            if e.ratchet != nil {
                                XCTAssertEqual(pi, pages - 1)
                                XCTAssertGreaterThanOrEqual(e.step, 14)
                            }
                        }
                        all += page.count
                        XCTAssertLessThanOrEqual(others, 2, "не больше 2 не-корней на страницу")
                        let steps: Set<Int> = Set(page.map { $0.step })
                        XCTAssertTrue([2, 6, 10].allSatisfy { steps.contains($0) }, "офбиты на каждой странице")
                        if pi < pages - 1 || pages == 1 { XCTAssertTrue(steps.contains(14)) }
                    }
                    XCTAssertLessThanOrEqual(pat.flatMap { $0 }.filter { $0.ratchet != nil }.count, 1)
                    XCTAssertGreaterThanOrEqual(Double(roots), Double(all) * 0.85, "корень — не меньше 85 %")
                }
            }
        }
    }

    func testBassFollowsKickTrack() {
        var g = SystemRandomNumberGenerator()
        var p = Project()
        var kick = Track(index: 0)
        kick.sample = SynthKey.key(Jambo.drum)
        kick.pages = [Track.emptyPage()]
        kick.length = 16
        for s in [0, 3, 8, 11] { kick.toggleStep(s, notes: [60]) }
        p.tracks = [kick]
        let grid: [Set<Int>] = p.kickGrid(pages: 0...1)
        XCTAssertEqual(grid, [[0, 3, 8, 11], [0, 3, 8, 11]], "страница бочки — по кругу её клипа")
        XCTAssertEqual(Project().kickGrid(pages: 0...0), [M.defaultKick], "без бочки — 1, 5, 9, 13")
        for _ in 0..<200 {
            let pat = M.bass(style: style, bpm: bpm, lens: [16, 16], degrees: [1], scale: scale, root: root,
                             octave: 1, kicks: grid, using: &g)
            let lead = M.lead(style: style, bpm: bpm, lens: [16, 16], degrees: [1], scale: scale, root: root,
                              octave: 3, kicks: grid, using: &g)
            for e in (pat + lead).flatMap({ $0 }) { XCTAssertFalse(grid[0].contains(e.step), "мимо реальной бочки") }
        }
    }

    func testPad() {
        var g = SystemRandomNumberGenerator()
        let kinds: [[Int]] = M.technoKinds
        for _ in 0..<300 {
            for pages in 1...4 {
                for d in progressions(using: &g) {
                    let lens: [Int] = Array(repeating: 16, count: pages)
                    let pat = M.technoPad(lens: lens, degrees: d, scale: scale, root: root, octave: 3, using: &g)
                    XCTAssertEqual(pat.count, pages)
                    let hits = pat.enumerated().flatMap { (pi, page) in page.map { (pi * 16 + $0.step, $0) } }
                    XCTAssertFalse(hits.isEmpty)
                    for (a, e) in hits {
                        XCTAssertTrue(inScale(e.note))
                        XCTAssertLessThanOrEqual(a + e.len, pages * 16, "не за выбранные страницы")
                        XCTAssertNil(e.chance)
                    }
                    // Длина удара — 32 (16 — одна страница или аккорд на одну страницу).
                    let starts: [Int] = Array(Set(hits.map { $0.0 })).sorted()
                    for s in starts {
                        let l: Int = hits.first { $0.0 == s }?.1.len ?? 0
                        XCTAssertTrue(l == 32 || l == 16, "удар \(l)")
                        XCTAssertEqual(s % 16, 0)
                    }
                    // Один тип аккорда: ступени всех ударов (от корня аккорда) — из одного набора.
                    var used = Set<Int>()
                    var tops: [Int] = []
                    let n: Int = 7
                    for s in starts {
                        let notes: [Int] = hits.filter { $0.0 == s }.map { $0.1.note }.sorted()
                        let ci: Int = M.technoChord(page: s / 16, pages: pages, chords: d.count)
                        let r: Int = Chords.degreeIndex(d[ci], scale: scale)
                        for x in notes {
                            let deg: Int = Scales.all[scale].steps.firstIndex(of: ((x - root) % 12 + 12) % 12) ?? -1
                            used.insert(Scales.wrap(deg - r, n))
                        }
                        if let t = notes.last { tops.append(t) }
                    }
                    XCTAssertTrue(kinds.contains { k in used.isSubset(of: Set(k.map { $0 % n })) }, "\(used)")
                    // Верхний голос при смене — не дальше 2 ступеней (≤ 4 полутонов).
                    for i in tops.indices.dropFirst() { XCTAssertLessThanOrEqual(Swift.abs(tops[i] - tops[i - 1]), 4) }
                }
            }
        }
    }

    func testLead() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            for pages in 1...4 {
                let lens: [Int] = Array(repeating: 16, count: pages)
                let pat = M.lead(style: style, bpm: bpm, lens: lens, degrees: [1], scale: scale, root: root,
                                 octave: 3, using: &g)
                XCTAssertEqual(pat.count, pages)
                let all = pat.flatMap { $0 }
                XCTAssertTrue((1...3).contains(Set(all.map { $0.note }).count), "1–3 высоты на ячейку")
                for e in all {
                    XCTAssertTrue(inScale(e.note))
                    XCTAssertFalse(M.defaultKick.contains(e.step), "мимо бочки")
                    XCTAssertTrue((1...2).contains(e.len))
                    XCTAssertNotNil(e.pan)
                    let a: Double = Swift.abs(e.pan ?? 0)
                    XCTAssertTrue((10...22).contains(a), "Pan 15–35 %")
                    if let c = e.chance { XCTAssertTrue((80...95).contains(c)) }
                }
            }
        }
    }

    /// Ансамбль Techno одной правкой проекта: одна запись UNDO возвращает все дорожки.
    func testOneUndo() {
        var g = SystemRandomNumberGenerator()
        var p = Project()
        var tracks: [Track] = []
        for i in 0..<3 {
            var t = Track(index: i)
            t.sample = "mi:24"
            t.pages = [Track.emptyPage(), Track.emptyPage()]
            t.length = 32
            tracks.append(t)
        }
        p.tracks = tracks
        var h = History<Project>()
        let before: Project = p
        let d: [Int] = M.technoProgression(using: &g)
        p.tracks[0].writeRandomBass(pages: 0...1, degrees: d, scale: scale, root: root, octave: 1, bpm: bpm,
                                    kicks: p.kickGrid(pages: 0...1), using: &g)
        p.tracks[1].writeTechnoPad(pages: 0...1, degrees: d, scale: scale, root: root, octave: 3, using: &g)
        p.tracks[2].writeRandomLead(pages: 0...1, degrees: d, scale: scale, root: root, octave: 3, bpm: bpm,
                                    kicks: p.kickGrid(pages: 0...1), using: &g)
        h.record(before: before, after: p)
        XCTAssertNotEqual(p, before)
        let back: Project? = h.undo(p)
        XCTAssertEqual(back, before)
        XCTAssertFalse(h.canUndo, "одна запись")
    }

    /// p-lock Chance, Ratchet, Pan пишутся на шаг; параметры звука — нет.
    func testLocksWritten() {
        var g = SystemRandomNumberGenerator()
        var t = Track(index: 0)
        t.sample = "mi:24"
        t.pages = [Track.emptyPage()]
        t.writeSlices([[SliceRhythm.Event(step: 2, note: 60, len: 1, vel: 90, chance: 80, ratchet: 1, pan: -12)]],
                      pages: 0...0)
        XCTAssertEqual(t.pages[0][2].locks["prob"], 80)
        XCTAssertEqual(t.pages[0][2].locks["ratchet"], 1)
        XCTAssertEqual(t.pages[0][2].locks["pan"], -12)
        for _ in 0..<50 {
            t.writeRandomBass(pages: 0...0, degrees: [1], scale: scale, root: root, octave: 1, bpm: bpm, using: &g)
            let ids = Set(t.pages[0].flatMap { $0.locks.keys })
            XCTAssertTrue(ids.isSubset(of: ["level", "prob", "ratchet", "pan"]), "\(ids)")
        }
    }
}
