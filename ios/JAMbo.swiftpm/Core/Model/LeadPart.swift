import Foundation

// Случайный LEAD (SHIFT + CHORD на дорожке-мелодии; docs/ai/sequencer.md, «Случайная партия»): мотив по ритму стиля,
// шаги по гамме (сильные доли — звуки аккорда), фразы A A′ A B (вопрос — ответ), конец — на корне.

extension MelodyRhythm {
    /// Ритм мелодии по стилю (DrumRhythm.Groove): вероятность ноты на шаге такта.
    static let leadRhythms: [[Double]] = [
        [1, 0, 0.4, 0.5, 0, 0.3, 0.6, 0, 0.5, 0, 0.4, 0.6, 0, 0.3, 0.2, 0],     // house
        [1, 0, 0, 0.6, 0, 0, 0.6, 0, 0.3, 0, 0, 0.6, 0, 0, 0.5, 0],             // techno
        [1, 0, 0.5, 0, 0.4, 0, 0.6, 0.3, 0, 0.5, 0, 0.4, 0.6, 0, 0.3, 0],       // breaks
        [1, 0, 0, 0, 0.5, 0, 0.3, 0, 0.6, 0, 0, 0.4, 0, 0, 0.5, 0],             // dnb
        [1, 0, 0.5, 0.3, 0, 0.5, 0.4, 0, 0.6, 0.3, 0.5, 0, 0.4, 0, 0.3, 0.3],   // trap
        [1, 0, 0, 0.5, 0, 0.4, 0, 0.5, 0.3, 0, 0.6, 0, 0, 0.4, 0, 0],           // rnb
        [1, 0, 0.6, 0, 0.7, 0, 0.6, 0.3, 1, 0, 0.6, 0, 0.5, 0, 0.4, 0],         // pop
        [1, 0, 0, 0, 0, 0, 0.3, 0, 0.5, 0, 0, 0, 0, 0, 0.2, 0],                 // ambient
    ]

    /// Доля нот мелодии, которые тянутся до следующей, по стилю.
    static let leadLegatos: [Double] = [0.3, 0.2, 0.3, 0.5, 0.4, 0.5, 0.4, 0.9]

    /// Шаги ритма отрезка длиной u (не меньше 3 нот, если отрезок позволяет; первый шаг — всегда).
    static func leadSteps<G: RandomNumberGenerator>(_ pr: [Double], len u: Int, using g: inout G) -> [Int] {
        var out: [Int] = [0]
        for s in 1..<Swift.max(1, u) where Double.random(in: 0..<1, using: &g) < pr[s % 16] { out.append(s) }
        while out.count < Swift.min(3, u) {
            let s: Int = Int.random(in: 1..<u, using: &g)
            if !out.contains(s) { out.append(s) }
        }
        return out.sorted()
    }

    /// Звук аккорда ступени-индекса k (корень, терция, квинта) ближе всего к ступени cur (номера ступеней — от
    /// корня клавиатуры, могут уходить в следующую октаву).
    static func nearestChordTone(_ cur: Int, chordRoot k: Int, n: Int, lo: Int, hi: Int, preferRoot: Bool) -> Int {
        var best: Int = cur
        var bestD: Int = Int.max
        var x: Int = lo
        while x <= hi {
            let r: Int = Scales.wrap(x - k, n)
            let tone: Bool = preferRoot ? r == 0 : (r == 0 || r == 2 || r == 4)
            if tone {
                let d: Int = Swift.abs(x - cur)
                if d < bestD {
                    bestD = d
                    best = x
                }
            }
            x += 1
        }
        return best
    }

    /// Следующая ступень мелодии: шаг ±1 (чаще), ±2, изредка скачок ±3…4; в пределах lo…hi.
    static func walk<G: RandomNumberGenerator>(_ cur: Int, lo: Int, hi: Int, using g: inout G) -> Int {
        let x: Double = Double.random(in: 0..<1, using: &g)
        let size: Int = x < 0.55 ? 1 : (x < 0.85 ? 2 : Int.random(in: 3...4, using: &g))
        var dir: Int = Bool.random(using: &g) ? 1 : -1
        if cur + dir * size > hi { dir = -1 }
        if cur + dir * size < lo { dir = 1 }
        return Swift.max(lo, Swift.min(hi, cur + dir * size))
    }

    /// Мелодия на страницы lens по прогрессии degrees. Отрезки фразы — такты (одна страница — полтакта): A, A′, A,
    /// B по кругу, последний — B с концом на корне своего аккорда; A — мотив (ритм и шаги от корня аккорда), повтор A —
    /// тот же мотив от корня нового аккорда, A′ — с другим концом (2 последние ноты), B — новый ритм и шаги.
    /// Сильные доли (шаги 1, 5, 9, 13) — звуки аккорда; диапазон — полторы октавы от октавы клавиатуры.
    /// Длина — до следующей ноты или короче (legato по стилю); velocity — доли 100 %, остальные 70–85 %.
    public static func lead<G: RandomNumberGenerator>(style: Int, bpm: Double, lens: [Int], degrees: [Int],
                                                      scale: Int, root: Int, octave oct: Int,
                                                      using g: inout G) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        if playing.isEmpty || degrees.isEmpty { return out }
        let gr: Int = DrumRhythm.groove(style, bpm: bpm).rawValue
        let pr: [Double] = leadRhythms[gr]
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let lo: Int = 0
        let hi: Int = n + n / 2
        let per: Int = Params.stepsPerPage
        let total: Int = playing.count * per
        let u: Int = playing.count == 1 ? per / 2 : per
        let units: Int = total / u
        // Мотив A: шаги и ступени от корня аккорда.
        var motif: [(Int, Int)] = []
        var cur: Int = Int.random(in: 0...(n / 2), using: &g)
        var events: [(abs: Int, deg: Int)] = []
        for ui in 0..<units {
            let start: Int = ui * u
            let ci: Int = Swift.min(degrees.count - 1, start * degrees.count / total)
            let k: Int = Chords.degreeIndex(degrees[ci], scale: scale)
            let last: Bool = ui == units - 1
            let kind: Int = last ? 3 : ui % 4
            if (kind == 0 || kind == 2) && !motif.isEmpty || kind == 1 {
                // Повтор мотива от корня аккорда; A′ — новые 2 последние ноты.
                for (j, m) in motif.enumerated() {
                    let abs: Int = start + m.0
                    var d: Int = Swift.max(lo, Swift.min(hi, k + m.1))
                    if kind == 1 && j >= motif.count - 2 { d = walk(d, lo: lo, hi: hi, using: &g) }
                    if abs % 4 == 0 {
                        let cj: Int = Swift.min(degrees.count - 1, abs * degrees.count / total)
                        let kk: Int = Chords.degreeIndex(degrees[cj], scale: scale)
                        d = nearestChordTone(d, chordRoot: kk, n: n, lo: lo, hi: hi, preferRoot: false)
                    }
                    events.append((abs, d))
                    cur = d
                }
                continue
            }
            let steps: [Int] = leadSteps(pr, len: u, using: &g)
            var made: [(Int, Int)] = []
            for (j, s) in steps.enumerated() {
                let abs: Int = start + s
                let cj: Int = Swift.min(degrees.count - 1, abs * degrees.count / total)
                let kk: Int = Chords.degreeIndex(degrees[cj], scale: scale)
                var d: Int = j == 0 && events.isEmpty ? cur : walk(cur, lo: lo, hi: hi, using: &g)
                if abs % 4 == 0 { d = nearestChordTone(d, chordRoot: kk, n: n, lo: lo, hi: hi, preferRoot: false) }
                if last && j == steps.count - 1 {
                    d = nearestChordTone(d, chordRoot: kk, n: n, lo: lo, hi: hi, preferRoot: true)
                }
                events.append((abs, d))
                made.append((s, d - k))
                cur = d
            }
            if kind == 0 && motif.isEmpty { motif = made }
        }
        let legato: Double = leadLegatos[gr]
        for (i, e) in events.enumerated() {
            let pi: Int = e.abs / per
            let st: Int = e.abs % per
            let p: Int = playing[Swift.min(playing.count - 1, pi)]
            if st >= lens[p] { continue }
            let next: Int = i + 1 < events.count ? events[i + 1].abs : total
            let gap: Int = Swift.max(1, Swift.min(next - e.abs, lens[p] - st))
            let long: Bool = i == events.count - 1 || Double.random(in: 0..<1, using: &g) < legato
            let len: Int = long ? gap : Swift.min(gap, Int.random(in: 1...2, using: &g))
            let note: Int = Swift.min(127, Swift.max(0, Scales.note(scale: scale, root: root, octave: oct, degree: e.deg)))
            let v: Double = st % 4 == 0 ? DrumRhythm.velFull : Double.random(in: DrumRhythm.velMid, using: &g).rounded()
            out[p].append(SliceRhythm.Event(step: st, note: note, len: len, vel: v))
        }
        return out
    }
}

extension Track {
    /// Случайная мелодия (LEAD) стиля проекта на страницы range по прогрессии degrees: прежние шаги этих страниц
    /// стираются, ноты — со своей длиной и velocity.
    public mutating func writeRandomLead<G: RandomNumberGenerator>(pages range: ClosedRange<Int>, degrees: [Int],
                                                                   scale: Int, root: Int, octave: Int, bpm: Double,
                                                                   using g: inout G) {
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[SliceRhythm.Event]] = MelodyRhythm.lead(style: drumStyle, bpm: bpm, lens: lens, degrees: degrees,
                                                               scale: scale, root: root, octave: octave, using: &g)
        writeSlices(pattern, pages: range)
    }
}
