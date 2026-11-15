import Foundation

// Роли случайных партий House, Breaks, Trap, Pop, Ambient (docs/ai/sequencer.md, «Случайная партия по стилю»):
// BASS, LEAD, KEYS, PAD, ARP; таблицы, отрезки аккордов, ритм и запись нот — StyleParts.swift. Ритм для нарезки —
// rhythmPart.

extension MelodyRhythm {
    // MARK: — Голоса аккорда

    /// Голоса аккорда (ступени) типа offs на ступени r: mode 0 — тесное, 1 — drop 2, 2 — тесное с корнем октавой
    /// ниже (обращение — верх ближе к прежнему, closeVoicing), 3 — широкое: корень в октаве клавиатуры, остальные
    /// выше, не ближе октавы друг к другу, где возможно (не выше 3 октав над корнем); обращение — верх ближе к
    /// прежнему и общий голос с прежним; top — верхний голос квинта или девятая (Ambient).
    static func styleVoicing(_ r: Int, _ offs: [Int], mode: Int, n: Int, prev: [Int]?, top: Bool) -> [Int] {
        if mode < 3 {
            var v: [Int] = closeVoicing(r, offs, n: n, prevTop: prev?.max())
            if mode == 1 && v.count >= 3 { v[v.count - 2] -= n }
            if mode == 2 { v.append(r - n) }
            return v.sorted()
        }
        let up: [Int] = Array(offs.dropFirst())
        var best: [Int] = [r]
        var bestD: Int = Int.max
        for rot in 0..<Swift.max(1, up.count) {
            let order: [Int] = Array(up[rot...] + up[..<rot])
            var v: [Int] = [r]
            for o in order {
                let low: Int = v[v.count - 1]
                var y: Int = r + o
                while y <= low { y += n }
                if y - low < n && y + n <= r + 3 * n { y += n }
                v.append(y)
            }
            var d: Int = 0
            if let p = prev, let pt = p.max() {
                d = Swift.abs((v.last ?? 0) - pt) + (Set(v).isDisjoint(with: p) ? 3 : 0)
            }
            if top, let t = order.last, t != 4 && t != 8 { d += 100 }
            if d < bestD {
                bestD = d
                best = v
            }
        }
        return best
    }

    /// Голоса аккордов всех отрезков типа kind (Scales.chordDegrees), расположение mode — одно на рисунок.
    static func styleVoices(_ c: StyleCtx, kind: Int, mode: Int) -> [[Int]] {
        let offs: [Int] = Scales.chordDegrees[Scales.wrap(kind, Scales.chordDegrees.count)]
        var prev: [Int]? = nil
        var out: [[Int]] = []
        for r in c.segRoot {
            let v: [Int] = styleVoicing(r, offs, mode: mode, n: c.n, prev: prev, top: c.ps == 4)
            out.append(v)
            prev = v
        }
        return out
    }

    // MARK: — BASS

    /// BASS: ячейка стиля (одна на рисунок; Trap — шаги бочки, Ambient — дрон: корень на отрезок, в 30 % на шаге 9
    /// последней страницы — квинта до конца); средние страницы — вариация, последняя — подход к корню первого аккорда
    /// (House, Breaks — шаги 15–16, Pop — 16; Trap — после шага 12 новых нот нет). Первая нота отрезка аккорда (Trap —
    /// шаг 1 страницы) — корень, остальные — корень, октава, квинта, септима вниз по весам стиля.
    static func styleBass(_ c: StyleCtx, using g: inout Rng) -> [StyleNote] {
        let ps: Int = c.ps
        let per: Int = Params.stepsPerPage
        if ps == 4 {
            var out: [StyleNote] = styleHold(c, voices: c.segRoot.map { [$0] }, vel: styleBassVel, using: &g)
            if c.count > 1 && Double.random(in: 0..<1, using: &g) < 0.3 {
                let at: Int = (c.count - 1) * per + 8
                for i in out.indices where out[i].step < at && out[i].step + out[i].len > at {
                    out[i].len = at - out[i].step
                }
                out.append(StyleNote(step: at, degs: [c.root(at) + 4], len: per - 8,
                                     vel: styleVel(styleBassVel, ps, st: 8, first: false, using: &g)))
            }
            return out
        }
        var steps: [Int] = []
        if ps == 2 {
            for pi in 0..<c.count {
                let ks: [Int] = c.kicks[pi].filter { $0 < c.len(pi) && (pi < c.count - 1 || c.count == 1 || $0 < 12) }
                steps += ks.sorted().map { pi * per + $0 }
            }
        } else {
            let t: StyleTable = styleTable(styleBassCells[ps])
            steps = styleCells(t.rows[stylePick(t, using: &g)], c, vary: ps == 0 ? 1 : 2, cut: per, avoid: ps < 2,
                               using: &g)
        }
        let pitch: StyleTable = styleTable(styleBassPitch[ps])
        let offs: [Int] = [0, c.n, 4, -1]
        var out: [StyleNote] = []
        var lastSeg: Int = -1
        var lastPage: Int = -1
        for s in steps {
            let si: Int = c.seg(s)
            let k: Int = c.segRoot[si]
            let st: Int = s % per
            var d: Int = k + offs[pitch.rows[stylePick(pitch, using: &g)].first ?? 0]
            if si != lastSeg || (ps == 2 && st == 0) { d = k }
            if c.count > 1 && s / per == c.count - 1 && ps != 2 && st >= (ps == 3 ? 15 : 14) {
                d = c.segRoot[0] + (Bool.random(using: &g) ? 1 : -1)
            }
            var want: Int = [1, 2, 16, 4][ps]
            if ps == 0 && Double.random(in: 0..<1, using: &g) < 0.25 { want = 2 }
            let first: Bool = s / per != lastPage
            out.append(StyleNote(step: s, degs: [d], len: want,
                                 vel: styleVel(styleBassVel, ps, st: st, first: first, using: &g)))
            lastSeg = si
            lastPage = s / per
        }
        styleFit(&out)
        return out
    }

    // MARK: — LEAD

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

    /// Ход мелодии: ±1, ±2 или скачок на 3–4 ступени по весам moves; после скачка — шаг в обратную сторону; в 0…hi.
    static func styleWalk(_ cur: Int, hi: Int, moves: [Double], last: inout Int, using g: inout Rng) -> Int {
        var m: Int = 1
        if Swift.abs(last) >= 3 {
            m = last > 0 ? -1 : 1
        } else {
            let k: Int = pick([1, 2, 3], moves, using: &g)
            m = k < 3 ? k : Int.random(in: 3...4, using: &g)
            if Bool.random(using: &g) { m = -m }
        }
        if cur + m > hi || cur + m < 0 { m = -m }
        last = m
        return Swift.max(0, Swift.min(hi, cur + m))
    }

    /// Ближайшая к d ступень из pool (номера ступеней в октаве; nil — любая) в 0…hi.
    static func styleSnap(_ d: Int, pool: [Int]?, n: Int, hi: Int) -> Int {
        guard let p = pool else { return d }
        for x in [d, d - 1, d + 1, d - 2, d + 2] where x >= 0 && x <= hi && p.contains(Scales.wrap(x, n)) { return x }
        return d
    }

    /// LEAD: фраза — такт, A, A′, A, B по страницам (Trap — мотив A в каждом такте; Ambient — ходы заново на той же
    /// ячейке, в одной из средних страниц нот может не быть). A — ячейка стиля и ходы от звука аккорда; повтор A — те
    /// же ступени от корня нового аккорда; A′ — у двух последних нот другие высоты; B — другая ячейка, последняя нота —
    /// корень (Trap, Pop, Ambient — последняя нота последней страницы; Pop — от шага 13 до конца). Сильные шаги
    /// (House — 3, 7, 11, 15, Pop — 1, 5, 9, 13) — звуки аккорда; Trap и Ambient — своя пентатоника гаммы.
    static func styleLead(_ c: StyleCtx, using g: inout Rng) -> [StyleNote] {
        let ps: Int = c.ps
        let n: Int = c.n
        let per: Int = Params.stepsPerPage
        let t: StyleTable = styleTable(styleLeadCells[ps])
        let a: Int = stylePick(t, using: &g)
        let b: Int = ps == 2 || ps == 4 ? a : stylePick(t, not: a, using: &g)
        let hi: Int = ps == 1 ? n + n / 2 : (ps == 4 ? 2 * n : n)
        var pool: [Int]? = nil
        if n == 7 && ps == 2 { pool = [0, 2, 3, 4, 6] }
        if n == 7 && ps == 4 { pool = [0, 1, 2, 4, 5] }
        let moves: [Double] = ps == 1 ? [55, 35, 10] : (ps == 3 ? [70, 20, 10] : (ps == 4 ? [50, 50, 0] : [60, 30, 10]))
        let empty: Int = ps == 4 && c.count >= 3 && Bool.random(using: &g) ? Int.random(in: 1...(c.count - 2), using: &g) : -1
        var motifSteps: [Int] = []
        var motif: [Int] = []
        var lastMove: Int = 0
        var cur: Int = Swift.min(hi, c.segRoot[0] + ([0, 2, 4].randomElement(using: &g) ?? 0))
        var out: [StyleNote] = []
        var leadSeg: Int = -1
        for pi in 0..<c.count where pi != empty {
            let form: Int = ps == 2 ? (pi == 0 ? 0 : 2) : (ps == 4 ? 3 : pi % 4)
            let len: Int = c.len(pi)
            let kick: Set<Int> = ps < 2 ? c.kicks[pi] : []
            let lastPage: Bool = pi == c.count - 1
            var steps: [Int] = t.rows[form == 3 ? b : a].filter { $0 < len && !kick.contains($0) }
            if ps == 3 && lastPage && len > 12 { steps = steps.filter { $0 < 12 } + [12] }
            if steps.isEmpty { continue }
            let endRoot: Bool = ps <= 1 ? form == 3 : lastPage
            var made: [Int] = []
            for (j, st) in steps.enumerated() {
                let s: Int = pi * per + st
                let k: Int = c.root(s)
                var d: Int = cur
                if (form == 0 || form == 2), !motif.isEmpty, let mi = motifSteps.firstIndex(of: st) {
                    d = Swift.max(0, Swift.min(hi, k + motif[mi]))
                } else if form == 1, let mi = motifSteps.firstIndex(of: st), j < steps.count - 2 {
                    d = Swift.max(0, Swift.min(hi, k + motif[mi]))
                } else if out.isEmpty || (ps == 4 && c.seg(s) != leadSeg) {
                    d = nearestChordTone(cur, chordRoot: k, n: n, lo: 0, hi: hi, preferRoot: false)
                } else {
                    d = styleSnap(styleWalk(cur, hi: hi, moves: moves, last: &lastMove, using: &g), pool: pool, n: n,
                                  hi: hi)
                }
                if (ps == 0 && isOffbeat(st)) || (ps == 3 && st % 4 == 0) {
                    d = nearestChordTone(d, chordRoot: k, n: n, lo: 0, hi: hi, preferRoot: false)
                }
                if endRoot && j == steps.count - 1 {
                    d = nearestChordTone(d, chordRoot: k, n: n, lo: 0, hi: hi, preferRoot: true)
                }
                var want: Int = [1, 1, 2, 4, 16][ps]
                if ps < 3 && Double.random(in: 0..<1, using: &g) < 0.3 { want = [2, 3, 6][ps] }
                if ps == 3 && j == steps.count - 1 { want = 8 }
                out.append(StyleNote(step: s, degs: [d], len: want,
                                     vel: styleVel(styleLeadVel, ps, st: st, first: j == 0, using: &g)))
                made.append(d - k)
                cur = d
                leadSeg = c.seg(s)
            }
            if form == 0 && motif.isEmpty {
                motif = made
                motifSteps = steps
            }
        }
        styleFit(&out)
        return out
    }

    // MARK: — KEYS, PAD

    /// KEYS: удары аккордом по ячейке стиля (одна на рисунок), средние страницы — вариация, последняя — без ударов
    /// в конце; расположение — одно на рисунок (House, Breaks — тесное или drop 2, Trap — тесное или с корнем ниже,
    /// Pop — тесное, Ambient — открытое). Ambient: аккорд на весь отрезок или «арфа» — звуки аккорда по одному на
    /// шагах 1, 3, 5, 7, каждый до конца страницы.
    static func styleKeys(_ c: StyleCtx, kind: Int, using g: inout Rng) -> [StyleNote] {
        let ps: Int = c.ps
        let per: Int = Params.stepsPerPage
        var mode: Int = ps == 4 ? 3 : 0
        if ps < 3 && Bool.random(using: &g) { mode = ps == 2 ? 2 : 1 }
        let voices: [[Int]] = styleVoices(c, kind: kind, mode: mode)
        let t: StyleTable = styleTable(styleKeysCells[ps])
        let ci: Int = stylePick(t, using: &g)
        if ps == 4 && ci == 0 { return styleHold(c, voices: voices, vel: styleKeysVel, using: &g) }
        var out: [StyleNote] = []
        if ps == 4 && ci == 3 {
            for pi in 0..<c.count {
                for (j, st) in t.rows[ci].enumerated() where st < c.len(pi) {
                    let v: [Int] = voices[c.seg(pi * per + st)]
                    out.append(StyleNote(step: pi * per + st, degs: [v[j % v.count]], len: per - st,
                                         vel: styleVel(styleKeysVel, ps, st: st, first: false, using: &g)))
                }
            }
            return out
        }
        let steps: [Int] = styleCells(t.rows[ci], c, vary: [2, 2, 3, 4, 0][ps], cut: [12, 14, 12, 14, 16][ps],
                                      avoid: ps < 2, using: &g)
        var lastPage: Int = -1
        for s in steps {
            var want: Int = [1, 1, 16, 1, 16][ps]
            let ln: [Int] = t.lens[ci]
            if ps == 3 && ln.count == 2 { want = Bool.random(using: &g) ? ln[0] : ln[1] }
            if (ps == 0 && Double.random(in: 0..<1, using: &g) < 0.2) || (ps == 1 && Bool.random(using: &g)) { want = 2 }
            out.append(StyleNote(step: s, degs: voices[c.seg(s)], len: want,
                                 vel: styleVel(styleKeysVel, ps, st: s % per, first: s / per != lastPage, using: &g)))
            lastPage = s / per
        }
        styleFit(&out)
        return out
    }

    /// PAD: аккорд на весь отрезок (подряд одинаковые — одной нотой до 32 шагов), расположение — одно на рисунок
    /// (House, Pop — тесное, Breaks — тесное или с корнем ниже, Trap и Ambient — широкое); single — одна нота, корень.
    static func stylePad(_ c: StyleCtx, kind: Int, single: Bool, using g: inout Rng) -> [StyleNote] {
        let ps: Int = c.ps
        var mode: Int = ps == 2 || ps == 4 ? 3 : 0
        if ps == 1 && Bool.random(using: &g) { mode = 2 }
        let voices: [[Int]] = single ? c.segRoot.map { [$0] } : styleVoices(c, kind: kind, mode: mode)
        return styleHold(c, voices: voices, vel: stylePadVel, using: &g)
    }

    // MARK: — ARP

    /// Номер в ряду ширины w для j-й ноты фигуры f (0 вверх, 1 через звук, 2 альберти, 3 ломаная вниз, 4 волна).
    static func styleFigure(_ f: Int, _ j: Int, _ w: Int) -> Int {
        if w < 2 { return 0 }
        let skip: Int = (j / 2 + (j % 2 == 1 ? 2 : 0)) % w
        switch f {
        case 1: return skip
        case 2: return [0, 2, 1, 2][j % 4] % w
        case 3: return w - 1 - skip
        case 4:
            let p: Int = j % (2 * w - 2)
            return p < w ? p : 2 * w - 2 - p
        default: return j % w
        }
    }

    /// ARP: звуки аккорда типа kind по DIRECTION и OCTAVES (Arp.sequence), фигура стиля — заново с каждым аккордом;
    /// ритм — все шаги сетки RATE (House, Trap, Pop) или ячейка стиля на шагах сетки (Breaks, Ambient); длина — по
    /// GATE (Ambient — до следующей ноты); последняя страница: в 13–16 нота растёт на ступень с каждым шагом (House,
    /// Breaks, Pop) или звучит каждая вторая (Trap).
    static func styleArp(_ c: StyleCtx, kind: Int, arp a: TrackArp, using g: inout Rng) -> [StyleNote] {
        let ps: Int = c.ps
        let per: Int = Params.stepsPerPage
        let every: Int = Arp.gridSteps[Arp.clampRate(a.rate)]
        let dir: Int = Arp.clampDir(a.dir)
        let offs: [Int] = Scales.chordDegrees[Scales.wrap(kind, Scales.chordDegrees.count)]
        let rows: [[Int]] = c.segRoot.map { r in Arp.sequence(offs.map { r + $0 }, dir: dir, octaves: a.octaves, span: c.n) }
        let fig: Int = stylePickValue(styleArpFigs[ps], using: &g)
        var cell: [Int] = Array(stride(from: 0, to: per, by: every))
        if !styleArpCells[ps].isEmpty {
            let t: StyleTable = styleTable(styleArpCells[ps])
            cell = t.rows[stylePick(t, using: &g)].filter { $0 % every == 0 }
        }
        let gateLen: Int = ps == 4 ? per : Swift.max(1, Int((Arp.clampGate(a.gate) * Double(every)).rounded()))
        var out: [StyleNote] = []
        var j: Int = 0
        var lastSeg: Int = -1
        var fill: Int = 0
        var cur: Int = 0
        for pi in 0..<c.count {
            for (h, st) in cell.enumerated() where st < c.len(pi) {
                let s: Int = pi * per + st
                let si: Int = c.seg(s)
                if si != lastSeg {
                    lastSeg = si
                    j = 0
                }
                let row: [Int] = rows[si]
                if row.isEmpty { continue }
                let end: Bool = c.count > 1 && pi == c.count - 1 && st >= 12
                if end && ps == 2 {
                    fill += 1
                    if fill % 2 == 0 { continue }
                }
                if end && ps != 2 && ps != 4 {
                    cur += 1
                } else {
                    cur = row[dir == Arp.random ? Int.random(in: 0..<row.count, using: &g) : styleFigure(fig, j, row.count)]
                }
                j += 1
                out.append(StyleNote(step: s, degs: [cur], len: gateLen,
                                     vel: styleVel(styleArpVel, ps, st: st, first: h == 0, using: &g)))
            }
        }
        styleFit(&out)
        return out
    }

    // MARK: — Партия

    /// Партия роли role стиля ps на страницы lens по прогрессии degrees (тип аккорда kind — номер Scales.chordKinds):
    /// kicks — шаги бочки страниц (nil — стиля), single — PAD без CHORD (одна нота), arp — настройки ARP дорожки.
    public static func stylePart(_ role: Role, style ps: Int, lens: [Int], degrees: [Int], kind: Int, scale: Int,
                                 root: Int, octave oct: Int, kicks: [Set<Int>]?, single: Bool = false,
                                 arp: TrackArp = TrackArp(), using g: inout Rng) -> [[SliceRhythm.Event]] {
        let c: StyleCtx = styleCtx(Scales.wrap(ps, 5), lens: lens, degrees: degrees, scale: scale, kicks: kicks)
        if c.playing.isEmpty { return lens.map { _ in [] } }
        var notes: [StyleNote] = []
        switch role {
        case .bass: notes = styleBass(c, using: &g)
        case .lead: notes = styleLead(c, using: &g)
        case .keys: notes = styleKeys(c, kind: kind, using: &g)
        case .pad: notes = stylePad(c, kind: kind, single: single, using: &g)
        case .arp: notes = styleArp(c, kind: kind, arp: arp, using: &g)
        }
        return stylePages(notes, c, scale: scale, root: root, octave: oct)
    }
}

extension MelodyRhythm {
    /// Ритм партии роли в стиле проекта (нарезка: роли кусков BASS, LEAD): Techno — генератор Techno, остальные —
    /// stylePart; прогрессия на тонике, бочка стиля.
    static func rhythmPart(_ role: Role, style: Int, bpm: Double, lens: [Int],
                           using g: inout Rng) -> [[SliceRhythm.Event]] {
        let d: [Int] = [1, 1, 1, 1]
        guard let ps = partStyle(style, bpm: bpm) else {
            if role == .bass {
                return technoBass(lens: lens, degrees: d, scale: 0, root: 0, octave: 3, kicks: nil, using: &g)
            }
            if role == .keys {
                return technoKeys(lens: lens, degrees: d, kind: 0, scale: 0, root: 0, octave: 4, kicks: nil, using: &g)
            }
            return hypnoticLead(lens: lens, degrees: d, scale: 0, root: 0, octave: 4, using: &g)
        }
        return stylePart(role, style: ps, lens: lens, degrees: d, kind: 0, scale: 0, root: 0, octave: 3, kicks: nil,
                         using: &g)
    }
}

extension Track {
    /// Случайная партия стиля ps (MelodyRhythm.partStyle) роли role на страницы range: прежние шаги этих страниц
    /// стираются; ARP — по настройкам ARP дорожки (они не меняются).
    public mutating func writeStylePart(_ role: MelodyRhythm.Role, style ps: Int, pages range: ClosedRange<Int>,
                                        degrees: [Int], kind: Int, scale: Int, root: Int, octave: Int,
                                        kicks: [Set<Int>]?, single: Bool = false, using g: inout Rng) {
        let t: Track = self
        let lens: [Int] = range.map { t.pageLen($0, from: range.lowerBound) }
        let pattern: [[SliceRhythm.Event]] = MelodyRhythm.stylePart(role, style: ps, lens: lens, degrees: degrees,
                                                                    kind: kind, scale: scale, root: root, octave: octave,
                                                                    kicks: kicks, single: single, arp: arp, using: &g)
        writeSlices(pattern, pages: range)
    }
}
