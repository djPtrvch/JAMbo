import Foundation

// Случайные BASS и PAD в стиле Techno — hypnotic (docs/ai/sequencer.md, «Случайная партия»). Гармония одна:
// 70 % — один аккорд на тонике, 30 % — смена 1 → 7 или 6 посередине диапазона на границе страниц. Бас катится
// шестнадцатыми по одной ячейке мимо бочки, пэд — открытый аккорд со своей прогрессией (аккорд на страницу). Из
// p-lock — только Velocity; параметры звука не трогаются. BASS, LEAD, KEYS и ARP — общий генератор
// TechnoRun.swift.

extension MelodyRhythm {
    /// Рисунок дорожки стиля style (вариант — по bpm) — Techno.
    public static func isTechno(style: Int, bpm: Double) -> Bool {
        return DrumRhythm.groove(style, bpm: bpm) == .techno
    }

    /// Прогрессия Techno: 70 % — [1], 30 % — [1, 7] или [1, 6].
    public static func technoProgression(using g: inout Rng) -> [Int] {
        if Double.random(in: 0..<1, using: &g) < 0.7 { return [1] }
        let second: Int = Bool.random(using: &g) ? 7 : 6
        return [1, second]
    }

    /// Прогрессия годится для Techno: одна гармония на тонике или 1 → 7/6.
    public static func isTechnoProgression(_ d: [Int]) -> Bool {
        if d == [1] { return true }
        return d.count == 2 && d[0] == 1 && (d[1] == 6 || d[1] == 7)
    }

    /// Номер аккорда на играющей странице pi из pages: аккорды — целыми страницами (при двух — смена посередине,
    /// при нечётном числе страниц первый аккорд на странице дольше); одна страница — один аккорд.
    static func technoChord(page pi: Int, pages: Int, chords: Int) -> Int {
        if chords < 2 || pages < 2 { return 0 }
        return Swift.min(chords - 1, pi * chords / pages)
    }

    /// Шаги бочки по умолчанию: 1, 5, 9, 13.
    public static let defaultKick: Set<Int> = [0, 4, 8, 12]

    /// Шаги бочки страницы p (номер в lens); нет сетки — 1, 5, 9, 13.
    static func kickOf(_ kicks: [Set<Int>]?, _ p: Int) -> Set<Int> {
        guard let k = kicks, p >= 0, p < k.count else { return defaultKick }
        return k[p]
    }

    /// Таблица строкой (ради объёма сборки): ряды через пробел, в ряду — числа 0…15 шестнадцатеричными цифрами.
    static func hexRows(_ s: String) -> [[Int]] {
        return s.split(separator: " ").map { w in w.map { Int(String($0), radix: 16) ?? 0 } }
    }

    /// Офбит: шаги 3, 7, 11, 15.
    static func isOffbeat(_ s: Int) -> Bool { return s % 4 == 2 }

    // MARK: — BASS

    /// Ячейки ритма баса (шаги 0…15; A…H) и их веса; офбиты — в каждой.
    static let technoBassCells: [[Int]] = hexRows("26ae 236abe 1235679abdef 2367abef 256ade 267aef 12569ade 2356abde")
    static let technoBassWeights: [Double] = [5, 15, 20, 20, 5, 10, 10, 15]

    // MARK: — PAD

    /// Типы аккорда Techno (ступени от корня): m7, m9, квинта + септима (без терции); один на прогрессию — общий у
    /// PAD, KEYS, ARP (AppModel.lastRandomKind).
    static let technoKinds: [[Int]] = hexRows("0246 02468 046")

    /// Прогрессии пэда Techno (ступени на страницы 1…4): своя у PAD, первая — тоника; гармония баса и лида — общая.
    static let padProgressions: [[Int]] = hexRows("1767 1671 1776 1617 1716 1667")

    /// Прогрессия пэда на pages страниц: аккорд на страницу (первые pages ступеней одной из прогрессий).
    public static func padProgression(pages: Int, using g: inout Rng) -> [Int] {
        let p: [Int] = padProgressions.randomElement(using: &g) ?? padProgressions[0]
        var out: [Int] = []
        for i in 0..<Swift.max(1, pages) { out.append(p[i % p.count]) }
        return out
    }

    /// Пэд Techno на страницы lens: своя прогрессия (padProgression; одна страница — тоника), аккорд на 1 или 2
    /// страницы (16 или 32 шага; наугад на рисунок, 2 — при 2 страницах и больше), тип аккорда kind (technoKinds; один
    /// на прогрессию), открытое расположение: корень внизу, остальные звуки тесно октавой выше (у следующего аккорда
    /// обращение — верхний голос ближе всего к прежнему); single (CHORD выключен) — одна нота, корень аккорда. Удар —
    /// с началом аккорда, повтор каждые 32 шага, если аккорд держится дольше. Velocity: первый удар аккорда 75–85 %,
    /// повторные 60–75 %.
    static func technoPad(lens: [Int], kind kindIndex: Int, scale: Int, root: Int, octave oct: Int,
                          single: Bool = false, using g: inout Rng) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        guard let lastPage = playing.last else { return out }
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let kind: [Int] = technoKinds[Scales.wrap(kindIndex, technoKinds.count)]
        let upper: [Int] = Array(kind.dropFirst())
        let count: Int = playing.count
        let span: Int = count >= 2 && Bool.random(using: &g) ? 2 : 1
        let chords: [Int] = padProgression(pages: (count + span - 1) / span, using: &g)
        let degrees: [Int] = (0..<count).map { chords[$0 / span] }
        var voices: [[Int]] = []
        var prevTop: Int? = nil
        for d in degrees {
            let r: Int = Chords.degreeIndex(d, scale: scale)
            // Корень внизу, остальные — тесно (closeVoicing, верх ближе к прежнему) октавой выше корня.
            let up: [Int] = closeVoicing(r, upper, n: n, prevTop: prevTop)
            var v: [Int] = [r]
            for x in up {
                var y: Int = x + n
                while y <= r { y += n }
                v.append(y)
            }
            voices.append(single ? [r] : v)
            prevTop = up.last
        }
        let per: Int = Params.stepsPerPage
        let endAbs: Int = (count - 1) * per + lens[lastPage]
        var pi: Int = 0
        while pi < count {
            var pj: Int = pi
            while pj + 1 < count && degrees[pj + 1] == degrees[pi] { pj += 1 }
            let a: Int = pi * per
            let b: Int = Swift.min(endAbs, (pj + 1) * per)
            var s: Int = a
            var first: Bool = true
            while s < b {
                let len: Int = Swift.min(2 * per, b - s)
                let p: Int = playing[s / per]
                let vel: Double = first ? Double(Int.random(in: 96...107, using: &g))
                                        : Double(Int.random(in: 77...95, using: &g))
                for dg in voices[pi] {
                    var note: Int = Scales.note(scale: scale, root: root, octave: oct, degree: dg)
                    while note > 127 { note -= 12 }
                    if note < 0 { continue }
                    out[p].append(SliceRhythm.Event(step: s % per, note: note, len: len, vel: vel))
                }
                first = false
                s += 2 * per
            }
            pi = pj + 1
        }
        return out
    }
}

extension Project {
    /// Шаги бочки страниц range (для баса и лида Techno): первая дорожка KICK (движок или сэмпл по имени) с тригами
    /// в открытом клипе; странице range соответствует её страница, играющая одновременно (по кругу длины клипа
    /// бочки). Страница бочки без тригов или бочки нет — fallback (1, 5, 9, 13; у стилей — MelodyRhythm.styleKick).
    public func kickGrid(pages range: ClosedRange<Int>, fallback: Set<Int> = MelodyRhythm.defaultKick) -> [Set<Int>] {
        let fs: [String: String] = files
        let kt: Track? = tracks.first { t in
            t.drumRoleBy(name: fs[t.sample]) == .kick && t.pages.contains { pg in pg.contains { $0.on } }
        }
        let per: Int = Params.stepsPerPage
        var out: [Set<Int>] = []
        for i in 0..<range.count {
            guard let t = kt else {
                out.append(fallback)
                continue
            }
            let kp: Int = Swift.max(1, Swift.min(t.pages.count, (t.length + per - 1) / per))
            let page: Int = (range.lowerBound + i) % kp
            var steps: Set<Int> = []
            for (s, st) in t.pages[page].enumerated() where st.on && page * per + s < t.length { steps.insert(s) }
            out.append(steps.isEmpty ? fallback : steps)
        }
        return out
    }
}
