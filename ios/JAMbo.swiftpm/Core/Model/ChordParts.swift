import Foundation

// Случайные аккордовые партии (SHIFT + CHORD на KEYS и PAD; docs/ai/sequencer.md, «Случайная партия»): прогрессия
// из набора стиля проекта, KEYS — ритм аккордов стиля (стабы, четверти, синкопы), PAD — аккорд на всю длину.

extension MelodyRhythm {
    /// Прогрессии стиля (ступени 1…7 гаммы) по рисунку DrumRhythm.Groove.
    static let progressions: [[[Int]]] = [
        [[1, 7, 6, 7], [1, 6, 4, 5], [2, 5, 1, 1], [1, 4, 6, 5], [1, 4, 1, 7], [6, 7, 1, 1]],   // house
        [[1, 1, 1, 1], [1, 1, 6, 6], [1, 6, 1, 7], [1, 1, 4, 1], [1, 2, 1, 2], [1, 1, 7, 6]],   // techno
        [[1, 7, 6, 7], [1, 6, 7, 1], [1, 4, 7, 1], [1, 3, 4, 6], [1, 7, 4, 4]],                 // breaks
        [[1, 6, 3, 7], [1, 6, 4, 5], [6, 4, 1, 5], [1, 4, 6, 3], [4, 5, 3, 6]],                 // dnb
        [[1, 6, 3, 7], [1, 6, 7, 6], [1, 1, 6, 6], [1, 4, 6, 5], [6, 6, 1, 7]],                 // trap
        [[2, 5, 1, 1], [4, 3, 6, 6], [1, 6, 2, 5], [4, 5, 3, 6], [1, 3, 4, 4], [2, 3, 4, 5]],   // rnb
        [[1, 5, 6, 4], [6, 4, 1, 5], [1, 4, 6, 5], [1, 6, 4, 5], [4, 1, 5, 6], [1, 5, 4, 4]],   // pop
        [[1, 4, 1, 4], [1, 6, 1, 6], [4, 1, 4, 1], [1, 1, 4, 4], [1, 3, 4, 1], [6, 4, 6, 4]],   // ambient
    ]

    /// Типы аккорда по стилю (номера Scales.chordKinds: 0 Triad, 1 7th, 2 9th, 3 Sus2, 4 Sus4, 5 Add9) и их доли.
    static let kindPools: [[(Int, Double)]] = [
        [(1, 0.45), (2, 0.3), (0, 0.15), (5, 0.1)],               // house: m7, m9-стабы
        [(0, 0.3), (3, 0.25), (4, 0.2), (1, 0.25)],               // techno: простые, sus
        [(1, 0.4), (0, 0.3), (2, 0.2), (4, 0.1)],                 // breaks
        [(2, 0.35), (1, 0.3), (5, 0.2), (3, 0.15)],               // dnb: liquid — 9th, add9
        [(0, 0.45), (1, 0.35), (3, 0.2)],                         // trap
        [(1, 0.4), (2, 0.4), (5, 0.1), (4, 0.1)],                 // rnb: 7th, 9th
        [(0, 0.5), (5, 0.2), (3, 0.1), (4, 0.1), (1, 0.1)],       // pop: трезвучия, add9, sus
        [(3, 0.3), (5, 0.3), (2, 0.25), (1, 0.15)],               // ambient: sus2, add9, 9th
    ]

    /// Расположение голосов: 0 — тесное (в октаве клавиатуры), 1 — drop 2 (второй сверху — на октаву вниз),
    /// 2 — тесное с корнем октавой ниже. Доли по стилю.
    static let voicingPools: [[(Int, Double)]] = [
        [(0, 0.7), (1, 0.3)], [(0, 1)], [(0, 0.6), (1, 0.4)], [(1, 0.5), (0, 0.5)],
        [(0, 0.6), (2, 0.4)], [(1, 0.7), (0, 0.3)], [(0, 0.5), (2, 0.5)], [(1, 0.6), (2, 0.4)],
    ]

    static func pickWeighted<G: RandomNumberGenerator>(_ pool: [(Int, Double)], using g: inout G) -> Int {
        return pick(pool.map { $0.0 }, pool.map { $0.1 }, using: &g)
    }

    /// Аккорды прогрессии degrees в стиле: тип — у каждого свой (из набора стиля, два одинаковых аккорда подряд — тот
    /// же тип), расположение голосов — одно на рисунок; ноты — в октаве клавиатуры (обращения для плавных переходов),
    /// drop 2 и корень ниже — не ниже 0.
    public static func styleChords<G: RandomNumberGenerator>(_ degrees: [Int], style: Int, bpm: Double, scale: Int,
                                                             root: Int, octave: Int, using g: inout G) -> [[Int]] {
        let gr: Int = DrumRhythm.groove(style, bpm: bpm).rawValue
        let voicing: Int = pickWeighted(voicingPools[gr], using: &g)
        let base: Int = Scales.baseNote(root: root, octave: octave)
        var out: [[Int]] = []
        var lastDeg: Int = -1
        var lastKind: Int = 0
        for d in degrees {
            let kind: Int = d == lastDeg ? lastKind : pickWeighted(kindPools[gr], using: &g)
            lastDeg = d
            lastKind = kind
            let raw: [Int] = Scales.chord(scale: scale, root: root, octave: octave,
                                          degree: Chords.degreeIndex(d, scale: scale), kind: kind)
            var c: [Int] = Arp.fold([raw], base: base)[0]
            if voicing == 1 && c.count >= 3 {
                let i: Int = c.count - 2
                if c[i] - 12 >= 0 { c[i] -= 12 }
            } else if voicing == 2, let r = raw.first {
                let low: Int = base + ((r - base) % 12 + 12) % 12 - 12
                if low >= 0 && !c.contains(low) { c.append(low) }
            }
            out.append(c.sorted())
        }
        return out
    }

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
