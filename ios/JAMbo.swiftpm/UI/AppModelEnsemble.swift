import Foundation

// Ансамбль (SETTINGS → RANDOM → STEPS ALL TRACKS; docs/ai/sequencer.md, «Случайная партия»): SHIFT + тап по CHORD
// (и тап по RANDOM) — партии сразу на всех дорожках со звуком, каждая по своей роли, по одной новой прогрессии стиля.

/// Партия одной дорожки ансамбля (считается до правки проекта).
enum EnsembleJob {
    case drums(note: Int, role: DrumRhythm.Role)
    case slices(pieces: [SliceRhythm.Piece], cuts: [Int: SliceRhythm.Cut], note: Int)
    case part(role: MelodyRhythm.Role, octave: Int, root: Int, single: Bool)
}

extension AppModel {
    /// Партия дорожки i по роли (рычажки DRUMS, SAMPLES, CHORDS / ARP); без звука или с выключенным рычажком — nil.
    private func ensembleJob(_ i: Int, octave oct: Int) -> EnsembleJob? {
        let t: Track = project.tracks[i]
        if t.sample.isEmpty { return nil }
        let p: Project = project
        if let dr = drumRoleOf(t) {
            return settings.randomDrums ? .drums(note: drumNote(t, octave: oct), role: dr) : nil
        }
        if settings.randomSamples && t.hasCuts {
            guard let d = sample(t.sample) else { return nil }
            let cut = slicePieces(t.sample, d, track: t, octave: oct)
            return cut.pieces.isEmpty ? nil : .slices(pieces: cut.pieces, cuts: cut.cuts, note: drumNote(t, octave: oct))
        }
        if !settings.randomChords { return nil }
        let chordOn: Bool = i < chordMode.count ? chordMode[i] : false
        let auto: MelodyRhythm.Role = MelodyRhythm.role(sample: t.sample, name: p.files[t.sample] ?? "", octave: oct,
                                                        chord: chordOn, arp: t.arp.mode)
        let role: MelodyRhythm.Role = MelodyRhythm.role(auto, part: partTypeOf(i), chord: chordOn)
        return .part(role: role, octave: oct, root: randomRoot(t), single: !chordOn)
    }

    /// Партии на всех дорожках со звуком (и заглушённых): выбранная — на выбранные страницы, остальные — на
    /// страницы своего открытого клипа; одна новая прогрессия стиля на всех (её же потом берут BASS и LEAD).
    /// Одна запись UNDO; AUTO SWING — Swing дорожек по стилю (кроме PAD). Techno — гармония Techno
    /// (technoProgression), House, Breaks, Trap, Pop, Ambient — прогрессия и тип аккорда стиля (styleProgression);
    /// ударные пишутся первыми: бас, лид и стабы обходят новую бочку (Project.kickGrid).
    func writeEnsemble() {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let ps: Int? = MelodyRhythm.partStyle(track.drumStyle, bpm: project.bpm)
        var degrees: [Int] = []
        var kind: Int = 0
        if let s = ps {
            degrees = MelodyRhythm.styleProgression(s, scale: project.scale, avoid: lastRandomProgression, using: &g)
            kind = MelodyRhythm.styleKind(s, using: &g)
        } else {
            degrees = MelodyRhythm.technoProgression(using: &g)
            kind = technoKind(new: true, using: &g)
        }
        lastRandomProgression = degrees
        let sel: Int = selectedTrack
        let selRange: ClosedRange<Int> = chordPages
        var jobs: [(Int, ClosedRange<Int>, EnsembleJob)] = []
        for i in project.tracks.indices {
            let r: ClosedRange<Int> = i == sel ? selRange : project.tracks[i].openClip.range
            let oct: Int = i == sel ? octave : octaveOf(i)
            if let j = ensembleJob(i, octave: oct) { jobs.append((i, r, j)) }
        }
        if jobs.isEmpty { return }
        // Ударные и нарезка — первыми (сетка бочки для баса и лида).
        let isDrums: (EnsembleJob) -> Bool = { j in
            if case .drums = j { return true }
            if case .slices = j { return true }
            return false
        }
        jobs = jobs.filter { isDrums($0.2) } + jobs.filter { !isDrums($0.2) }
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
                case .slices(let pieces, let cuts, let note):
                    last[-1 - id] = p.tracks[i].writeRandomSlices(pieces, pages: r, avoid: last[-1 - id], cuts: cuts,
                                                                  bpm: bpm, cutNote: note, using: &g)
                case .part(let role, let oct, let root, let single):
                    pad = role == .pad || (ps != nil && role == .arp)
                    p.tracks[i].writePart(role, style: ps, pages: r, degrees: degrees, kind: kind, scale: p.scale,
                                          root: root, octave: oct, kicks: p.kickGrid(pages: r, style: ps),
                                          single: single, using: &g)
                }
                if swing && !pad { p.tracks[i].params["swing"] = DrumRhythm.swing(p.tracks[i].drumStyle, bpm: bpm) }
            }
        }
        lastRandomDrums = last
    }
}
