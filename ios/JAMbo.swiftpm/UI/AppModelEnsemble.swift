import Foundation

// Ансамбль (SETTINGS → RANDOM → STEPS ALL TRACKS; docs/ai/sequencer.md, «Случайная партия»): SHIFT + тап по CHORD
// (и тап по RANDOM) — партии сразу на всех дорожках со звуком, каждая по своей роли, по одной новой прогрессии стиля.

/// Партия одной дорожки ансамбля (считается до правки проекта).
enum EnsembleJob {
    case drums(note: Int, role: DrumRhythm.Role)
    case slices(pieces: [SliceRhythm.Piece], cuts: [Int: SliceRhythm.Cut])
    case bass(octave: Int, root: Int)
    case chords(role: MelodyRhythm.Role, chords: [[Int]])
    case lead(octave: Int, root: Int)
    case arp(notes: [ArpStepNote])
}

extension AppModel {
    /// Партия дорожки i по роли (рычажки DRUMS, SAMPLES, CHORDS / ARP); без звука или с выключенным рычажком — nil.
    private func ensembleJob(_ i: Int, degrees: [Int], range: ClosedRange<Int>, octave oct: Int,
                                                      using g: inout Rng) -> EnsembleJob? {
        let t: Track = project.tracks[i]
        if t.sample.isEmpty { return nil }
        let p: Project = project
        if let dr = drumRoleOf(t) {
            return settings.randomDrums ? .drums(note: drumNote(t, octave: oct), role: dr) : nil
        }
        if settings.randomSamples && t.hasCuts {
            guard let d = sample(t.sample) else { return nil }
            let cut = slicePieces(t.sample, d, track: t, octave: oct)
            return cut.pieces.isEmpty ? nil : .slices(pieces: cut.pieces, cuts: cut.cuts)
        }
        if !settings.randomChords { return nil }
        let chordOn: Bool = i < chordMode.count ? chordMode[i] : false
        let auto: MelodyRhythm.Role = MelodyRhythm.role(sample: t.sample, name: p.files[t.sample] ?? "", octave: oct,
                                                        chord: chordOn, arp: t.arp.mode)
        let role: MelodyRhythm.Role = MelodyRhythm.role(auto, part: partTypeOf(i), chord: chordOn)
        switch role {
        case .bass: return .bass(octave: oct, root: randomRoot(t))
        case .lead: return .lead(octave: oct, root: randomRoot(t))
        case .keys, .pad:
            let cs: [[Int]] = MelodyRhythm.styleChords(degrees, style: t.drumStyle, bpm: p.bpm, scale: p.scale,
                                                       root: randomRoot(t), octave: oct, using: &g)
            return .chords(role: role, chords: cs)
        case .arp:
            let cs: [[Int]] = MelodyRhythm.styleChords(degrees, style: t.drumStyle, bpm: p.bpm, scale: p.scale,
                                                       root: randomRoot(t), octave: oct, using: &g)
            let folded: [[Int]] = Arp.fold(cs, base: Scales.baseNote(root: randomRoot(t), octave: oct))
            let total: Int = (range.upperBound - range.lowerBound + 1) * Params.stepsPerPage
            let a: TrackArp = t.arp
            let notes: [ArpStepNote] = Arp.randomSteps(folded, steps: total, dir: a.dir, octaves: a.octaves, rate: a.rate,
                                                       gate: a.gate, style: t.drumStyle, bpm: p.bpm, using: &g)
            return .arp(notes: notes)
        }
    }

    /// Партии на всех дорожках со звуком (и заглушённых): выбранная — на выбранные страницы, остальные — на
    /// страницы своего открытого клипа; одна новая прогрессия стиля на всех (её же потом берут BASS и LEAD).
    /// Одна запись UNDO; AUTO SWING — Swing дорожек по стилю (кроме PAD).
    func writeEnsemble() {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = newProgression(using: &g)
        lastRandomProgression = degrees
        let sel: Int = selectedTrack
        let selRange: ClosedRange<Int> = chordPages
        var jobs: [(Int, ClosedRange<Int>, EnsembleJob)] = []
        for i in project.tracks.indices {
            let r: ClosedRange<Int> = i == sel ? selRange : project.tracks[i].openClip.range
            let oct: Int = i == sel ? octave : octaveOf(i)
            if let j = ensembleJob(i, degrees: degrees, range: r, octave: oct, using: &g) { jobs.append((i, r, j)) }
        }
        if jobs.isEmpty { return }
        var last: [Int: [Int]] = lastRandomDrums
        let swing: Bool = settings.randomSwing
        edit { p in
            let bpm: Double = p.bpm
            for (i, r, job) in jobs where i < p.tracks.count {
                let id: Int = p.tracks[i].id
                var pad: Bool = false
                switch job {
                case .drums(let note, let role):
                    last[id] = p.tracks[i].writeRandomDrums(pages: r, note: note, bpm: bpm, avoid: last[id], role: role,
                                                            using: &g)
                case .slices(let pieces, let cuts):
                    last[-1 - id] = p.tracks[i].writeRandomSlices(pieces, pages: r, avoid: last[-1 - id], cuts: cuts,
                                                                  bpm: bpm, using: &g)
                case .bass(let oct, let root):
                    p.tracks[i].writeRandomBass(pages: r, degrees: degrees, scale: p.scale, root: root, octave: oct,
                                                bpm: bpm, using: &g)
                case .chords(let role, let cs):
                    pad = role == .pad
                    p.tracks[i].writeRandomChords(role, pages: r, chords: cs, bpm: bpm, using: &g)
                case .lead(let oct, let root):
                    p.tracks[i].writeRandomLead(pages: r, degrees: degrees, scale: p.scale, root: root, octave: oct,
                                                bpm: bpm, using: &g)
                case .arp(let notes):
                    p.tracks[i].writeArpSteps(notes, pages: r)
                }
                if swing && !pad { p.tracks[i].params["swing"] = DrumRhythm.swing(p.tracks[i].drumStyle, bpm: bpm) }
            }
        }
        lastRandomDrums = last
    }
}
