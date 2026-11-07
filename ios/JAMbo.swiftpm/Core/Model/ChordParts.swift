import Foundation

// Случайные аккордовые партии (SHIFT + CHORD на KEYS и PAD; docs/ai/sequencer.md, «Случайная партия»): прогрессия
// из набора стиля проекта, KEYS — ритм аккордов стиля (стабы, четверти, синкопы), PAD — аккорд на всю длину.

extension MelodyRhythm {
    /// Прогрессии стиля (ступени 1…7 гаммы) по рисунку DrumRhythm.Groove.
    static let progressions: [String] = [
        "1767 1645 2511 1465 1417 6711",   // house
        "1111 1166 1617 1141 1212 1176",   // techno
        "1767 1671 1471 1346 1744",        // breaks
        "1637 1645 6415 1463 4536",        // dnb
        "1637 1676 1166 1465 6617",        // trap
        "2511 4366 1625 4536 1344 2345",   // rnb
        "1564 6415 1465 1645 4156 1544",   // pop
        "1414 1616 4141 1144 1341 6464",   // ambient
    ]

    /// Прогрессии стиля: группы по 4 цифры (ступени 1…7) через пробел.
    static func pool(_ gr: Int) -> [[Int]] {
        return progressions[gr].split(separator: " ").map { w in w.utf8.map { Int($0) - 48 } }
    }

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
        let pool: [[Int]] = MelodyRhythm.pool(DrumRhythm.groove(style, bpm: bpm).rawValue)
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
    static let keysRhythms: [String] = [
        "..1...1...1...1. 2..1..1...2..1..",                    // house: офбит-стабы
        "..1....1..1..... g............... ...1..1....1..1.",   // techno: даб-стабы, дрон
        "3.....2...3..... 2..2....2..3....",                    // breaks
        "8.......8....... g............... 6.........6.....",   // dnb
        "g............... 6.......6....... 3..3....8.......",   // trap
        "3..3...2..4..... g............... 6.....4....5....",   // rnb
        "3...3...3...3... 6.....2.6.....2. 2.2.2.2.2.2.2.2.",   // pop
        "g............... 8.......8.......",                    // ambient
    ]

    /// Удары KEYS из строки: на шаге — длина (1…9, a…g — 10…16), «.» — нет удара.
    static func hits(_ s: String) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (i, c) in s.utf8.enumerated() {
            if c >= 49 && c <= 57 { out.append((i, Int(c) - 48)) } else if c >= 97 && c <= 103 { out.append((i, Int(c) - 87)) }
        }
        return out
    }

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
        let pool: [Substring] = keysRhythms[DrumRhythm.groove(style, bpm: bpm).rawValue].split(separator: " ")
        let pick: String = String(pool.randomElement(using: &g) ?? "g")
        let hits: [(Int, Int)] = role == .pad ? [(0, per)] : MelodyRhythm.hits(pick)
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
