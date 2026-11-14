import Foundation

// Случайные KEYS и ARP в стиле Techno — hypnotic (docs/ai/sequencer.md, «Случайная партия», «Случайное арпеджио»):
// гармония Techno (TechnoParts: 1 или 1 → 7/6, тип аккорда один на прогрессию), KEYS — короткие стабы без корня по
// одной ячейке мимо бочки, ARP — непрерывный цикл из N нот (полиметрия поверх такта). Из p-lock — только Velocity.

extension MelodyRhythm {
    /// Ячейки стабов KEYS (шаги 0…15; S1…S7) и их веса.
    static let technoKeysCells: [[Int]] = [[2, 10], [3, 10], [2, 6, 10, 14], [2, 5, 10, 13], [3, 6, 11, 14],
                                           [2, 6, 11], [6, 14]]
    static let technoKeysWeights: [Double] = [20, 15, 15, 15, 15, 10, 10]

    /// Голоса KEYS без корня (ступени от корня) по типу аккорда: m7 — 3, 5, 7; m9 — 5, 7, 9; квинта + септима — 5, 7, 8.
    static let technoKeysVoices: [[Int]] = [[2, 4, 6], [4, 6, 8], [4, 6, 7]]

    /// Тесное расположение голосов offs аккорда на ступени r в октаве клавиатуры (ступени от корня клавиатуры);
    /// prevTop — верхний голос прежнего аккорда: обращение и октава — так, чтобы верх сдвинулся меньше всего.
    static func closeVoicing(_ r: Int, _ offs: [Int], n: Int, prevTop: Int?) -> [Int] {
        let folded: [Int] = offs.map { Scales.wrap(r + $0, n) }.sorted()
        guard let t = prevTop else { return folded }
        var best: [Int] = folded
        var bestD: Int = Int.max
        for shift in [0, -1, 1] {
            for inv in 0..<folded.count {
                var v: [Int] = []
                for (i, x) in folded.enumerated() { v.append(x + (i < inv ? n : 0) + shift * n) }
                let d: Int = Swift.abs((v.max() ?? 0) - t)
                if d < bestD {
                    bestD = d
                    best = v.sorted()
                }
            }
        }
        return best
    }

    /// Нота ступени d от корня клавиатуры; выше 127 — на октаву ниже.
    static func technoNote(_ d: Int, scale: Int, root: Int, octave oct: Int) -> Int {
        var note: Int = Scales.note(scale: scale, root: root, octave: oct, degree: d)
        while note > 127 { note -= 12 }
        return Swift.max(0, note)
    }

    /// KEYS Techno на страницы lens по прогрессии degrees (аккорды — целыми страницами), тип kind (technoKinds),
    /// бочка kicks (nil — 1, 5, 9, 13). Стабы в 1 шаг, аккорд из трёх голосов без корня в тесном расположении
    /// (одно на рисунок; у второго аккорда верх — не дальше 2 ступеней). Одна ячейка S1…S7 на рисунок, шаги бочки
    /// выброшены; средние страницы — один стаб (не первый) сдвинут на ±1 шаг или убран; последняя — стаб в шагах
    /// 13–16 убран. Velocity: первый стаб страницы 100 %, остальные 70–85 %.
    static func technoKeys(lens: [Int], degrees: [Int], kind: Int, scale: Int, root: Int, octave oct: Int,
                           kicks: [Set<Int>]?, using g: inout Rng) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        if playing.isEmpty || degrees.isEmpty { return out }
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let offs: [Int] = technoKeysVoices[Scales.wrap(kind, technoKeysVoices.count)]
        var voices: [[Int]] = []
        var prevTop: Int? = nil
        for d in degrees {
            let v: [Int] = closeVoicing(Chords.degreeIndex(d, scale: scale), offs, n: n, prevTop: prevTop)
            voices.append(v)
            prevTop = v.last
        }
        let k: Int = pick(Array(0..<technoKeysCells.count), technoKeysWeights, using: &g)
        let cell: [Int] = technoKeysCells[k]
        let count: Int = playing.count
        for (pi, p) in playing.enumerated() {
            let len: Int = lens[p]
            let kick: Set<Int> = kickOf(kicks, p)
            var steps: [Int] = cell.filter { $0 < len && !kick.contains($0) }
            if pi > 0 && pi < count - 1 && steps.count > 1 {
                let j: Int = Int.random(in: 1..<steps.count, using: &g)
                let to: Int = steps[j] + (Bool.random(using: &g) ? 1 : -1)
                let ok: Bool = to >= 0 && to < len && !kick.contains(to) && !steps.contains(to)
                if ok && Bool.random(using: &g) { steps[j] = to } else { steps.remove(at: j) }
                steps.sort()
            }
            if pi == count - 1 && count > 1, let s = steps.filter({ $0 >= 12 }).randomElement(using: &g) {
                steps.removeAll { $0 == s }
            }
            let ci: Int = technoChord(page: pi, pages: count, chords: degrees.count)
            for (i, s) in steps.enumerated() {
                let vel: Double = i == 0 ? DrumRhythm.velFull : Double(Int.random(in: 89...108, using: &g))
                for d in voices[ci] {
                    let note: Int = technoNote(d, scale: scale, root: root, octave: oct)
                    out[p].append(SliceRhythm.Event(step: s, note: note, len: 1, vel: vel))
                }
            }
        }
        return out
    }
}

extension Arp {
    /// Арпеджио Techno на страницы lens по прогрессии degrees (аккорды — целыми страницами), тип kind (m9 — с d+8):
    /// звуки d, d+4, d+6 (m9 — ещё d+8), с OCTAVES 2–3 ряд выше; ряд по направлению dir (Random — N звуков наугад,
    /// один набор на рисунок). Цикл из N нот (3, 5, 6 или 7; ряд короче — по кругу) идёт по шагам сетки RATE подряд
    /// через все страницы, при смене аккорда продолжается нотами нового. Ноты не на шагах бочки kicks, длина — по
    /// GATE (не дальше следующей ноты). Velocity: шаги 3, 7, 11, 15 — 100 %, остальные 55–75 %; последняя страница —
    /// в шагах 13–16 снята каждая вторая нота. Возвращает ноты по шагам от начала range (как randomSteps).
    public static func technoSteps(lens: [Int], degrees: [Int], kind: Int, scale: Int, root: Int, octave oct: Int,
                                   dir: Int, octaves: Int, rate: Int, gate: Double, kicks: [Set<Int>]?,
                                   using g: inout Rng) -> [ArpStepNote] {
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        if playing.isEmpty || degrees.isEmpty { return [] }
        let per: Int = Params.stepsPerPage
        let offs: [Int] = kind == 1 ? [0, 4, 6, 8] : [0, 4, 6]
        let oc: Int = clampOctaves(octaves)
        // Ряды звуков аккордов: по высоте (Order — как в аккорде), октавы выше, направление.
        var rows: [[Int]] = []
        for d in degrees {
            let r: Int = Chords.degreeIndex(d, scale: scale)
            var tones: [Int] = offs.map { MelodyRhythm.technoNote(r + $0, scale: scale, root: root, octave: oct) }
            if dir != order { tones.sort() }
            var row: [Int] = []
            for o in 0..<oc {
                for t in tones {
                    var m: Int = t + 12 * o
                    while m > 127 { m -= 12 }
                    row.append(m)
                }
            }
            switch clampDir(dir) {
            case down: row.reverse()
            case upDown: if row.count > 2 { row += row.dropFirst().dropLast().reversed() }
            case downUp:
                row.reverse()
                if row.count > 2 { row += row.dropFirst().dropLast().reversed() }
            default: break
            }
            rows.append(row)
        }
        let cycle: Int = [3, 5, 6, 7].randomElement(using: &g) ?? 5
        let width: Int = rows[0].count
        var fig: [Int] = []
        for j in 0..<cycle {
            fig.append(clampDir(dir) == random ? Int.random(in: 0..<Swift.max(1, width), using: &g) : j % Swift.max(1, width))
        }
        let every: Int = gridSteps[clampRate(rate)]
        let baseLen: Int = Swift.max(1, Int((clampGate(gate) * Double(every)).rounded()))
        let count: Int = playing.count
        let total: Int = (count - 1) * per + lens[playing[count - 1]]
        var hits: [(step: Int, note: Int, vel: Double)] = []
        var slot: Int = 0
        var fillNo: Int = 0
        var s: Int = 0
        while s < total {
            let pi: Int = s / per
            let st: Int = s % per
            let pos: Int = slot % cycle
            slot += 1
            let page: Int = playing[pi]
            if st < lens[page] && !MelodyRhythm.kickOf(kicks, page).contains(st) {
                var skip: Bool = false
                if pi == count - 1 && count > 1 && st >= 12 {
                    skip = fillNo % 2 == 1
                    fillNo += 1
                }
                if !skip {
                    let ci: Int = MelodyRhythm.technoChord(page: pi, pages: count, chords: degrees.count)
                    let row: [Int] = rows[ci]
                    let note: Int = row[fig[pos] % Swift.max(1, row.count)]
                    let vel: Double = st % 4 == 2 ? DrumRhythm.velFull : Double(Int.random(in: 70...95, using: &g))
                    hits.append((page * per + st, note, vel))
                }
            }
            s += every
        }
        var out: [ArpStepNote] = []
        for (j, h) in hits.enumerated() {
            let next: Int = j + 1 < hits.count ? hits[j + 1].step : playing[count - 1] * per + lens[playing[count - 1]]
            let len: Int = Swift.max(1, Swift.min(baseLen, next - h.step))
            out.append(ArpStepNote(step: h.step, note: h.note, len: len, vel: h.vel))
        }
        return out
    }
}

extension Track {
    /// Случайные KEYS Techno на страницы range (MelodyRhythm.technoKeys): прежние шаги этих страниц стираются.
    public mutating func writeTechnoKeys(pages range: ClosedRange<Int>, degrees: [Int], kind: Int, scale: Int,
                                         root: Int, octave: Int, kicks: [Set<Int>]?, using g: inout Rng) {
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[SliceRhythm.Event]] = MelodyRhythm.technoKeys(lens: lens, degrees: degrees, kind: kind,
                                                                     scale: scale, root: root, octave: octave,
                                                                     kicks: kicks, using: &g)
        writeSlices(pattern, pages: range)
    }

    /// Случайное арпеджио Techno на страницы range (Arp.technoSteps) по настройкам ARP дорожки (не меняются).
    public mutating func writeTechnoArp(pages range: ClosedRange<Int>, degrees: [Int], kind: Int, scale: Int,
                                        root: Int, octave: Int, kicks: [Set<Int>]?, using g: inout Rng) {
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let a: TrackArp = arp
        let notes: [ArpStepNote] = Arp.technoSteps(lens: lens, degrees: degrees, kind: kind, scale: scale, root: root,
                                                   octave: octave, dir: a.dir, octaves: a.octaves, rate: a.rate,
                                                   gate: a.gate, kicks: kicks, using: &g)
        writeArpSteps(notes, pages: range)
    }
}
