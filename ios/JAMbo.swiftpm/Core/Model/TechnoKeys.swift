import Foundation

// KEYS и ARP в стиле Techno (docs/ai/sequencer.md, «Случайная партия Techno», «Случайное арпеджио»): ячейки стабов,
// голоса KEYS, тесное расположение, запись на дорожку; ноты строит общий генератор (TechnoRun.swift).

extension MelodyRhythm {
    /// Ячейки стабов KEYS (шаги 0…15; S1…S7) и их веса.
    static let technoKeysCells: [[Int]] = hexRows("2a 3a 26ae 25ad 36be 26b 6e")
    static let technoKeysWeights: [Double] = [20, 15, 15, 15, 15, 10, 10]

    /// Голоса KEYS без корня (ступени от корня) по типу аккорда: m7 — 3, 5, 7; m9 — 5, 7, 9; квинта + септима — 5, 7, 8.
    static let technoKeysVoices: [[Int]] = hexRows("246 468 467")

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
