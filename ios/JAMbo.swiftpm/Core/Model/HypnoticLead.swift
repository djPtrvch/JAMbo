import Foundation

// Случайный LEAD в стиле Techno — «гипнотик» (docs/ai/sequencer.md, «Случайная партия»): вместо мелодии с фразами —
// короткая ячейка, которая повторяется без изменений. Приёмы техно-секвенций: полиметрия (ячейка 3, 5, 6 или 7 шагов
// поверх такта 16 — каждый круг начинается с другой доли), евклидовы ритмы (Toussaint: E(k, n) — k ударов как можно
// ровнее по n шагам) и «полиметрия высот» (2–3 ноты по кругу поверх ритма другой длины). Высоты — 1–3 ноты от корня
// аккорда: корень чаще всего, октава, квинта, септима, секунда. Ноты короткие, акцент — в начале ячейки.

extension MelodyRhythm {
    /// Евклидов ритм E(k, n), сдвинутый на rot шагов: true — удар.
    static func euclid(_ k: Int, _ n: Int, rot: Int) -> [Bool] {
        var out: [Bool] = Array(repeating: false, count: Swift.max(1, n))
        if n <= 0 { return out }
        for i in 0..<n {
            let j: Int = Scales.wrap(i - rot, n)
            out[i] = (j * k) % n < k
        }
        return out
    }

    /// Ступени гипнотической партии от корня аккорда: 0 — корень, n — октава, 4 — квинта, 6 — септима, 1 — секунда.
    static func hypnoticPitches(count m: Int, n: Int, using g: inout Rng) -> [Int] {
        let pool: [Int] = [n, 4, 6, 1]
        let weights: [Double] = [0.4, 0.3, 0.15, 0.15]
        var out: [Int] = [0]
        var tries: Int = 0
        while out.count < m && tries < 20 {
            let d: Int = pick(pool, weights, using: &g)
            if !out.contains(d) { out.append(d) }
            tries += 1
        }
        return out
    }

    /// Гипнотическая партия на страницы lens по прогрессии degrees. Два вида (наугад): ячейка-полиметрия длиной
    /// 3, 5, 6 или 7 шагов (евклидов ритм внутри, высоты на ударах ячейки) — повторяется подряд через все страницы, не
    /// с начала такта; или евклидов ритм на 16 шагов (5, 7, 9 ударов) с кругом из 2–3 высот другой длины. Высоты — от
    /// корня аккорда страницы (аккорды — целыми страницами, TechnoParts). Ноты не на шагах бочки kicks (nil — 1, 5,
    /// 9, 13), 1 шаг (25 % — 2). p-lock: Velocity — первый удар ячейки (или круга высот) 100 %, остальные 60–85 %;
    /// Chance — у ~30 % нот 80–95 %; Pan — удары ячейки попеременно влево и вправо на 15–35 % (рисунок один на
    /// ячейку); Ratchet 2 — 15 % на проход ячейки, одна нота. Последняя страница (если их больше одной) — сбивка:
    /// в последних 4 шагах часть нот снята.
    static func hypnoticLead(lens: [Int], degrees: [Int], scale: Int, root: Int, octave oct: Int,
                             kicks: [Set<Int>]? = nil, using g: inout Rng) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        if playing.isEmpty || degrees.isEmpty { return out }
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let hi: Int = n + n / 2
        let per: Int = Params.stepsPerPage
        let total: Int = playing.count * per
        let poly: Bool = Double.random(in: 0..<1, using: &g) < 0.6
        let cellLen: Int = poly ? ([3, 5, 6, 7].randomElement(using: &g) ?? 5) : per
        // Ударов в ячейке: 3 шага — 2, 5 — 2…4, 6 — 3…5, 7 — 3…6; на 16 шагов — 5, 7 или 9 (не кратно кругу высот).
        let hits: Int = poly ? Int.random(in: Swift.max(2, cellLen / 2)...(cellLen - 1), using: &g)
                             : ([5, 7, 9].randomElement(using: &g) ?? 7)
        let rhythm: [Bool] = euclid(hits, cellLen, rot: Int.random(in: 0..<cellLen, using: &g))
        let pitches: [Int] = hypnoticPitches(count: Int.random(in: 2...3, using: &g), n: n, using: &g)
        // Высоты на ударах ячейки (полиметрия) или круг высот (евклид на 16): корень — чаще.
        var cellPitch: [Int] = []
        for _ in 0..<cellLen {
            let rootP: Bool = Double.random(in: 0..<1, using: &g) < 0.55
            cellPitch.append(rootP ? 0 : (pitches.dropFirst().randomElement(using: &g) ?? 0))
        }
        // Ячейка не на одной ноте: один удар (не первый) — другая высота.
        let cellHits: [Int] = (0..<cellLen).filter { rhythm[$0] }
        if poly && cellHits.count > 1 && !cellHits.contains(where: { cellPitch[$0] != 0 }) {
            let j: Int = cellHits[Int.random(in: 1..<cellHits.count, using: &g)]
            cellPitch[j] = pitches.count > 1 ? pitches[1] : 0
        }
        // Pan ударов ячейки: попеременно влево и вправо на 15–35 % (−64…63).
        var cellPan: [Double] = Array(repeating: 0, count: cellLen)
        var side: Double = Bool.random(using: &g) ? 1 : -1
        for j in cellHits {
            cellPan[j] = side * Double(Int.random(in: 10...22, using: &g))
            side = -side
        }
        let fillFrom: Int = total - 4
        let firstHit: Int = rhythm.firstIndex(of: true) ?? 0
        var abs: [Int] = []
        var deg: [Int] = []
        var acc: [Bool] = []
        var pans: [Double] = []
        var rats: [Bool] = []
        var hitNo: Int = 0
        var pass: Int = -1
        var ratchetPos: Int = -1
        for s in 0..<total {
            let pos: Int = s % cellLen
            if s / cellLen != pass {
                pass = s / cellLen
                let on: Bool = Double.random(in: 0..<1, using: &g) < 0.15
                ratchetPos = on ? (cellHits.randomElement(using: &g) ?? -1) : -1
            }
            if !rhythm[pos] { continue }
            let pi: Int = s / per
            if kickOf(kicks, playing[pi]).contains(s % per) { continue }
            if playing.count > 1 && s >= fillFrom && Bool.random(using: &g) { continue }
            let ci: Int = technoChord(page: pi, pages: playing.count, chords: degrees.count)
            let k: Int = Chords.degreeIndex(degrees[ci], scale: scale)
            let off: Int = poly ? cellPitch[pos] : pitches[hitNo % pitches.count]
            var d: Int = k + off
            while d > hi { d -= n }
            abs.append(s)
            deg.append(Swift.max(0, d))
            acc.append(poly ? pos == firstHit : hitNo % pitches.count == 0)
            pans.append(cellPan[pos])
            rats.append(pos == ratchetPos)
            hitNo += 1
        }
        for i in abs.indices {
            let pi: Int = abs[i] / per
            let st: Int = abs[i] % per
            let p: Int = playing[Swift.min(playing.count - 1, pi)]
            if st >= lens[p] { continue }
            let next: Int = i + 1 < abs.count ? abs[i + 1] : total
            let gap: Int = Swift.max(1, Swift.min(next - abs[i], lens[p] - st))
            let gate: Int = Double.random(in: 0..<1, using: &g) < 0.25 ? 2 : 1
            let note: Int = Swift.min(127, Swift.max(0, Scales.note(scale: scale, root: root, octave: oct, degree: deg[i])))
            let v: Double = acc[i] ? DrumRhythm.velFull : Double(Int.random(in: 77...107, using: &g))
            let ch: Double? = Double.random(in: 0..<1, using: &g) < 0.3 ? Double(Int.random(in: 80...95, using: &g)) : nil
            out[p].append(SliceRhythm.Event(step: st, note: note, len: Swift.min(gap, gate), vel: v, chance: ch,
                                            ratchet: rats[i] ? 1 : nil, pan: pans[i]))
        }
        return out
    }
}
