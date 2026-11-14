import Foundation

// Случайные BASS и PAD в стиле Techno — hypnotic (docs/ai/sequencer.md, «Случайная партия»). Гармония одна:
// 70 % — один аккорд на тонике, 30 % — смена 1 → 7 или 6 посередине диапазона на границе страниц. Бас катится
// шестнадцатыми по одной ячейке мимо бочки, пэд — широкий аккорд со своей прогрессией (аккорд на страницу). Из
// p-lock — только Velocity; параметры звука не трогаются. LEAD — HypnoticLead.swift, KEYS и ARP — TechnoKeys.swift.

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

    /// Офбит: шаги 3, 7, 11, 15.
    static func isOffbeat(_ s: Int) -> Bool { return s % 4 == 2 }

    // MARK: — BASS

    /// Ячейки ритма баса (шаги 0…15; A…H) и их веса; офбиты — в каждой.
    static let technoBassCells: [[Int]] = [
        [2, 6, 10, 14],
        [2, 3, 6, 10, 11, 14],
        [1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15],
        [2, 3, 6, 7, 10, 11, 14, 15],
        [2, 5, 6, 10, 13, 14],
        [2, 6, 7, 10, 14, 15],
        [1, 2, 5, 6, 9, 10, 13, 14],
        [2, 3, 5, 6, 10, 11, 13, 14],
    ]
    static let technoBassWeights: [Double] = [5, 15, 20, 20, 5, 10, 10, 15]

    /// Вариация страницы: 1–2 шестнадцатых (не офбиты, не бочка) добавлены или убраны.
    static func technoVary(_ steps: [Int], len: Int, kick: Set<Int>, using g: inout Rng) -> [Int] {
        var out: [Int] = steps
        let times: Int = Int.random(in: 1...2, using: &g)
        for _ in 0..<times {
            let present: [Int] = out.filter { !isOffbeat($0) }
            let free: [Int] = (0..<len).filter { !out.contains($0) && !isOffbeat($0) && !kick.contains($0) }
            let add: Bool = present.isEmpty || (!free.isEmpty && Bool.random(using: &g))
            if add, let s = free.randomElement(using: &g) {
                out.append(s)
            } else if let s = present.randomElement(using: &g) {
                out.removeAll { $0 == s }
            }
        }
        return out.sorted()
    }

    /// Бас Techno на страницы lens по прогрессии degrees; kicks — шаги бочки страниц (nil — 1, 5, 9, 13). Одна
    /// ячейка на рисунок (шаги бочки выброшены), средние страницы — 1–2 шестнадцатых добавлены или убраны,
    /// последняя — то же и 1–2 ноты сняты в шагах 13–16. Ноты в 1 шаг; корень аккорда — не меньше 85 % нот, иначе
    /// октава вверх или септима (ступень ниже корня): не больше 2 на страницу, на шагах 8–16, не первая после бочки.
    /// Velocity (единственный p-lock): офбиты 100 %, остальные 60–80 % (до 20 % — призрачные 40–55 %).
    static func technoBass(lens: [Int], degrees: [Int], scale: Int, root: Int, octave oct: Int,
                           kicks: [Set<Int>]?, using g: inout Rng) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        if playing.isEmpty || degrees.isEmpty { return out }
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let ci0: Int = pick(Array(0..<technoBassCells.count), technoBassWeights, using: &g)
        let cell: [Int] = technoBassCells[ci0]
        let count: Int = playing.count
        var pages: [[Int]] = []
        for (pi, p) in playing.enumerated() {
            let kick: Set<Int> = kickOf(kicks, p)
            let len: Int = lens[p]
            var steps: [Int] = cell.filter { $0 < len && !kick.contains($0) }
            if pi > 0 { steps = technoVary(steps, len: len, kick: kick, using: &g) }
            if pi == count - 1 && count > 1 {
                let tail: [Int] = steps.filter { $0 >= 12 }
                let cut: Int = Swift.min(tail.count, Int.random(in: 1...2, using: &g))
                for s in tail.shuffled(using: &g).prefix(cut) { steps.removeAll { $0 == s } }
            }
            if steps.isEmpty, let s = (0..<len).first(where: { !kick.contains($0) }) { steps = [s] }
            pages.append(steps)
        }
        let totalNotes: Int = pages.reduce(0) { $0 + $1.count }
        var budget: Int = totalNotes * 15 / 100
        for (pi, p) in playing.enumerated() {
            let steps: [Int] = pages[pi]
            let kick: Set<Int> = kickOf(kicks, p)
            let ci: Int = technoChord(page: pi, pages: count, chords: degrees.count)
            let k: Int = Chords.degreeIndex(degrees[ci], scale: scale)
            var afterKick: Set<Int> = []
            for kk in kick {
                if let s = steps.first(where: { $0 > kk }) { afterKick.insert(s) }
            }
            let offCount: Int = steps.filter { !isOffbeat($0) }.count
            var ghosts: Int = offCount / 5
            var others: Int = 0
            var evs: [SliceRhythm.Event] = []
            for s in steps {
                var deg: Int = k
                if s >= 7 && !afterKick.contains(s) && others < 2 && budget > 0
                    && Double.random(in: 0..<1, using: &g) < 0.2 {
                    deg = Bool.random(using: &g) ? k + n : k - 1
                    others += 1
                    budget -= 1
                }
                let note: Int = Swift.min(127, Swift.max(0, Scales.note(scale: scale, root: root, octave: oct, degree: deg)))
                var vel: Double = DrumRhythm.velFull
                if !isOffbeat(s) {
                    if ghosts > 0 && Double.random(in: 0..<1, using: &g) < 0.2 {
                        ghosts -= 1
                        vel = Double(Int.random(in: 51...69, using: &g))
                    } else {
                        vel = Double(Int.random(in: 77...101, using: &g))
                    }
                }
                evs.append(SliceRhythm.Event(step: s, note: note, len: 1, vel: vel))
            }
            out[p] = evs
        }
        return out
    }

    // MARK: — PAD

    /// Типы аккорда Techno (ступени от корня): m7, m9, квинта + септима (без терции); один на прогрессию — общий у
    /// PAD, KEYS, ARP (AppModel.lastRandomKind).
    static let technoKinds: [[Int]] = [[0, 2, 4, 6], [0, 2, 4, 6, 8], [0, 4, 6]]

    /// Наименьшая ступень не ниже from того же класса, что r + off.
    static func degreeAtLeast(_ from: Int, root r: Int, off: Int, n: Int) -> Int {
        var x: Int = from
        while Scales.wrap(x - r - off, n) != 0 { x += 1 }
        return x
    }

    /// Широкое расположение (ступени от корня клавиатуры): корень r, остальные звуки order — каждый не ближе октавы
    /// к предыдущему, пока не выше трёх октав над корнем (иначе — ближайший выше). top — верхний голос задан
    /// (средние — между корнем и им; не поместился — пропущен).
    static func spread(_ r: Int, _ order: [Int], n: Int, top: Int? = nil) -> [Int] {
        var out: [Int] = [r]
        var prev: Int = r
        let cap: Int = top ?? r + 3 * n
        for off in order {
            var x: Int = degreeAtLeast(prev + n, root: r, off: off, n: n)
            if x > cap || (top != nil && x >= cap) { x = degreeAtLeast(prev + 1, root: r, off: off, n: n) }
            if let t = top, x >= t { continue }
            out.append(x)
            prev = x
        }
        if let t = top { out.append(t) }
        return out
    }

    /// Ступень звука аккорда (корень r, ступени kind) ближе всего к t, выше корня.
    static func nearestTone(_ t: Int, root r: Int, kind: [Int], n: Int) -> Int {
        var best: Int = t
        var bestD: Int = Int.max
        for x in Swift.max(r + 1, t - n)...(t + n) {
            let c: Int = Scales.wrap(x - r, n)
            if !kind.contains(where: { Scales.wrap($0, n) == c }) { continue }
            let d: Int = Swift.abs(x - t)
            if d < bestD {
                bestD = d
                best = x
            }
        }
        return best
    }

    /// Прогрессии пэда Techno (ступени на страницы 1…4): своя у PAD, первая — тоника; гармония баса и лида — общая.
    static let padProgressions: [[Int]] = [[1, 7, 6, 7], [1, 6, 7, 1], [1, 7, 7, 6], [1, 6, 1, 7], [1, 7, 1, 6],
                                           [1, 6, 6, 7]]

    /// Прогрессия пэда на pages страниц: аккорд на страницу (первые pages ступеней одной из прогрессий).
    public static func padProgression(pages: Int, using g: inout Rng) -> [Int] {
        let p: [Int] = padProgressions.randomElement(using: &g) ?? padProgressions[0]
        var out: [Int] = []
        for i in 0..<Swift.max(1, pages) { out.append(p[i % p.count]) }
        return out
    }

    /// Пэд Techno на страницы lens: своя прогрессия (аккорд на страницу, padProgression; одна страница — тоника),
    /// тип аккорда kind (technoKinds; один на прогрессию), широкое расположение (одно на рисунок; у следующего аккорда
    /// верхний голос — не дальше 2 ступеней от прежнего). Удар — с началом аккорда, повтор каждые 32 шага, если
    /// аккорд держится дольше. Velocity: первый удар аккорда 75–85 %, повторные 60–75 %.
    static func technoPad(lens: [Int], kind kindIndex: Int, scale: Int, root: Int, octave oct: Int,
                          using g: inout Rng) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        guard let lastPage = playing.last else { return out }
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let kind: [Int] = technoKinds[Scales.wrap(kindIndex, technoKinds.count)]
        let order: [Int] = Array(kind.dropFirst()).shuffled(using: &g)
        let count: Int = playing.count
        let degrees: [Int] = padProgression(pages: count, using: &g)
        var voices: [[Int]] = []
        var prevTop: Int? = nil
        for d in degrees {
            let r: Int = Chords.degreeIndex(d, scale: scale)
            var v: [Int] = spread(r, order, n: n)
            if let t = prevTop, let top = v.last, Swift.abs(top - t) > 2 {
                let want: Int = nearestTone(t, root: r, kind: kind, n: n)
                let rest: [Int] = order.filter { Scales.wrap(r + $0 - want, n) != 0 }
                v = spread(r, rest, n: n, top: want)
            }
            voices.append(v)
            prevTop = v.last
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

extension Track {
    /// Случайный пэд Techno на страницы range (своя прогрессия, тип аккорда kind; MelodyRhythm.technoPad): прежние
    /// шаги этих страниц стираются.
    public mutating func writeTechnoPad(pages range: ClosedRange<Int>, kind: Int, scale: Int, root: Int,
                                        octave: Int, using g: inout Rng) {
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[SliceRhythm.Event]] = MelodyRhythm.technoPad(lens: lens, kind: kind, scale: scale,
                                                                    root: root, octave: octave, using: &g)
        writeSlices(pattern, pages: range)
    }
}

extension Project {
    /// Шаги бочки страниц range (для баса и лида Techno): первая дорожка KICK (движок или сэмпл по имени) с тригами
    /// в открытом клипе; странице range соответствует её страница, играющая одновременно (по кругу длины клипа
    /// бочки). Страница бочки без тригов или бочки нет — 1, 5, 9, 13.
    public func kickGrid(pages range: ClosedRange<Int>) -> [Set<Int>] {
        let fs: [String: String] = files
        let kt: Track? = tracks.first { t in
            t.drumRoleBy(name: fs[t.sample]) == .kick && t.pages.contains { pg in pg.contains { $0.on } }
        }
        let per: Int = Params.stepsPerPage
        var out: [Set<Int>] = []
        for i in 0..<range.count {
            guard let t = kt else {
                out.append(MelodyRhythm.defaultKick)
                continue
            }
            let kp: Int = Swift.max(1, Swift.min(t.pages.count, (t.length + per - 1) / per))
            let page: Int = (range.lowerBound + i) % kp
            var steps: Set<Int> = []
            for (s, st) in t.pages[page].enumerated() where st.on && page * per + s < t.length { steps.insert(s) }
            out.append(steps.isEmpty ? MelodyRhythm.defaultKick : steps)
        }
        return out
    }
}
