import Foundation

// Случайные партии мелодических дорожек (SHIFT + CHORD; docs/ai/sequencer.md, «Пианоролл»): роль дорожки
// определяется сама (движок, имя сэмпла, октава клавиатуры, CHORD, ARP); BASS — линия по стилю проекта и
// прогрессии (общей с аккордами дорожек). LEAD, KEYS, PAD — следующими этапами (пока — прогрессия).

public enum MelodyRhythm {
    /// Роль мелодической дорожки.
    public enum Role: Int, Sendable, CaseIterable { case bass, lead, keys, pad, arp }

    public static let roleNames: [String] = ["Bass", "Lead", "Keys", "Pad", "Arp"]

    /// Октава клавиатуры, с которой и ниже дорожка — BASS (C2 и ниже).
    public static let bassOctave: Int = 2

    static let bassWords: [String] = ["bass", "808", "sub", "reese"]
    static let padWords: [String] = ["pad", "atmo", "drone", "string", "ambient", "choir"]
    static let keysWords: [String] = ["chord", "keys", "piano", "stab", "organ", "rhodes", "epiano"]

    /// Роль по звуку дорожки: ARP — арпеджиатор включён; KEYS — режим CHORD; SUB — BASS; TEXTURE, GRANULAR — PAD;
    /// сэмпл — по словам в имени файла name (bass, pad, chord…); иначе по октаве клавиатуры: до C2 — BASS, выше — LEAD.
    public static func role(sample: String, name: String = "", octave: Int, chord: Bool, arp: Bool) -> Role {
        if arp { return .arp }
        if chord { return .keys }
        if let e = SynthKey.engine(sample) {
            if e == Jambo.sub { return .bass }
            if e == Jambo.texture || e == Jambo.granular { return .pad }
        } else if !sample.isEmpty {
            let name: String = DrumRhythm.words(name).joined(separator: " ")
            if bassWords.contains(where: { name.contains($0) }) { return .bass }
            if padWords.contains(where: { name.contains($0) }) { return .pad }
            if keysWords.contains(where: { name.contains($0) }) { return .keys }
        }
        return octave <= bassOctave ? .bass : .lead
    }

    // MARK: — BASS

    /// Ступени от корня аккорда: 0 — корень, 2 — терция, 4 — квинта, 6 — септима, octave — корень октавой выше.
    static let octave: Int = 100

    /// Партия баса в рисунке: вероятности шагов (варианты), длина нот (legato — до следующей), ступени и их доли.
    struct BassPart {
        let options: [[Double]]
        let len: ClosedRange<Int>
        let legato: Bool
        let degrees: [Int]
        let weights: [Double]
    }

    static func probs(_ steps: [Int: Double], rest: Double = 0) -> [Double] { return DrumRhythm.probs(steps, rest: rest) }

    /// Шаги не на долях (1, 5, 9, 13) — с вероятностью p.
    static func offFours(_ p: Double) -> [Double] {
        var out: [Double] = [Double](repeating: p, count: 16)
        for k in [0, 4, 8, 12] { out[k] = 0 }
        return out
    }

    static func bassPart(_ gr: DrumRhythm.Groove) -> BassPart {
        switch gr {
        // HOUSE: офбит (между бочками), иногда синкопа.
        case .house:
            return BassPart(options: [probs([2: 1, 6: 1, 10: 1, 14: 1, 3: 0.2, 11: 0.2, 15: 0.15]),
                                      probs([2: 1, 3: 0.5, 6: 1, 10: 1, 11: 0.5, 14: 1])],
                            len: 1...2, legato: false, degrees: [0, octave, 4], weights: [0.6, 0.25, 0.15])
        // TECHNO: «катящийся» 16-ми мимо бочки или офбит, почти одна нота.
        case .techno:
            var off: [Double] = offFours(0.3)
            for k in [2, 6, 10, 14] { off[k] = 1 }
            return BassPart(options: [offFours(0.9), off], len: 1...1, legato: false,
                            degrees: [0, octave, 4], weights: [0.85, 0.1, 0.05])
        // BREAKS: за бочкой брейка, ноты 2–3 шага.
        case .breaks:
            return BassPart(options: [probs([0: 1, 2: 0.5, 7: 0.3, 10: 1, 11: 0.4, 14: 0.3])], len: 2...3, legato: false,
                            degrees: [0, 4, octave, 6], weights: [0.5, 0.2, 0.2, 0.1])
        // D&B: длинные ноты (Reese) на 1 и 11.
        case .dnb:
            return BassPart(options: [probs([0: 1, 10: 0.7, 6: 0.3])], len: 4...16, legato: true,
                            degrees: [0, 4, 2], weights: [0.7, 0.15, 0.15])
        // TRAP: 808 на ударах бочки, тянется до следующей.
        case .trap:
            return BassPart(options: [probs([0: 1, 7: 0.4, 10: 0.5, 11: 0.3, 14: 0.3])], len: 2...16, legato: true,
                            degrees: [0, octave, 4], weights: [0.7, 0.2, 0.1])
        // R&B: синкопы, звуки аккорда.
        case .rnb:
            return BassPart(options: [probs([0: 1, 3: 0.3, 7: 0.5, 10: 0.6, 14: 0.3])], len: 2...3, legato: false,
                            degrees: [0, 2, 4, 6], weights: [0.45, 0.2, 0.2, 0.15])
        // POP: восьмые на корне («пульс») или за бочкой.
        case .pop:
            return BassPart(options: [probs(DrumRhythm.evens, rest: 0).map { $0 * 0.9 },
                                      probs([0: 1, 3: 0.4, 8: 1, 10: 0.5, 11: 0.3])],
                            len: 1...2, legato: false, degrees: [0, 4, octave], weights: [0.7, 0.2, 0.1])
        // AMBIENT: дрон — нота на страницу, иногда вторая.
        case .ambient:
            return BassPart(options: [probs([0: 1, 8: 0.25])], len: 8...16, legato: true,
                            degrees: [0, 4], weights: [0.8, 0.2])
        }
    }

    static func pick<G: RandomNumberGenerator>(_ items: [Int], _ weights: [Double], using g: inout G) -> Int {
        let total: Double = weights.reduce(0, +)
        var x: Double = Double.random(in: 0..<Swift.max(total, 0.000001), using: &g)
        for (i, w) in weights.enumerated() {
            if x < w { return items[i] }
            x -= w
        }
        return items.last ?? 0
    }

    /// Шаги ритма баса на странице длиной n (не пусто).
    static func bassSteps<G: RandomNumberGenerator>(_ part: BassPart, len n: Int, using g: inout G) -> [Int] {
        let pr: [Double] = part.options[Int.random(in: 0..<part.options.count, using: &g)]
        var out: [Int] = []
        for s in 0..<n where pr[s] > 0 && Double.random(in: 0..<1, using: &g) < pr[s] { out.append(s) }
        if out.isEmpty { out = [0] }
        return out
    }

    /// Вариация ритма: один шаг добавлен или убран (первый не снимается).
    static func varySteps<G: RandomNumberGenerator>(_ steps: [Int], len n: Int, using g: inout G) -> [Int] {
        var out: [Int] = steps.filter { $0 < n }
        let free: [Int] = (0..<n).filter { !out.contains($0) }
        if out.count > 1 && (free.isEmpty || Bool.random(using: &g)) {
            out.remove(at: Int.random(in: 1..<out.count, using: &g))
        } else if let s = free.randomElement(using: &g) {
            out.append(s)
        }
        if out.isEmpty { out = [0] }
        return out.sorted()
    }

    /// Басовая линия на страницы lens (шагов на странице, 0 — не играет) по прогрессии degrees (ступени 1…7,
    /// аккорды поровну на все шаги — как Chords.places): первая играющая страница — основа ритма, средние — вариации,
    /// последняя — сбивка в последних 4 шагах (подход к корню первого аккорда). Первая нота каждого аккорда — его
    /// корень. Ноты — в гамме от октавы клавиатуры; velocity — доли 100 %, остальные 70–85 %.
    public static func bass<G: RandomNumberGenerator>(style: Int, bpm: Double, lens: [Int], degrees: [Int],
                                                      scale: Int, root: Int, octave oct: Int,
                                                      using g: inout G) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = lens.map { _ in [] }
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        guard let first = playing.first, let last = playing.last, !degrees.isEmpty else { return out }
        let part: BassPart = bassPart(DrumRhythm.groove(style, bpm: bpm))
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let total: Int = playing.count * Params.stepsPerPage
        let baseSteps: [Int] = bassSteps(part, len: lens[first], using: &g)
        var lastChord: Int = -1
        for (pi, p) in playing.enumerated() {
            let len: Int = lens[p]
            var steps: [Int] = p == first ? baseSteps : varySteps(baseSteps, len: len, using: &g)
            let fillFrom: Int = Swift.max(0, len - 4)
            if p == last && last != first {
                steps = steps.filter { $0 < fillFrom }
                for s in fillFrom..<len where Double.random(in: 0..<1, using: &g) < 0.5 { steps.append(s) }
                if !steps.contains(where: { $0 >= fillFrom }) { steps.append(Int.random(in: fillFrom..<len, using: &g)) }
                steps.sort()
            }
            var evs: [SliceRhythm.Event] = []
            for (i, s) in steps.enumerated() {
                let abs: Int = pi * Params.stepsPerPage + s
                let ci: Int = Swift.min(degrees.count - 1, abs * degrees.count / Swift.max(1, total))
                let k: Int = Chords.degreeIndex(degrees[ci], scale: scale)
                var d: Int = ci != lastChord ? 0 : pick(part.degrees, part.weights, using: &g)
                lastChord = ci
                // Сбивка: подход к корню первого аккорда — ступень выше или ниже, квинта.
                if p == last && last != first && s >= fillFrom { d = [1, -1, 4].randomElement(using: &g) ?? 0 }
                let deg: Int = d == octave ? k + n : k + d
                let note: Int = Swift.min(127, Swift.max(0, Scales.note(scale: scale, root: root, octave: oct, degree: deg)))
                let next: Int = i + 1 < steps.count ? steps[i + 1] : len
                let gap: Int = Swift.max(1, next - s)
                let l: Int = part.legato ? Swift.min(gap, part.len.upperBound)
                                         : Swift.min(gap, Int.random(in: part.len, using: &g))
                let v: Double = s % 4 == 0 ? DrumRhythm.velFull : Double.random(in: DrumRhythm.velMid, using: &g).rounded()
                evs.append(SliceRhythm.Event(step: s, note: note, len: Swift.max(1, l), vel: v))
            }
            out[p] = evs
        }
        return out
    }
}

extension Track {
    /// Случайная басовая линия стиля проекта на страницы range (по их длинам) по прогрессии degrees: прежние шаги
    /// этих страниц стираются, ноты — со своей длиной и velocity.
    public mutating func writeRandomBass<G: RandomNumberGenerator>(pages range: ClosedRange<Int>, degrees: [Int],
                                                                   scale: Int, root: Int, octave: Int, bpm: Double,
                                                                   using g: inout G) {
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[SliceRhythm.Event]] = MelodyRhythm.bass(style: drumStyle, bpm: bpm, lens: lens, degrees: degrees,
                                                               scale: scale, root: root, octave: octave, using: &g)
        writeSlices(pattern, pages: range)
    }
}
