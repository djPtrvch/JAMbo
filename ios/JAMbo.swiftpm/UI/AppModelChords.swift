import Foundation

// Режим CHORD: случайная прогрессия (SHIFT + CHORD) — запись аккордов в выбранные страницы открытого паттерна; на
// ударном движке (KICK, SNARE, HAT, CLAP, PERC) — случайный ритм стиля дорожки (DrumRhythm), на нарезанном сэмпле
// (SETTINGS → RANDOM → SAMPLES) — случайный рисунок кусков (SliceRhythm); стили — в окне CHORD.

extension AppModel {
    /// Тап по CHORD: с SHIFT — случайная прогрессия (режим не меняется), иначе — вкл./выкл. режима. Кнопка RANDOM
    /// (ударная при DRUMS, нарезанная дорожка) — моментальная: тап сразу пишет случайный ритм, без SHIFT.
    func chordTap() {
        if randomButton {
            if settings.randomStepsAll {
                writeEnsemble()
            } else if drumTrack {
                writeRandomDrums()
            } else {
                writeRandomSlices()
            }
            return
        }
        if shiftHeld && settings.randomStepsAll {
            // STEPS ALL TRACKS: партии сразу на всех дорожках (AppModelEnsemble).
            writeEnsemble()
        } else if shiftHeld {
            // SETTINGS → RANDOM: выключенный DRUMS или CHORDS — ничего.
            if drumTrack {
                if settings.randomDrums { writeRandomDrums() }
            } else if sliceTrack {
                writeRandomSlices()
            } else if settings.randomChords {
                if arpMode {
                    writeRandomArp()
                } else if melodyRole == .bass {
                    writeRandomBass()
                } else if melodyRole == .keys || melodyRole == .pad {
                    writeRandomChordPart(melodyRole)
                } else {
                    writeRandomLead()
                }
            }
        } else if arpMode {
            toggleArp()
        } else {
            toggleChord()
        }
    }

    /// Дорожка с ударным движком (KICK, SNARE, HAT, CLAP, PERC): у CHORD — стили ритма вместо типов аккорда.
    var drumTrack: Bool {
        guard channel == .track else { return false }
        return track.drumRole != nil
    }

    /// Дорожка с нарезанным сэмплом при SETTINGS → RANDOM → SAMPLES: у CHORD — RANDOM и стили, как у ударной.
    var sliceTrack: Bool {
        guard channel == .track, settings.randomSamples else { return false }
        return track.drumRole == nil && track.hasCuts
    }

    /// У кнопки CHORD — стили вместо типов аккорда (ударная или нарезанная дорожка; в режиме ARP — направления).
    var styleTrack: Bool { return drumTrack || sliceTrack }

    /// Кнопка в режиме RANDOM (не ARP; ударная при DRUMS или нарезанная дорожка): моментальная — горит, пока
    /// нажата, тап пишет случайный ритм; режима аккордов у неё нет.
    var randomButton: Bool {
        if arpMode { return false }
        return (drumTrack && settings.randomDrums) || sliceTrack
    }

    /// Режим аккордов клавиш выбранной дорожки (у кнопки RANDOM — нет).
    var chordOn: Bool {
        return chordMode[selectedTrack] && !randomButton
    }

    /// Слово на кнопке CHORD: ARP — в режиме ARP; RANDOM — на ударной (при DRUMS) и нарезанной дорожке.
    var chordWord: String {
        if arpMode { return "ARP" }
        return randomButton ? "RANDOM" : "CHORD"
    }

    /// Стиль ритма (хранится в проекте, одна запись UNDO) — всем дорожкам проекта (решение 4.11): и тем, что
    /// станут ударными или нарезанными позже (смена звука, маркеры, SAMPLES, ARP).
    func setDrumStyle(_ k: Int) {
        let v: Int = DrumRhythm.styleIndex(k)
        edit { p in
            for i in p.tracks.indices { p.tracks[i].drumStyle = v }
        }
    }

    /// Вариант стиля по темпу проекта (Breaks или D&B, Trap или R&B) — под словом RANDOM.
    var drumGrooveName: String {
        let gr: DrumRhythm.Groove = DrumRhythm.groove(track.drumStyle, bpm: project.bpm)
        return DrumRhythm.grooveNames[gr.rawValue]
    }

    /// Окно и MIDI CHORD TYPE n: на ударной дорожке — стиль, в режиме ARP — направление, иначе — тип аккорда.
    func chooseChordType(_ k: Int) {
        if arpMode {
            setArpDir(k)
        } else if styleTrack {
            setDrumStyle(k)
        } else {
            setChordKind(k)
        }
    }

    /// Подписи окна CHORD и под словом на кнопке: стили, направления арпеджио или типы аккорда.
    var chordTypeNames: [String] {
        if arpMode { return Arp.dirs }
        return styleTrack ? DrumRhythm.styles : Scales.chordKinds
    }

    /// Номер выбранного типа (на ударной дорожке — стиля, в ARP — направления).
    var chordTypeIndex: Int {
        if arpMode { return track.arp.dir }
        return styleTrack ? track.drumStyle : chordKind[selectedTrack]
    }

    /// Подписи клавиш в режиме CHORD: аккорд и римская ступень («Em · i»).
    func chordKeyLabel(_ k: Int) -> String {
        return Chords.keyLabel(scale: project.scale, root: project.root, octave: octave, degree: k,
                               kind: chordKind[selectedTrack])
    }

    /// Выбранные страницы открытого паттерна (playFrom…playTo); вне их — открытая страница.
    private var chordPages: ClosedRange<Int> {
        let t: Track = track
        let last: Int = t.pages.count - 1
        if t.playFrom >= 0 && t.playFrom <= t.playTo && t.playTo <= last { return t.playFrom...t.playTo }
        let v: Int = max(0, min(viewPage, last))
        return v...v
    }

    /// Роль выбранной дорожки для случайной партии (MelodyRhythm.role): звук, октава клавиатуры, CHORD, ARP.
    var melodyRole: MelodyRhythm.Role {
        return MelodyRhythm.role(sample: track.sample, octave: octave, chord: chordMode[selectedTrack], arp: arpMode)
    }

    /// Случайная прогрессия стиля проекта (MelodyRhythm.progression), не равная прошлой.
    func newProgression<G: RandomNumberGenerator>(using g: inout G) -> [Int] {
        return MelodyRhythm.progression(style: track.drumStyle, bpm: project.bpm, scale: project.scale,
                                        avoid: lastRandomProgression, using: &g)
    }

    /// Случайная мелодия (LEAD) выбранной дорожки (стиль проекта) на выбранные страницы — по прогрессии, общей с
    /// аккордами (последняя случайная; её нет — новая). Одна запись UNDO; AUTO SWING — Swing дорожки по стилю.
    func writeRandomLead() {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = lastRandomProgression ?? newProgression(using: &g)
        lastRandomProgression = degrees
        let range: ClosedRange<Int> = chordPages
        let scale: Int = project.scale
        let root: Int = project.root
        let oct: Int = octave
        let bpm: Double = project.bpm
        let swing: Bool = settings.randomSwing
        editTrack { t in
            t.writeRandomLead(pages: range, degrees: degrees, scale: scale, root: root, octave: oct, bpm: bpm, using: &g)
            if swing { t.params["swing"] = DrumRhythm.swing(t.drumStyle, bpm: bpm) }
        }
    }

    /// Случайная аккордовая партия KEYS (ритм стиля) или PAD (аккорд на отрезок) на выбранные страницы: новая
    /// прогрессия стиля (её же потом берёт бас), типы аккордов и расположение голосов — по стилю (styleChords). Одна запись UNDO; режим CHORD не меняется.
    func writeRandomChordPart(_ role: MelodyRhythm.Role) {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = newProgression(using: &g)
        lastRandomProgression = degrees
        let bpm: Double = project.bpm
        let folded: [[Int]] = MelodyRhythm.styleChords(degrees, style: track.drumStyle, bpm: bpm, scale: project.scale,
                                                       root: project.root, octave: octave, using: &g)
        let range: ClosedRange<Int> = chordPages
        let swing: Bool = settings.randomSwing
        editTrack { t in
            t.writeRandomChords(role, pages: range, chords: folded, bpm: bpm, using: &g)
            if swing && role == .keys { t.params["swing"] = DrumRhythm.swing(t.drumStyle, bpm: bpm) }
        }
    }

    /// Случайная басовая линия выбранной дорожки (стиль проекта) на выбранные страницы — по прогрессии, общей с
    /// аккордами (последняя случайная; её нет — новая). Одна запись UNDO; AUTO SWING — Swing дорожки по стилю.
    func writeRandomBass() {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = lastRandomProgression ?? newProgression(using: &g)
        lastRandomProgression = degrees
        let range: ClosedRange<Int> = chordPages
        let scale: Int = project.scale
        let root: Int = project.root
        let oct: Int = octave
        let bpm: Double = project.bpm
        let swing: Bool = settings.randomSwing
        editTrack { t in
            t.writeRandomBass(pages: range, degrees: degrees, scale: scale, root: root, octave: oct, bpm: bpm, using: &g)
            if swing { t.params["swing"] = DrumRhythm.swing(t.drumStyle, bpm: bpm) }
        }
    }

    /// Режим ARP: случайная прогрессия стиля (newProgression) с типами аккордов стиля, разложенная по шагам выбранных страниц —
    /// четверть на аккорд, фигура по направлению, ритм стиля проекта, октавы, RATE и GATE арпеджиатора
    /// (Arp.randomSteps). Одна запись UNDO; ARP не меняется.
    func writeRandomArp() {
        guard channel == .track else { return }
        var g = SystemRandomNumberGenerator()
        let degrees: [Int] = newProgression(using: &g)
        lastRandomProgression = degrees
        // Типы аккордов — по стилю (styleChords); каждый аккорд — в октаве клавиатуры (обращением, без drop 2 и
        // корня ниже): с OCTAVES 1 арпеджио не разбегается на две октавы.
        let cs: [[Int]] = MelodyRhythm.styleChords(degrees, style: track.drumStyle, bpm: project.bpm, scale: project.scale,
                                                   root: project.root, octave: octave, using: &g)
        let range: ClosedRange<Int> = chordPages
        let a: TrackArp = track.arp
        let folded: [[Int]] = Arp.fold(cs, base: Scales.baseNote(root: project.root, octave: octave))
        let total: Int = (range.upperBound - range.lowerBound + 1) * Params.stepsPerPage
        let notes: [ArpStepNote] = Arp.randomSteps(folded, steps: total, dir: a.dir, octaves: a.octaves,
                                                   rate: a.rate, gate: a.gate, style: track.drumStyle,
                                                   bpm: project.bpm, using: &g)
        editTrack { t in t.writeArpSteps(notes, pages: range) }
    }

    /// Случайный ритм ударного движка выбранной дорожки (KICK, SNARE, HAT, CLAP, PERC) на выбранные страницы: по
    /// длинам страниц (короткая — своей длиной), нота — корневая в октаве клавиатуры; на все дорожки сразу — STEPS ALL
    /// TRACKS (writeEnsemble). AUTO SWING — Swing дорожки по стилю. Одна запись UNDO.
    func writeRandomDrums() {
        guard channel == .track, track.drumRole != nil else { return }
        let range: ClosedRange<Int> = chordPages
        var g = SystemRandomNumberGenerator()
        let id: Int = track.id
        let avoid: [Int]? = lastRandomDrums[id]
        let note: Int = Scales.baseNote(root: project.root, octave: octave)
        let bpm: Double = project.bpm
        let swing: Bool = settings.randomSwing
        var steps: [Int]? = nil
        editTrack { t in
            steps = t.writeRandomDrums(pages: range, note: note, bpm: bpm, avoid: avoid, using: &g)
            if swing { t.params["swing"] = DrumRhythm.swing(t.drumStyle, bpm: bpm) }
        }
        lastRandomDrums[id] = steps
    }

    /// Случайный рисунок нарезанного сэмпла выбранной дорожки на выбранные страницы (SliceRhythm): куски —
    /// от маркера до следующего, длина в шагах по темпу (с WARP — по долям карты), ноты — как у маркеров.
    /// Одна запись UNDO; рисунок не повторяет прошлый рисунок дорожки.
    func writeRandomSlices() {
        guard sliceTrack else { return }
        let key: String = track.sample
        guard let d = sample(key) else { return }
        let cut = slicePieces(key, d)
        let pieces: [SliceRhythm.Piece] = cut.pieces
        if pieces.isEmpty { return }
        let range: ClosedRange<Int> = chordPages
        let id: Int = track.id
        var g = SystemRandomNumberGenerator()
        let avoid: [Int]? = lastRandomDrums[-1 - id]
        var code: [Int]? = nil
        let cuts: [Int: SliceRhythm.Cut] = cut.cuts
        let bpm: Double = project.bpm
        let swing: Bool = settings.randomSwing
        editTrack { t in
            code = t.writeRandomSlices(pieces, pages: range, avoid: avoid, cuts: cuts, bpm: bpm, using: &g)
            if swing { t.params["swing"] = DrumRhythm.swing(t.drumStyle, bpm: bpm) }
        }
        lastRandomDrums[-1 - id] = code
    }

    /// Куски нарезки сэмпла key дорожки (SliceRhythm.pieces): по маркерам с нотой, без них — по меткам без ноты
    /// (отрезки — в cuts); длина в шагах — с включённым WARP по долям карты меток, иначе по времени в темпе проекта.
    /// t и oct — дорожка и её октава клавиатуры (по умолчанию — выбранная).
    func slicePieces(_ key: String, _ d: SampleData, track tr: Track? = nil,
                     octave oc: Int? = nil) -> (pieces: [SliceRhythm.Piece], cuts: [Int: SliceRhythm.Cut]) {
        let t: Track = tr ?? track
        let marks: [SliceMark] = t.sliceMarks(key)
        let notes: [Int] = Slices.notes(marks, map: settings.sliceMap, scale: project.scale, root: project.root,
                                        octave: oc ?? octave)
        let info: WarpInfo? = t.warps[key]
        let frames: Double = Double(max(1, d.frames))
        var warp: WarpMap? = nil
        if let i = info, !i.isEmpty, !i.isOff {
            warp = WarpMap(i, frames: d.frames, bpm: WarpMap.bpm(i, detected: d.loopBpm, follow: warpFollowBpm))
        }
        let stepSec: Double = 15 / max(1, project.bpm)
        let dur: Double = d.duration
        return SliceRhythm.pieces(marks, notes: notes) { a, b in
            if let w = warp { return (w.beat(b * frames) - w.beat(a * frames)) * 4 }
            return (b - a) * dur / stepSec
        }
    }

    /// Октава клавиатуры дорожки i (у каждой своя).
    func octaveOf(_ i: Int) -> Int {
        guard i >= 0 && i < octaves.count else { return Scales.octaveDef }
        return min(octaves[i], topOctave)
    }
}
