import Foundation

// Случайные BASS, LEAD, KEYS и ARP в стиле Techno — hypnotic (docs/ai/sequencer.md, «Случайная партия Techno»):
// один генератор technoRun. Удары — по ячейке ритма (шаги сетки), которая повторяется подряд через все страницы,
// мимо бочки; высоты — фигура из звуков ряда аккорда страницы, она сдвигается только на ударе (фигура и ритм другой
// длины расходятся — полиметрия). Средние страницы — один удар снят или одна пауза заполнена (офбиты не трогаются),
// последняя — в шагах 13–16 снят каждый второй удар. Velocity (единственный p-lock): офбиты 3, 7, 11, 15 — 100 %,
// первая нота фигуры (если в фигуре больше одной ноты) 80–90 %, остальные 55–75 %. PAD — TechnoParts.swift.

/// Удар партии Techno: шаг от начала страниц (по 16 на страницу), ноты (у KEYS — аккорд), velocity.
struct TechnoHit {
    var step: Int
    var notes: [Int]
    var vel: Double
}

extension MelodyRhythm {
    /// Евклидов ритм k ударов на n шагах со сдвигом rot (DrumRhythm.euclid) — ячейкой: true — удар.
    static func euclidCell(_ k: Int, _ n: Int, rot: Int) -> [Bool] {
        var out: [Bool] = Array(repeating: false, count: Swift.max(1, n))
        for s in DrumRhythm.euclid(k, n, rot: rot) { out[s] = true }
        return out
    }

    /// Ступени лида от корня аккорда: 0 — корень, n — октава, 4 — квинта, 6 — септима, 1 — секунда.
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

    /// Ячейка ритма (perBar шагов сетки в такте). dense (ARP): подряд (20 %), евклид на такт E(k, perBar) с k ≈ 9…13
    /// из 16 (40 %) или ячейка 3, 5, 6, 7 шагов с евклидовым ритмом внутри (40 %); иначе (LEAD) — евклид с k ≈ 5…9
    /// из 16 (40 %) или ячейка (60 %). Мимо бочки 1, 5, 9, 13 в каждом из 4 тактов — не меньше половины (LEAD —
    /// четверти) свободных шагов, иначе заново (до 8 раз; потом — подряд).
    static func technoMask(perBar: Int, dense: Bool, using g: inout Rng) -> [Bool] {
        let all: [Bool] = Array(repeating: true, count: Swift.max(1, perBar))
        let r: Double = Double.random(in: 0..<1, using: &g)
        if perBar < 4 || (dense && r < 0.2) { return all }
        let per: Int = Params.stepsPerPage
        let every: Int = Swift.max(1, per / perBar)
        let free: [Int] = (0..<perBar).filter { !defaultKick.contains(($0 * every) % per) }
        let need: Int = Swift.max(1, dense ? free.count / 2 : free.count / 4)
        let bar: Bool = dense ? r < 0.6 : r < 0.4
        for _ in 0..<8 {
            var cell: [Bool] = []
            if bar {
                let lo: Int = Swift.max(2, perBar * (dense ? 9 : 5) / 16)
                let hi: Int = Swift.max(lo, perBar * (dense ? 13 : 9) / 16)
                cell = euclidCell(Int.random(in: lo...hi, using: &g), perBar, rot: Int.random(in: 0..<perBar, using: &g))
            } else {
                let n: Int = [3, 5, 6, 7].filter { $0 < perBar }.randomElement(using: &g) ?? 3
                let k: Int = Int.random(in: Swift.max(2, (n + 1) / 2)...(n - 1), using: &g)
                cell = euclidCell(k, n, rot: Int.random(in: 0..<n, using: &g))
            }
            var ok: Bool = true
            for b in 0..<4 where free.filter({ cell[(b * perBar + $0) % cell.count] }).count < need { ok = false }
            if ok { return cell }
        }
        return all
    }

    /// Фигура из cycle нот (номера в ряду ширины width): random — наугад; иначе ряд подряд (50 %), педаль на первом
    /// звуке (0, 1, 0, 2…; 25 %) или через звук (0, 2, 1, 3…; 25 %).
    static func technoFigure(cycle: Int, width: Int, random: Bool, using g: inout Rng) -> [Int] {
        let w: Int = Swift.max(1, width)
        let r: Double = Double.random(in: 0..<1, using: &g)
        var fig: [Int] = []
        for j in 0..<cycle {
            if random {
                fig.append(Int.random(in: 0..<w, using: &g))
            } else if r < 0.5 || w < 3 {
                fig.append(j % w)
            } else if r < 0.75 {
                fig.append(j % 2 == 0 ? 0 : 1 + (j / 2) % (w - 1))
            } else {
                fig.append((j / 2 + (j % 2 == 1 ? 2 : 0)) % w)
            }
        }
        return fig
    }

    /// Общий генератор Techno на страницы lens: ячейка ритма cell по шагам сетки every подряд через страницы; rows —
    /// ряд звуков (или аккордов) на каждый аккорд прогрессии (аккорды — целыми страницами, technoChord); fig —
    /// номера в ряду, сдвиг — на ударе; rootFirst — первый удар страницы — первый звук ряда (корень у BASS). Удары
    /// не на шагах бочки kicks (nil — 1, 5, 9, 13).
    static func technoRun(lens: [Int], rows: [[[Int]]], fig: [Int], cell: [Bool], every: Int, kicks: [Set<Int>]?,
                          rootFirst: Bool = false, using g: inout Rng) -> [TechnoHit] {
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        if playing.isEmpty || rows.isEmpty || fig.isEmpty || cell.isEmpty { return [] }
        let per: Int = Params.stepsPerPage
        let ev: Int = Swift.max(1, every)
        let count: Int = playing.count
        let total: Int = (count - 1) * per + lens[playing[count - 1]]
        let slots: Int = (total + ev - 1) / ev
        let perBar: Int = Swift.max(1, per / ev)
        var mask: [Bool] = (0..<slots).map { cell[$0 % cell.count] }
        if count > 2 {
            for pi in 1..<(count - 1) {
                let a: Int = pi * perBar
                let b: Int = Swift.min(slots, a + perBar)
                if b - a < 2 { continue }
                let kick: Set<Int> = kickOf(kicks, playing[pi])
                let want: Bool = Bool.random(using: &g)
                let cand: [Int] = ((a + 1)..<b).filter { s in
                    let st: Int = (s * ev) % per
                    return mask[s] == want && !kick.contains(st) && !isOffbeat(st)
                }
                if let j = cand.randomElement(using: &g) { mask[j].toggle() }
            }
        }
        var out: [TechnoHit] = []
        var hitNo: Int = 0
        var fillNo: Int = 0
        var lastPage: Int = -1
        for slot in 0..<slots where mask[slot] {
            let s: Int = slot * ev
            let pi: Int = s / per
            let st: Int = s % per
            let page: Int = playing[pi]
            if st >= lens[page] || kickOf(kicks, page).contains(st) { continue }
            if pi == count - 1 && count > 1 && st >= 12 {
                fillNo += 1
                if fillNo % 2 == 0 { continue }
            }
            let pos: Int = hitNo % fig.count
            hitNo += 1
            let row: [[Int]] = rows[technoChord(page: pi, pages: count, chords: rows.count)]
            if row.isEmpty { continue }
            var vel: Double = Double(Int.random(in: 70...95, using: &g))
            if pos == 0 && fig.count > 1 { vel = Double(Int.random(in: 100...114, using: &g)) }
            if isOffbeat(st) { vel = DrumRhythm.velFull }
            let first: Bool = rootFirst && pi != lastPage
            lastPage = pi
            out.append(TechnoHit(step: page * per + st, notes: row[first ? 0 : fig[pos] % row.count], vel: vel))
        }
        return out
    }

    /// Удары по страницам lens: ноты в 1 шаг.
    static func technoPages(_ hits: [TechnoHit], lens: [Int]) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let per: Int = Params.stepsPerPage
        for h in hits where h.step / per < out.count {
            for m in h.notes { out[h.step / per].append(SliceRhythm.Event(step: h.step % per, note: m, len: 1, vel: h.vel)) }
        }
        return out
    }

    /// BASS: одна ячейка A…H (вес) по шестнадцатым; ряд — корень, октава вверх, ступень ниже корня; фигура из 8 нот —
    /// корень, в половине рисунков одна нота (не первая) — октава или ступень ниже; первая нота страницы — корень.
    static func technoBass(lens: [Int], degrees: [Int], scale: Int, root: Int, octave oct: Int,
                           kicks: [Set<Int>]?, using g: inout Rng) -> [[SliceRhythm.Event]] {
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let ci: Int = pick(Array(0..<technoBassCells.count), technoBassWeights, using: &g)
        var cell: [Bool] = Array(repeating: false, count: Params.stepsPerPage)
        for s in technoBassCells[ci] { cell[s] = true }
        let rows: [[[Int]]] = degrees.map { d in
            let k: Int = Chords.degreeIndex(d, scale: scale)
            return [k, k + n, k - 1].map { [technoNote(Swift.max(0, $0), scale: scale, root: root, octave: oct)] }
        }
        var fig: [Int] = Array(repeating: 0, count: 8)
        if Bool.random(using: &g) { fig[Int.random(in: 1..<8, using: &g)] = Int.random(in: 1...2, using: &g) }
        let hits: [TechnoHit] = technoRun(lens: lens, rows: rows, fig: fig, cell: cell, every: 1, kicks: kicks,
                                          rootFirst: true, using: &g)
        return technoPages(hits, lens: lens)
    }

    /// LEAD: ячейка technoMask (реже, чем у ARP); 2–3 высоты от корня аккорда (hypnoticPitches; выше полутора
    /// октав — октавой ниже); фигура из 3–7 нот, корень — чаще (55 %), не вся на корне.
    static func hypnoticLead(lens: [Int], degrees: [Int], scale: Int, root: Int, octave oct: Int,
                             kicks: [Set<Int>]? = nil, using g: inout Rng) -> [[SliceRhythm.Event]] {
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let hi: Int = n + n / 2
        let pitches: [Int] = hypnoticPitches(count: Int.random(in: 2...3, using: &g), n: n, using: &g)
        let rows: [[[Int]]] = degrees.map { d in
            let k: Int = Chords.degreeIndex(d, scale: scale)
            return pitches.map { off in
                var x: Int = k + off
                while x > hi { x -= n }
                return [technoNote(Swift.max(0, x), scale: scale, root: root, octave: oct)]
            }
        }
        let cycle: Int = Int.random(in: 3...7, using: &g)
        var fig: [Int] = (0..<cycle).map { _ in
            Double.random(in: 0..<1, using: &g) < 0.55 ? 0 : Int.random(in: 1..<pitches.count, using: &g)
        }
        if !fig.contains(where: { $0 != 0 }) { fig[Int.random(in: 1..<cycle, using: &g)] = 1 }
        let cell: [Bool] = technoMask(perBar: Params.stepsPerPage, dense: false, using: &g)
        let hits: [TechnoHit] = technoRun(lens: lens, rows: rows, fig: fig, cell: cell, every: 1, kicks: kicks, using: &g)
        return technoPages(hits, lens: lens)
    }

    /// KEYS: одна ячейка стабов S1…S7 (вес); аккорд из трёх голосов без корня (technoKeysVoices по типу kind) в
    /// тесном расположении (одно на рисунок; у второго аккорда верх — не дальше 2 ступеней).
    static func technoKeys(lens: [Int], degrees: [Int], kind: Int, scale: Int, root: Int, octave oct: Int,
                           kicks: [Set<Int>]?, using g: inout Rng) -> [[SliceRhythm.Event]] {
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let offs: [Int] = technoKeysVoices[Scales.wrap(kind, technoKeysVoices.count)]
        var rows: [[[Int]]] = []
        var prevTop: Int? = nil
        for d in degrees {
            let v: [Int] = closeVoicing(Chords.degreeIndex(d, scale: scale), offs, n: n, prevTop: prevTop)
            rows.append([v.map { technoNote($0, scale: scale, root: root, octave: oct) }])
            prevTop = v.last
        }
        let k: Int = pick(Array(0..<technoKeysCells.count), technoKeysWeights, using: &g)
        var cell: [Bool] = Array(repeating: false, count: Params.stepsPerPage)
        for s in technoKeysCells[k] { cell[s] = true }
        let hits: [TechnoHit] = technoRun(lens: lens, rows: rows, fig: [0], cell: cell, every: 1, kicks: kicks, using: &g)
        return technoPages(hits, lens: lens)
    }
}

extension Arp {
    /// ARP Techno: звуки аккорда d, d+4, d+6 (m9 — ещё d+8), ряд по DIRECTION и OCTAVES (Arp.sequence); фигура
    /// из 3–7 нот (technoFigure), ячейка technoMask по сетке RATE; длина — по GATE, не дальше следующей ноты.
    /// Возвращает ноты по шагам от начала range.
    public static func technoSteps(lens: [Int], degrees: [Int], kind: Int, scale: Int, root: Int, octave oct: Int,
                                   dir: Int, octaves: Int, rate: Int, gate: Double, kicks: [Set<Int>]?,
                                   using g: inout Rng) -> [ArpStepNote] {
        let offs: [Int] = kind == 1 ? [0, 4, 6, 8] : [0, 4, 6]
        let rows: [[[Int]]] = degrees.map { d in
            let r: Int = Chords.degreeIndex(d, scale: scale)
            let tones: [Int] = offs.map { MelodyRhythm.technoNote(r + $0, scale: scale, root: root, octave: oct) }
            return sequence(tones, dir: clampDir(dir), octaves: octaves).map { [$0] }
        }
        let width: Int = rows.first?.count ?? 1
        let fig: [Int] = MelodyRhythm.technoFigure(cycle: Int.random(in: 3...7, using: &g), width: width,
                                                   random: clampDir(dir) == random, using: &g)
        let every: Int = gridSteps[clampRate(rate)]
        let cell: [Bool] = MelodyRhythm.technoMask(perBar: Params.stepsPerPage / every, dense: true, using: &g)
        let hits: [TechnoHit] = MelodyRhythm.technoRun(lens: lens, rows: rows, fig: fig, cell: cell, every: every,
                                                       kicks: kicks, using: &g)
        let baseLen: Int = Swift.max(1, Int((clampGate(gate) * Double(every)).rounded()))
        let end: Int = (lens.lastIndex { $0 > 0 } ?? 0) * Params.stepsPerPage + (lens.last { $0 > 0 } ?? 0)
        var out: [ArpStepNote] = []
        for (j, h) in hits.enumerated() {
            let next: Int = j + 1 < hits.count ? hits[j + 1].step : end
            let len: Int = Swift.max(1, Swift.min(baseLen, next - h.step))
            for m in h.notes { out.append(ArpStepNote(step: h.step, note: m, len: len, vel: h.vel)) }
        }
        return out
    }
}
