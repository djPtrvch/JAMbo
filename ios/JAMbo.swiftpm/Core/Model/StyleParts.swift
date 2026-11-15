import Foundation

// Случайные партии BASS, PAD, LEAD, KEYS, ARP в стилях House, Breaks, Trap, Pop и
// Ambient (docs/ai/sequencer.md, «Случайная партия по стилю»): таблицы — строками по стилям (ради объёма сборки),
// ноты считаются ступенями гаммы от корня клавиатуры. Из p-lock — только Level (velocity). Techno — TechnoRun.swift.
// Роли — StyleRoles.swift.

/// Нота партии стиля: шаг от начала играющих страниц (по 16 на страницу), ступени (у аккорда — несколько), длина,
/// velocity 0…127.
struct StyleNote {
    var step: Int
    var degs: [Int]
    var len: Int
    var vel: Double
}

/// Таблица стиля: ряды (шестнадцатеричные цифры), веса и длины (после «/», KEYS Pop).
struct StyleTable {
    var rows: [[Int]] = []
    var weights: [Double] = []
    var lens: [[Int]] = []
}

/// Общее для партии: стиль, страницы, отрезки аккордов, бочка.
struct StyleCtx {
    let ps: Int
    let lens: [Int]
    let playing: [Int]
    let n: Int
    /// Отрезки аккордов: начало, длина (шаги от начала играющих страниц), ступень-индекс корня (0…n−1).
    let segStart: [Int]
    let segLen: [Int]
    let segRoot: [Int]
    /// Шаги бочки играющих страниц.
    let kicks: [Set<Int>]

    var count: Int { return playing.count }

    /// Длина играющей страницы pi.
    func len(_ pi: Int) -> Int { return lens[playing[pi]] }

    /// Номер отрезка аккорда на шаге s.
    func seg(_ s: Int) -> Int { return segStart.lastIndex { $0 <= s } ?? 0 }

    /// Корень аккорда на шаге s.
    func root(_ s: Int) -> Int { return segRoot[seg(s)] }
}

extension MelodyRhythm {
    /// Стиль партий по ТЗ: 0 House, 1 Breaks, 2 Trap, 3 Pop, 4 Ambient; Techno — nil.
    public static func partStyle(_ style: Int, bpm: Double) -> Int? {
        switch DrumRhythm.groove(style, bpm: bpm) {
        case .house: return 0
        case .breaks: return 1
        case .trap: return 2
        case .pop: return 3
        case .ambient: return 4
        default: return nil
        }
    }

    // MARK: — Таблицы (по стилям House, Breaks, Trap, Pop, Ambient; «ряд:вес», шаги 1…16 — цифры 0…f)

    /// Прогрессии (ступени 1…7).
    static let styleProgs: [String] = ["1767:30 2511:20 1671:20 1475:15 6545:15", "1767:35 1765:25 1677:20 1376:20",
                                       "1637:50 1767:20 1367:15 1675:15", "1564:40 6415:40 1645:20",
                                       "14:30 16:30 15:15 64:15 13:10"]
    /// Типы аккорда (номера Scales.chordKinds) — один на прогрессию.
    static let styleKinds: [String] = ["1:60 2:40", "1:50 0:30 2:20", "0:50 1:30 3:20", "0:50 5:30 3:10 4:10",
                                       "3:40 5:35 2:25"]
    /// Шаги бочки, если на проекте нет дорожки KICK с тригами.
    static let styleKicks: [String] = ["048c", "02a", "0a", "08", ""]
    /// Ячейки BASS (Trap — шаги бочки, Ambient — дрон).
    static let styleBassCells: [String] = [
        "26ae:20 269ae:15 236abe:15 267aef:15 256ade:15 1269ae:10 26abef:10",
        "136be:20 13bf:20 157bd:15 367be:15 16bd:15 37bf:15", "",
        "02468ace:30 0368be:20 0268ae:15 048c:15 0258ad:20", ""]
    /// Ступени баса: 0 корень, 1 октава вверх, 2 квинта, 3 септима вниз.
    static let styleBassPitch: [String] = ["0:60 1:20 2:10 3:10", "0:55 1:15 2:15 3:15", "0:75 1:8 2:8 3:9",
                                           "0:70 1:15 2:15", "0:1"]
    /// Ячейки мотива LEAD.
    static let styleLeadCells: [String] = ["2369ae:1 1367ad:1 256abe:1 369be:1", "1367be:1 3569b:1 169bd:1 379ef:1",
                                           "0368b:1 026a:1 068e:1 038be:1", "0248c:1 02468a:1 0368c:1 2468c:1",
                                           "0:20 08:25 4c:20 06c:20 2a:15"]
    /// Ячейки KEYS (Pop — с длиной «/база, длинная»; Ambient: первая — аккорд на отрезок, последняя — «арфа»).
    static let styleKeysCells: [String] = [
        "26ae:25 25ad:20 36be:20 269e:20 2a:15", "169e:25 36bd:25 159d:15 37bf:15 67b:20", "0:20 08:30 06a:25 038:25",
        "048c:30/22 02468ace:30/11 0368be:25/12 26ae:15/11", "0:30 08:25 06:20 0246:25"]
    /// Ритм ARP (пусто — все шаги сетки RATE).
    static let styleArpCells: [String] = ["", "0368be:40 1369be:30 0257ad:30", "", "", "048c:40 0369c:30 0268c:30"]
    /// Фигуры ARP: 0 вверх, 1 через звук, 2 альберти, 3 ломаная вниз, 4 волна.
    static let styleArpFigs: [String] = ["0:40 1:30 2:30", "1:40 3:30 0:30", "0:50 1:50", "0:50 2:50", "4:60 0:40"]

    /// Velocity по стилям: «сильные lo hi [верх]» — сильные (0 офбиты, 1 доли 1, 5, 9, 13, 2 первая нота страницы,
    /// 3 шаг 1, 4 шаги 3 и 11, 5 нет, 6 шаг 1 и шаг 9 — 90 %) — верх (100 %), остальные lo…hi %.
    static let styleBassVel: String = "0 70 85,2 70 90,3 85 100,1 70 85,5 70 85"
    static let styleLeadVel: String = "2 70 85,2 70 90,2 70 90,1 70 85,5 50 75"
    static let styleKeysVel: String = "4 70 85,2 70 85,3 70 85,1 70 85,5 55 75"
    static let stylePadVel: String = "5 65 80,5 60 75,5 55 70,5 60 75,5 55 70"
    static let styleArpVel: String = "0 60 80,2 60 80,6 55 75,1 60 80,2 40 65 70"

    // MARK: — Разбор таблиц

    /// Таблица из строки «ряд:вес[/длины] …».
    static func styleTable(_ s: String) -> StyleTable {
        var t: StyleTable = StyleTable()
        for item in s.split(separator: " ") {
            let parts: [Substring] = item.split(separator: "/")
            let a: [Substring] = parts[0].split(separator: ":")
            t.rows.append(a[0].map { Int(String($0), radix: 16) ?? 0 })
            t.weights.append(a.count > 1 ? Double(String(a[1])) ?? 1 : 1)
            t.lens.append(parts.count > 1 ? parts[1].map { Int(String($0)) ?? 1 } : [])
        }
        return t
    }

    /// Номер ряда таблицы по весу; not — кроме этого (если есть другие).
    static func stylePick(_ t: StyleTable, not: Int = -1, using g: inout Rng) -> Int {
        if t.rows.isEmpty { return 0 }
        var w: [Double] = t.weights
        if not >= 0 && not < w.count && w.count > 1 { w[not] = 0 }
        return pick(Array(t.rows.indices), w, using: &g)
    }

    /// Первое число ряда таблицы s, выбранного по весу.
    static func stylePickValue(_ s: String, using g: inout Rng) -> Int {
        let t: StyleTable = styleTable(s)
        return t.rows.isEmpty ? 0 : t.rows[stylePick(t, using: &g)].first ?? 0
    }

    /// Шаги бочки стиля ps без дорожки KICK.
    public static func styleKick(_ ps: Int) -> Set<Int> {
        return Set(styleKicks[Scales.wrap(ps, styleKicks.count)].map { Int(String($0), radix: 16) ?? 0 })
    }

    /// Velocity ноты на шаге st страницы (first — первая нота страницы) по правилу стиля ps из таблицы s.
    static func styleVel(_ s: String, _ ps: Int, st: Int, first: Bool, using g: inout Rng) -> Double {
        let rules: [Substring] = s.split(separator: ",")
        let r: [Int] = rules[Scales.wrap(ps, rules.count)].split(separator: " ").map { Int(String($0)) ?? 0 }
        var strong: Bool = false
        switch r[0] {
        case 0: strong = isOffbeat(st)
        case 1: strong = st % 4 == 0
        case 2: strong = first
        case 3, 6: strong = st == 0
        case 4: strong = st == 2 || st == 10
        default: strong = false
        }
        if r[0] == 6 && st == 8 { return 114 }
        if strong { return (Double(r.count > 3 ? r[3] : 100) * 1.27).rounded() }
        return (Double(Int.random(in: r[1]...r[2], using: &g)) * 1.27).rounded()
    }

    // MARK: — Гармония

    /// Прогрессия стиля ps: 75 % — из набора (по весу), 25 % — свободная (ступени 1…7 без повторов подряд, тоника
    /// первой; Ambient — две разные ступени); не равна avoid (до 16 попыток).
    public static func styleProgression(_ ps: Int, scale: Int, avoid: [Int]?, using g: inout Rng) -> [Int] {
        let t: StyleTable = styleTable(styleProgs[Scales.wrap(ps, styleProgs.count)])
        var out: [Int] = [1]
        for _ in 0..<16 {
            if Double.random(in: 0..<1, using: &g) < 0.75 {
                out = t.rows[stylePick(t, using: &g)]
            } else {
                let free: [Int] = Chords.random(scale: scale, using: &g)
                out = ps == 4 ? Array(free.prefix(2)) : free
            }
            if out != avoid { break }
        }
        return out
    }

    /// Тип аккорда стиля ps (номер Scales.chordKinds) — один на прогрессию.
    public static func styleKind(_ ps: Int, using g: inout Rng) -> Int {
        return stylePickValue(styleKinds[Scales.wrap(ps, styleKinds.count)], using: &g)
    }

    /// Общее для партии на страницы lens: отрезки аккордов — аккорд на страницу (первые ступени прогрессии), одна
    /// страница — два по 8 шагов (Trap, Ambient — один); Ambient — два аккорда, смена на границе страниц посередине
    /// (на 3 страницах — после 2-й). Бочка — kicks (по страницам lens), нет — шаги стиля.
    static func styleCtx(_ ps: Int, lens: [Int], degrees: [Int], scale: Int, kicks: [Set<Int>]?) -> StyleCtx {
        let playing: [Int] = lens.indices.filter { lens[$0] > 0 }
        let n: Int = Scales.all[Scales.wrap(scale, Scales.all.count)].steps.count
        let per: Int = Params.stepsPerPage
        let d: [Int] = degrees.isEmpty ? [1] : degrees
        let count: Int = Swift.max(1, playing.count)
        var starts: [Int] = []
        var degs: [Int] = []
        if count == 1 && ps != 2 && ps != 4 {
            starts = [0, per / 2]
            degs = [d[0], d[1 % d.count]]
        } else if ps == 4 {
            starts = [0]
            degs = [d[0]]
            if count > 1 && d.count > 1 {
                starts.append((count + 1) / 2 * per)
                degs.append(d[1])
            }
        } else {
            starts = (0..<count).map { $0 * per }
            degs = (0..<count).map { d[$0 % d.count] }
        }
        let total: Int = count * per
        let segLen: [Int] = starts.indices.map { i in (i + 1 < starts.count ? starts[i + 1] : total) - starts[i] }
        let def: Set<Int> = styleKick(ps)
        let ks: [Set<Int>] = playing.map { p in
            guard let k = kicks, p < k.count else { return def }
            return k[p]
        }
        return StyleCtx(ps: ps, lens: lens, playing: playing, n: n, segStart: starts, segLen: segLen,
                        segRoot: degs.map { Chords.degreeIndex($0, scale: scale) }, kicks: ks)
    }

    // MARK: — Ритм, длины, ноты

    /// Шаги ячейки cell на всех страницах (от начала играющих): средние страницы — вариация vary (1 — шестнадцатая не
    /// на офбите добавлена или убрана; 2 — нота, не первая, сдвинута на ±1 или убрана; 3 — вторая сдвинута на ±1;
    /// 4 — нота, не первая, убрана); последняя (из нескольких) — без нот с шага cut (0…15). avoid — мимо бочки.
    static func styleCells(_ cell: [Int], _ c: StyleCtx, vary: Int, cut: Int, avoid: Bool,
                           using g: inout Rng) -> [Int] {
        var out: [Int] = []
        for pi in 0..<c.count {
            let len: Int = c.len(pi)
            let kick: Set<Int> = avoid ? c.kicks[pi] : []
            var st: [Int] = cell.filter { $0 < len && !kick.contains($0) }
            if pi > 0 && pi < c.count - 1 && vary > 0 && !st.isEmpty {
                let free: [Int] = (0..<len).filter { !st.contains($0) && !kick.contains($0) }
                if vary == 1 {
                    let rem: [Int] = st.filter { !isOffbeat($0) }
                    let add: [Int] = free.filter { !isOffbeat($0) }
                    if let x = rem.randomElement(using: &g), add.isEmpty || Bool.random(using: &g) {
                        st.removeAll { $0 == x }
                    } else if let x = add.randomElement(using: &g) {
                        st.append(x)
                    }
                } else if vary == 4 {
                    if st.count > 1 { st.remove(at: Int.random(in: 1..<st.count, using: &g)) }
                } else if st.count > 1 {
                    let i: Int = vary == 3 ? 1 : Int.random(in: 1..<st.count, using: &g)
                    let to: Int = st[i] + (Bool.random(using: &g) ? 1 : -1)
                    if vary == 3 {
                        if free.contains(to) { st[i] = to }
                    } else if free.contains(to) && Bool.random(using: &g) {
                        st[i] = to
                    } else {
                        st.remove(at: i)
                    }
                }
            }
            if pi == c.count - 1 && c.count > 1 { st = st.filter { $0 < cut } }
            out += st.sorted().map { pi * Params.stepsPerPage + $0 }
        }
        return out
    }

    /// Длины нот: не дальше следующей ноты и конца страницы.
    static func styleFit(_ notes: inout [StyleNote]) {
        notes.sort { $0.step < $1.step }
        let per: Int = Params.stepsPerPage
        for i in notes.indices {
            let s: Int = notes[i].step
            let next: Int = i + 1 < notes.count ? notes[i + 1].step : Int.max
            notes[i].len = Swift.max(1, Swift.min(notes[i].len, next - s, per - s % per))
        }
    }

    /// Аккорды отрезков целиком (подряд одинаковые — одним): удар с началом, нота — до 32 шагов, дальше заново.
    static func styleHold(_ c: StyleCtx, voices: [[Int]], vel: String, using g: inout Rng) -> [StyleNote] {
        var out: [StyleNote] = []
        var i: Int = 0
        while i < c.segRoot.count {
            var j: Int = i
            while j + 1 < c.segRoot.count && c.segRoot[j + 1] == c.segRoot[i] { j += 1 }
            var s: Int = c.segStart[i]
            let e: Int = c.segStart[j] + c.segLen[j]
            while s < e {
                out.append(StyleNote(step: s, degs: voices[i], len: Swift.min(32, e - s),
                                     vel: styleVel(vel, c.ps, st: s % Params.stepsPerPage, first: false, using: &g)))
                s += 32
            }
            i = j + 1
        }
        return out
    }

    /// Ноты по страницам lens: ступени — ноты гаммы (technoNote); длина — не дальше конца играющих страниц, на
    /// короткой странице — не за её конец, не больше 32 шагов.
    static func stylePages(_ notes: [StyleNote], _ c: StyleCtx, scale: Int, root: Int,
                           octave oct: Int) -> [[SliceRhythm.Event]] {
        var out: [[SliceRhythm.Event]] = c.lens.map { _ in [] }
        guard let last = c.playing.last else { return out }
        let per: Int = Params.stepsPerPage
        let end: Int = (c.count - 1) * per + c.lens[last]
        for x in notes where x.step >= 0 && x.step / per < c.count {
            let p: Int = c.playing[x.step / per]
            let st: Int = x.step % per
            if st >= c.lens[p] { continue }
            let room: Int = c.lens[p] == per ? end - x.step : c.lens[p] - st
            let len: Int = Swift.max(1, Swift.min(x.len, room, 32))
            for d in x.degs {
                out[p].append(SliceRhythm.Event(step: st, note: technoNote(d, scale: scale, root: root, octave: oct),
                                                len: len, vel: x.vel))
            }
        }
        return out
    }
}
