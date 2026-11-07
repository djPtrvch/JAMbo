import Foundation

// Случайные аккордовые партии (SHIFT + CHORD на KEYS и PAD; docs/ai/sequencer.md, «Случайная партия»): прогрессия
// из набора стиля проекта, KEYS — ритм аккордов стиля (стабы, четверти, синкопы), PAD — аккорд на всю длину.

extension MelodyRhythm {
    /// Прогрессии стиля (ступени 1…7 гаммы) по рисунку DrumRhythm.Groove.
    static let progressions: [[[Int]]] = [
        [[1, 7, 6, 7], [1, 6, 4, 5], [2, 5, 1, 1], [1, 4, 6, 5]],   // house
        [[1, 1, 1, 1], [1, 1, 6, 6], [1, 6, 1, 7], [1, 1, 4, 1]],   // techno
        [[1, 7, 6, 7], [1, 6, 7, 1], [1, 4, 7, 1]],                 // breaks
        [[1, 6, 3, 7], [1, 6, 4, 5], [6, 4, 1, 5]],                 // dnb
        [[1, 6, 3, 7], [1, 6, 7, 6], [1, 1, 6, 6]],                 // trap
        [[2, 5, 1, 1], [4, 3, 6, 6], [1, 6, 2, 5], [4, 5, 3, 6]],   // rnb
        [[1, 5, 6, 4], [6, 4, 1, 5], [1, 4, 6, 5], [1, 6, 4, 5]],   // pop
        [[1, 4, 1, 4], [1, 6, 1, 6], [4, 1, 4, 1], [1, 1, 4, 4]],   // ambient
    ]

    /// Случайная прогрессия стиля: 75 % — из набора стиля, 25 % — свободная (Chords.random); не равна avoid,
    /// если получится за 16 попыток. Ступени выше числа ступеней гаммы — по модулю (пентатоника).
    public static func progression<G: RandomNumberGenerator>(style: Int, bpm: Double, scale: Int, avoid: [Int]?,
                                                             using g: inout G) -> [Int] {
        let pool: [[Int]] = progressions[DrumRhythm.groove(style, bpm: bpm).rawValue]
        var out: [Int] = []
        var tries: Int = 0
        repeat {
            if Double.random(in: 0..<1, using: &g) < 0.75, let p = pool.randomElement(using: &g) {
                out = p
            } else {
                out = Chords.random(scale: scale, using: &g)
            }
            tries += 1
        } while out == avoid && tries < 16
        return out
    }

    /// Ритм аккордов KEYS по стилю: варианты, удар — (шаг 0…15 в такте, длина в шагах).
    static let keysRhythms: [[[(Int, Int)]]] = [
        [[(2, 1), (6, 1), (10, 1), (14, 1)], [(0, 2), (3, 1), (6, 1), (10, 2), (13, 1)]],     // house: офбит-стабы
        [[(2, 1), (7, 1), (10, 1)], [(0, 16)], [(3, 1), (6, 1), (11, 1), (14, 1)]],           // techno: даб-стабы, дрон
        [[(0, 3), (6, 2), (10, 3)], [(0, 2), (3, 2), (8, 2), (11, 3)]],                       // breaks
        [[(0, 8), (8, 8)], [(0, 16)], [(0, 6), (10, 6)]],                                     // dnb
        [[(0, 16)], [(0, 6), (8, 6)], [(0, 3), (3, 3), (8, 8)]],                              // trap
        [[(0, 3), (3, 3), (7, 2), (10, 4)], [(0, 16)], [(0, 6), (6, 4), (11, 5)]],            // rnb
        [[(0, 3), (4, 3), (8, 3), (12, 3)], [(0, 6), (6, 2), (8, 6), (14, 2)], [(0, 2), (2, 2), (4, 2), (6, 2), (8, 2), (10, 2), (12, 2), (14, 2)]], // pop
        [[(0, 16)], [(0, 8), (8, 8)]],                                                        // ambient
    ]

    /// Аккордовая партия на страницы lens по аккордам chords (поровну на все играющие шаги, как Chords.places):
    /// KEYS — ритм стиля (один вариант на рисунок, повтор по тактам; в отрезке аккорда короче такта — его начало),
    /// PAD — аккорд на весь свой отрезок (с новой страницы — заново). Ноты не переходят за страницу; velocity — доли 100 %, остальные 70–85 % (PAD — 75–85 %).
    public static func chordPart<G: RandomNumberGenerator>(_ role: Role, style: Int, bpm: Double, lens: [Int],
                                                           chords: [[Int]], using g: inout G) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        if playing.isEmpty || chords.isEmpty { return out }
        let per: Int = Params.stepsPerPage
        let total: Int = playing.count * per
        let seg: Int = Swift.max(1, total / chords.count)
        let pool: [[(Int, Int)]] = keysRhythms[DrumRhythm.groove(style, bpm: bpm).rawValue]
        let hits: [(Int, Int)] = role == .pad ? [(0, per)] : (pool.randomElement(using: &g) ?? [(0, per)])
        for (ci, chord) in chords.enumerated() {
            let start: Int = ci * seg
            let end: Int = ci == chords.count - 1 ? total : start + seg
            var bar: Int = start
            while bar < end {
                for (at, l) in hits {
                    let s: Int = bar + at
                    if s >= end { continue }
                    let pi: Int = s / per
                    let st: Int = s % per
                    let p: Int = playing[pi]
                    if st >= lens[p] { continue }
                    let want: Int = role == .pad ? end - s : l
                    let len: Int = Swift.max(1, Swift.min(want, end - s, lens[p] - st))
                    var v: Double = st % 4 == 0 ? DrumRhythm.velFull : Double.random(in: DrumRhythm.velMid, using: &g).rounded()
                    if role == .pad { v = Double.random(in: 95...108, using: &g).rounded() }
                    for n in chord {
                        out[p].append(SliceRhythm.Event(step: st, note: n, len: len, vel: v))
                    }
                }
                bar += per
            }
        }
        return out
    }
}

extension Track {
    /// Случайная аккордовая партия (KEYS или PAD) стиля проекта на страницы range по аккордам chords: прежние шаги
    /// этих страниц стираются, ноты — со своей длиной и velocity.
    public mutating func writeRandomChords<G: RandomNumberGenerator>(_ role: MelodyRhythm.Role, pages range: ClosedRange<Int>,
                                                                     chords: [[Int]], bpm: Double, using g: inout G) {
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[SliceRhythm.Event]] = MelodyRhythm.chordPart(role, style: drumStyle, bpm: bpm, lens: lens,
                                                                   chords: chords, using: &g)
        writeSlices(pattern, pages: range)
    }
}
