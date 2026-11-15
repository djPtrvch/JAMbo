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
                    let pat = M.technoBass(lens: lens, degrees: d, scale: scale, root: root,
                                           octave: 1, kicks: nil, using: &g)
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
                            if e.note == rootNote { roots += 1 } else { others += 1 }
                            if e.step % 4 == 2 { XCTAssertEqual(e.vel, 127) } else { XCTAssertLessThanOrEqual(e.vel ?? 127, 114) }
                        }
                        all += page.count
                        XCTAssertLessThanOrEqual(others, 2, "не больше 2 не-корней на страницу")
                        let steps: Set<Int> = Set(page.map { $0.step })
                        XCTAssertTrue([2, 6, 10].allSatisfy { steps.contains($0) }, "офбиты на каждой странице")
                        if pi < pages - 1 || pages == 1 { XCTAssertTrue(steps.contains(14)) }
                    }
                    XCTAssertGreaterThanOrEqual(Double(roots), Double(all) * 0.75, "корень — почти всегда")
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
            let pat = M.technoBass(lens: [16, 16], degrees: [1], scale: scale, root: root,
                             octave: 1, kicks: grid, using: &g)
            let lead = M.hypnoticLead(lens: [16, 16], degrees: [1], scale: scale, root: root,
                              octave: 3, kicks: grid, using: &g)
            for e in (pat + lead).flatMap({ $0 }) { XCTAssertFalse(grid[0].contains(e.step), "мимо реальной бочки") }
        }
    }

    func testPad() {
        var g = SystemRandomNumberGenerator()
        let kinds: [[Int]] = M.technoKinds
        for _ in 0..<300 {
            for pages in 1...4 {
                for kind in 0..<3 {
                    let lens: [Int] = Array(repeating: 16, count: pages)
                    let pat = M.technoPad(lens: lens, kind: kind, scale: scale, root: root, octave: 3, using: &g)
                    XCTAssertEqual(pat.count, pages)
                    let hits = pat.enumerated().flatMap { (pi, page) in page.map { (pi * 16 + $0.step, $0) } }
                    XCTAssertFalse(hits.isEmpty)
                    for (a, e) in hits {
                        XCTAssertTrue(inScale(e.note))
                        XCTAssertLessThanOrEqual(a + e.len, pages * 16, "не за выбранные страницы")
                    }
                    // Удары — с начала страницы, 16 или 32 шага; прогрессия: от 2 страниц аккордов больше одного.
                    let starts: [Int] = Array(Set(hits.map { $0.0 })).sorted()
                    for s in starts {
                        let l: Int = hits.first { $0.0 == s }?.1.len ?? 0
                        XCTAssertTrue(l == 32 || l == 16, "удар \(l)")
                        XCTAssertEqual(s % 16, 0)
                    }
                    let chords: Set<[Int]> = Set(starts.map { s in hits.filter { $0.0 == s }.map { $0.1.note }.sorted() })
                    if pages > 2 { XCTAssertGreaterThan(chords.count, 1, "прогрессия") }
                    // Один тип аккорда: ступени всех ударов (от корня аккорда) — из одного набора.
                    var used = Set<Int>()
                    var tops: [Int] = []
                    let n: Int = 7
                    for s in starts {
                        let notes: [Int] = hits.filter { $0.0 == s }.map { $0.1.note }.sorted()
                        let r: Int = Scales.all[scale].steps.firstIndex(of: ((notes[0] - root) % 12 + 12) % 12) ?? 0
                        for x in notes {
                            let deg: Int = Scales.all[scale].steps.firstIndex(of: ((x - root) % 12 + 12) % 12) ?? -1
                            used.insert(Scales.wrap(deg - r, n))
                        }
                        if let t = notes.last { tops.append(t) }
                    }
                    XCTAssertTrue(used.isSubset(of: Set(kinds[kind].map { $0 % n })), "один тип: \(used)")
                    // Верхний голос при смене — не дальше 2 ступеней (≤ 4 полутонов).
                    for i in tops.indices.dropFirst() { XCTAssertLessThanOrEqual(Swift.abs(tops[i] - tops[i - 1]), 4) }
                }
            }
        }
    }

    /// PAD без CHORD — одна длинная нота (корень аккорда), 16 или 32 шага.
    func testPadSingle() {
        var g = SystemRandomNumberGenerator()
        var lens32: Int = 0
        for _ in 0..<200 {
            let pat = M.technoPad(lens: [16, 16, 16, 16], kind: 0, scale: scale, root: root, octave: 3, single: true,
                                  using: &g)
            let hits = pat.enumerated().flatMap { (pi, page) in page.map { (pi * 16 + $0.step, $0) } }
            XCTAssertEqual(Set(hits.map { $0.0 }).count, hits.count, "одна нота на удар")
            for (_, e) in hits { XCTAssertTrue(e.len == 16 || e.len == 32) }
            if hits.contains(where: { $0.1.len == 32 }) { lens32 += 1 }
        }
        XCTAssertGreaterThan(lens32, 50, "бывают ноты на 32 шага")
    }

    func testLead() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            for pages in 1...4 {
                let lens: [Int] = Array(repeating: 16, count: pages)
                let pat = M.hypnoticLead(lens: lens, degrees: [1], scale: scale, root: root,
                                 octave: 3, using: &g)
                XCTAssertEqual(pat.count, pages)
                let all = pat.flatMap { $0 }
                XCTAssertTrue((1...3).contains(Set(all.map { $0.note }).count), "1–3 высоты на ячейку")
                for e in all {
                    XCTAssertTrue(inScale(e.note))
                    XCTAssertFalse(M.defaultKick.contains(e.step), "мимо бочки")
                    XCTAssertEqual(e.len, 1, "одиночные ноты")
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
        p.tracks[0].writeTechnoPart(.bass, pages: 0...1, degrees: d, kind: 0, scale: scale, root: root, octave: 1,
                                    kicks: p.kickGrid(pages: 0...1), using: &g)
        p.tracks[1].writeTechnoPart(.pad, pages: 0...1, degrees: d, kind: 0, scale: scale, root: root, octave: 3, kicks: nil,
                                    using: &g)
        p.tracks[2].writeTechnoPart(.lead, pages: 0...1, degrees: d, kind: 0, scale: scale, root: root, octave: 3,
                                    kicks: p.kickGrid(pages: 0...1), using: &g)
        h.record(before: before, after: p)
        XCTAssertNotEqual(p, before)
        let back: Project? = h.undo(p)
        XCTAssertEqual(back, before)
        XCTAssertFalse(h.canUndo, "одна запись")
    }

    /// Из p-lock — только Level: ни Chance, ни Ratchet, ни Pan, ни параметров звука.
    func testOnlyVelocityLocks() {
        var g = SystemRandomNumberGenerator()
        var t = Track(index: 0)
        t.sample = "mi:24"
        t.pages = [Track.emptyPage(), Track.emptyPage()]
        t.length = 32
        t.arp.mode = true
        for _ in 0..<50 {
            let d: [Int] = M.technoProgression(using: &g)
            t.writeTechnoPart(.bass, pages: 0...1, degrees: d, kind: 0, scale: scale, root: root, octave: 1, kicks: nil, using: &g)
            var ids = Set(t.pages.flatMap { $0 }.flatMap { $0.locks.keys })
            t.writeTechnoPart(.lead, pages: 0...1, degrees: d, kind: 0, scale: scale, root: root, octave: 3, kicks: nil, using: &g)
            ids.formUnion(t.pages.flatMap { $0 }.flatMap { $0.locks.keys })
            t.writeTechnoPart(.pad, pages: 0...1, degrees: d, kind: 1, scale: scale, root: root, octave: 3, kicks: nil, using: &g)
            ids.formUnion(t.pages.flatMap { $0 }.flatMap { $0.locks.keys })
            t.writeTechnoPart(.keys, pages: 0...1, degrees: d, kind: 2, scale: scale, root: root, octave: 4, kicks: nil, using: &g)
            ids.formUnion(t.pages.flatMap { $0 }.flatMap { $0.locks.keys })
            t.writeTechnoPart(.arp, pages: 0...1, degrees: d, kind: 0, scale: scale, root: root, octave: 4, kicks: nil, using: &g)
            ids.formUnion(t.pages.flatMap { $0 }.flatMap { $0.locks.keys })
            XCTAssertTrue(ids.isSubset(of: ["level"]), "\(ids)")
        }
    }

    // MARK: — KEYS

    func testKeys() {
        var g = SystemRandomNumberGenerator()
        let n: Int = 7
        for _ in 0..<200 {
            for pages in 1...4 {
                for d in progressions(using: &g) {
                    for kind in 0..<3 {
                        let lens: [Int] = Array(repeating: 16, count: pages)
                        let pat = M.technoKeys(lens: lens, degrees: d, kind: kind, scale: scale, root: root,
                                               octave: 4, kicks: nil, using: &g)
                        XCTAssertEqual(pat.count, pages)
                        // Шаги — из одной ячейки S1…S7 (средние страницы — стаб снят или добавлен).
                        let first: Set<Int> = Set(pat[0].map { $0.step })
                        XCTAssertTrue(M.technoKeysCells.contains { Set($0).subtracting(M.defaultKick) == first },
                                      "основа — ячейка: \(first.sorted())")
                        var tops: [Int] = []
                        for (pi, page) in pat.enumerated() {
                            let ci: Int = M.technoChord(page: pi, pages: pages, chords: d.count)
                            let r: Int = Chords.degreeIndex(d[ci], scale: scale)
                            for st in Set(page.map { $0.step }) {
                                XCTAssertFalse(M.defaultKick.contains(st), "мимо бочки")
                                let notes: [Int] = page.filter { $0.step == st }.map { $0.note }.sorted()
                                XCTAssertEqual(notes.count, 3, "три голоса")
                                var cls = Set<Int>()
                                for x in notes {
                                    XCTAssertTrue(inScale(x))
                                    XCTAssertLessThanOrEqual(x, 127)
                                    let deg: Int = Scales.all[scale].steps.firstIndex(of: ((x - root) % 12 + 12) % 12) ?? -1
                                    cls.insert(Scales.wrap(deg - r, n))
                                }
                                XCTAssertEqual(cls, Set(M.technoKeysVoices[kind].map { $0 % n }), "тип \(kind)")
                                if kind < 2 { XCTAssertFalse(cls.contains(0), "без корня") }
                                if let t = notes.last { tops.append(t) }
                                XCTAssertTrue(page.filter { $0.step == st }.allSatisfy { $0.len == 1 })
                            }
                            XCTAssertLessThanOrEqual(Set(page.map { $0.step }).subtracting(first).count, 1, "не больше одного нового стаба")
                        }
                        for i in tops.indices.dropFirst() { XCTAssertLessThanOrEqual(Swift.abs(tops[i] - tops[i - 1]), 4) }
                    }
                }
            }
        }
    }

    // MARK: — ARP

    func testArpCycle() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            for dir in 0..<6 {
                for rate in 0..<5 {
                    let pages: Int = 4
                    let d: [Int] = [1, 7]
                    let lens: [Int] = Array(repeating: 16, count: pages)
                    let notes = Arp.technoSteps(lens: lens, degrees: d, kind: 0, scale: scale, root: root, octave: 4,
                                                dir: dir, octaves: 2, rate: rate, gate: 0.5, kicks: nil, using: &g)
                    XCTAssertFalse(notes.isEmpty)
                    let every: Int = Arp.gridSteps[rate]
                    for (j, a) in notes.enumerated() {
                        XCTAssertTrue(inScale(a.note))
                        XCTAssertLessThanOrEqual(a.note, 127)
                        XCTAssertTrue((0..<64).contains(a.step))
                        XCTAssertFalse(M.defaultKick.contains(a.step % 16), "мимо бочки")
                        XCTAssertEqual(a.step % every, 0)
                        if j + 1 < notes.count { XCTAssertLessThanOrEqual(a.step + a.len, notes[j + 1].step) }
                        XCTAssertEqual(a.vel, a.step % 4 == 2 ? 127 : a.vel)
                    }
                    if rate == 0 { XCTAssertTrue(notes.allSatisfy { $0.step % 4 == 2 }, "1/8 — офбиты") }
                    // Период: индекс в ряду аккорда для слота k — один и тот же через N слотов, через страницы и смену.
                    var byChord: [[Int]] = [[], []]
                    for ci in 0..<2 {
                        let r: Int = Chords.degreeIndex(d[ci], scale: scale)
                        var row: [Int] = [0, 4, 6].map { M.technoNote(r + $0, scale: scale, root: root, octave: 4) }.sorted()
                        row += row.map { $0 + 12 }
                        byChord[ci] = row
                    }
                    // Фигура сдвигается по ударам: индексы нот подряд — с периодом N (3…7), через страницы и смену.
                    var idx: [Int] = []
                    for a in notes where a.step < 48 {
                        let ci: Int = a.step < 32 ? 0 : 1
                        guard let i = byChord[ci].firstIndex(of: a.note) else {
                            XCTFail("нота из звуков аккорда")
                            continue
                        }
                        idx.append(i)
                    }
                    var period: Int = 0
                    for n in 3...7 {
                        if dir == Arp.random || dir == Arp.order || dir >= 2 { break }
                        let ok: Bool = idx.indices.allSatisfy { k in k + n >= idx.count || idx[k + n] == idx[k] }
                        if ok && period == 0 { period = n }
                    }
                    if dir < 2 { XCTAssertGreaterThan(period, 0, "цикл с периодом N") }
                }
            }
        }
    }

    /// Ритм арпеджио Techno — не только «подряд мимо бочки»: среди рисунков на 1/16 есть с паузами вне бочки.
    func testArpRhythmVaries() {
        var g = SystemRandomNumberGenerator()
        var shapes = Set<[Int]>()
        var withRests: Int = 0
        for _ in 0..<100 {
            let notes = Arp.technoSteps(lens: [16, 16], degrees: [1], kind: 0, scale: scale, root: root, octave: 4,
                                        dir: Arp.up, octaves: 1, rate: 2, gate: 0.5, kicks: nil, using: &g)
            let steps: [Int] = notes.filter { $0.step < 16 }.map { $0.step }
            shapes.insert(steps)
            if steps.count < 12 { withRests += 1 }
            XCTAssertGreaterThanOrEqual(steps.count, 6, "мимо бочки — не меньше половины шагов")
        }
        XCTAssertGreaterThan(withRests, 50)
        XCTAssertGreaterThan(shapes.count, 15)
    }
}
