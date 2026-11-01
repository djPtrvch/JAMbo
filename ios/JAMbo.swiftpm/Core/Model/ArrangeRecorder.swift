import Foundation

/// Запись аранжировки из сетки (S15e): что играет и слышно в сетке, пишется отрезками в позициях курсора.
/// Пишет интерфейс по сообщениям колбэка (arrange — курсор каждого шага, clip — запуск или стоп) и по mute / solo
/// (audible); на конце записи отрезки ложатся в проект одной правкой (Project.applyRecording). Дорожки, которые идут
/// по таймлайну, не пишутся.
public struct ArrRecorder: Sendable {
    /// Отрезок: дорожка, клип (−1 — тишина), начало и конец (шаги таймлайна), место в проходе клипа на начале;
    /// silent — клип играл заглушённым (mute / solo): на таймлайне пусто.
    public struct Seg: Equatable, Sendable {
        public var track: Int
        public var slot: Int
        public var start: Int
        public var end: Int
        public var offset: Int
        public var silent: Bool

        public init(track: Int, slot: Int, start: Int, end: Int, offset: Int, silent: Bool = false) {
            self.track = track
            self.slot = slot
            self.start = start
            self.end = end
            self.offset = offset
            self.silent = silent
        }
    }

    private var open: [Seg?]
    /// Заглушена ли дорожка (mute / solo) сейчас.
    private var muted: [Bool]
    public private(set) var done: [Seg] = []
    /// Запись «по факту» (решение пользователя): на каждом шаге таймлайна — какой шаг клипа звучал (позиция p·16 + s)
    /// и прошёл ли он Chance; по дорожкам. Держатся до следующей записи (applyRecording берёт их после finish).
    public private(set) var played: [[Int: Int]]
    public private(set) var fired: [Set<Int>]
    /// Шаг клипа, каким он был, когда прозвучал (решение пользователя 2.11: правка шагов во время записи действует
    /// с места, где её сделали; прежние проходы — как сыграли): шаг таймлайна → шаг.
    public private(set) var heard: [[Int: Step]]
    /// Ноты, сыгранные вживую во время записи (клавиши, MIDI; решение пользователя 2.11 — пишутся всегда).
    public private(set) var live: [LiveNote] = []

    /// Живая нота: дорожка, шаг таймлайна, ноты, сила (0…1; nil — без своей), длина в шагах.
    public struct LiveNote: Equatable, Sendable {
        public var track: Int
        public var at: Int
        public var notes: [Int]
        public var velocity: Double?
        public var len: Int

        public init(track: Int, at: Int, notes: [Int], velocity: Double?, len: Int = 1) {
            self.track = track
            self.at = at
            self.notes = notes
            self.velocity = velocity
            self.len = len
        }
    }
    public private(set) var active: Bool = false
    /// Курсор на текущем шаге.
    public private(set) var pos: Int = 0

    public init(tracks: Int = Params.maxTracks) {
        open = [Seg?](repeating: nil, count: tracks)
        muted = [Bool](repeating: false, count: tracks)
        played = [[Int: Int]](repeating: [:], count: tracks)
        fired = [Set<Int>](repeating: [], count: tracks)
        heard = [[Int: Step]](repeating: [:], count: tracks)
    }

    /// Отрезки записи сейчас (законченные и идущие — до конца текущего шага): показ записи на таймлайне.
    public var current: [Seg] {
        guard active else { return [] }
        var out: [Seg] = done
        for s in open {
            guard var x = s else { continue }
            x.end = Swift.max(x.start, pos + 1)
            if x.end > x.start { out.append(x) }
        }
        return out
    }

    /// Клип, который сейчас пишется у дорожки t (−1 — тишина; nil — дорожка не пишется).
    public func openSlot(_ t: Int) -> Int? {
        guard active, open.indices.contains(t) else { return nil }
        return open[t]?.slot
    }

    /// Шаг pos клипа дорожки t начал звучать на текущем шаге таймлайна (дорожка пишется); step — каким он был.
    public mutating func notePlayed(track t: Int, pos p: Int, step: Step? = nil) {
        guard active, p >= 0, open.indices.contains(t), open[t] != nil else { return }
        played[t][pos] = p
        if let s = step { heard[t][pos] = s }
    }

    /// Нажали клавишу на дорожке t: ноты на шаге таймлайна at. Номер ноты (для длины) или nil — дорожка не пишется.
    public mutating func liveNote(track t: Int, at x: Int, notes: [Int], velocity: Double?) -> Int? {
        guard active, !notes.isEmpty, open.indices.contains(t), let s = open[t], !s.silent else { return nil }
        live.append(LiveNote(track: t, at: Swift.max(s.start, x), notes: notes, velocity: velocity))
        return live.count - 1
    }

    /// Отпустили клавишу: длина живой ноты i в шагах (не меньше 1).
    public mutating func liveLength(_ i: Int, _ len: Int) {
        if live.indices.contains(i) { live[i].len = Swift.max(1, len) }
    }

    /// Шаг дорожки t прошёл Chance на текущем шаге таймлайна.
    public mutating func noteFired(track t: Int) {
        guard active, open.indices.contains(t), open[t] != nil else { return }
        fired[t].insert(pos)
    }

    /// Начало записи на позиции at: у каждой дорожки — клип и место в его проходе (slot −1 — тишина; nil — дорожка
    /// на таймлайне, не пишется); audible — слышна ли дорожка (mute / solo).
    public mutating func begin(at: Int, states: [(slot: Int, offset: Int)?], audible: [Bool] = []) {
        active = true
        done = []
        pos = at
        for t in played.indices {
            played[t] = [:]
            fired[t] = []
            heard[t] = [:]
        }
        live = []
        for t in open.indices {
            open[t] = nil
            muted[t] = t < audible.count && !audible[t]
            if t < states.count, let s = states[t] {
                open[t] = Seg(track: t, slot: s.slot, start: at, end: at, offset: s.offset, silent: muted[t])
            }
        }
    }

    /// Mute / solo: дорожки, у которых слышимость сменилась, закрывают отрезок на шаге at (текущий или следующий)
    /// и продолжают тот же клип с того же места прохода — заглушённым (на таймлайне пусто) или слышным.
    public mutating func audible(_ flags: [Bool], at: Int) {
        guard active else { return }
        let x: Int = min(pos + 1, max(pos, at))
        for t in open.indices where t < flags.count && muted[t] == flags[t] {
            muted[t] = !flags[t]
            guard let s = open[t] else { continue }
            let off: Int = s.offset + max(0, x - s.start)
            close(t, at: x)
            open[t] = Seg(track: t, slot: s.slot, start: x, end: x, offset: off, silent: muted[t])
        }
    }

    /// Курсор на шаге p: следующий шаг — дальше; скачок (петля, переход курсора) — отрезки закрываются на конце шага
    /// и продолжаются с p с того же места прохода.
    public mutating func step(_ p: Int) {
        if !active || p == pos || p == pos + 1 {
            pos = p
            return
        }
        let end: Int = pos + 1
        for t in open.indices {
            guard let s = open[t] else { continue }
            close(t, at: end)
            open[t] = Seg(track: t, slot: s.slot, start: p, end: p, offset: s.offset + (end - s.start), silent: s.silent)
        }
        pos = p
    }

    /// Дорожка t с текущего шага играет клип slot (−1 — тишина; nil — ушла на таймлайн, дальше не пишется).
    public mutating func clip(track t: Int, slot: Int?) {
        guard active, open.indices.contains(t) else { return }
        close(t, at: pos)
        open[t] = nil
        if let k = slot { open[t] = Seg(track: t, slot: k, start: pos, end: pos, offset: 0, silent: muted[t]) }
    }

    /// Дорожка from встала на место to (как Launcher.move).
    public mutating func move(_ from: Int, _ to: Int) {
        guard open.indices.contains(from), open.indices.contains(to), from != to else { return }
        let x: Seg? = open.remove(at: from)
        open.insert(x, at: to)
        let m: Bool = muted.remove(at: from)
        muted.insert(m, at: to)
        let pl = played.remove(at: from)
        played.insert(pl, at: to)
        let fi = fired.remove(at: from)
        fired.insert(fi, at: to)
        let he = heard.remove(at: from)
        heard.insert(he, at: to)
        for t in open.indices { open[t]?.track = t }
        for i in live.indices {
            let t: Int = live[i].track
            if t == from {
                live[i].track = to
            } else if from < to && t > from && t <= to {
                live[i].track = t - 1
            } else if from > to && t >= to && t < from {
                live[i].track = t + 1
            }
        }
        for i in done.indices {
            let t: Int = done[i].track
            if t == from {
                done[i].track = to
            } else if from < to && t > from && t <= to {
                done[i].track = t - 1
            } else if from > to && t >= to && t < from {
                done[i].track = t + 1
            }
        }
    }

    /// Конец записи — на конце текущего шага. Все отрезки по порядку записи.
    public mutating func finish() -> [Seg] {
        if !active { return [] }
        for t in open.indices { close(t, at: pos + 1) }
        for t in open.indices { open[t] = nil }
        active = false
        let out: [Seg] = done
        done = []
        return out
    }

    private mutating func close(_ t: Int, at end: Int) {
        guard var s = open[t] else { return }
        s.end = end
        if s.end > s.start { done.append(s) }
        open[t] = nil
    }
}

extension Project {
    /// Записанные отрезки — в аранжировку (по порядку записи: поздний заменяет ранний): участок отрезка заменяется,
    /// клип — блоком, тишина и заглушённый клип — пусто.
    /// played и fired (ArrRecorder) — запись «по факту» (решение пользователя): блок получает свою копию из шагов,
    /// которые звучали на каждом шаге таймлайна (переключение страниц — как играли); шаг, не прошедший Chance, — пустой
    /// (без трига и p-lock), прошедший — с Chance 100 %. Блоки — по проходу клипа, не длиннее 8 тактов (128 шагов).
    /// Клип с другой скоростью (×2, 1/2…) и запись без этих данных — блок со ссылкой на клип, как прежде.
    /// heard — шаги, какими они были, когда звучали (правка во время записи — с места правки); live — ноты, сыгранные
    /// вживую (ложатся в блок на свой шаг; в тишине — блоками по такту).
    public mutating func applyRecording(_ segs: [ArrRecorder.Seg], played: [[Int: Int]] = [], fired: [Set<Int>] = [],
                                        heard: [[Int: Step]] = [], live: [ArrRecorder.LiveNote] = []) {
        for s in segs where tracks.indices.contains(s.track) && s.end > s.start {
            tracks[s.track].clearArrange(from: s.start, to: s.end)
            let t: Int = s.track
            let notes: [ArrRecorder.LiveNote] = live.filter { $0.track == t && $0.at >= s.start && $0.at < s.end }
            guard s.slot >= 0 && !s.silent && tracks[s.track].clipFilled(s.slot), let src = tracks[s.track].clips[s.slot] else {
                if !s.silent && !notes.isEmpty { placeLive(t, s, notes) }
                continue
            }
            if src.speed == 0 && t < played.count && t < fired.count {
                placeFired(t, s, src, played[t], fired[t], t < heard.count ? heard[t] : [:], notes)
                continue
            }
            let pass: Int = tracks[t].clipSteps(s.slot)
            tracks[t].placeClip(ArrBlock(clip: s.slot, start: s.start, length: s.end - s.start, offset: s.offset % pass))
        }
    }

    /// Отрезок s дорожки t — блоками со своей копией из прозвучавших шагов клипа src.
    private mutating func placeFired(_ t: Int, _ s: ArrRecorder.Seg, _ src: Clip, _ played: [Int: Int], _ fired: Set<Int>,
                                     _ heard: [Int: Step], _ live: [ArrRecorder.LiveNote]) {
        let maxLen: Int = Swift.min(Params.maxPages * Params.stepsPerPage, Track.maxClipBlock)
        // Блоки — по проходу клипа (клип в такт — по такту, в два — по два), не длиннее 8 тактов (решение пользователя).
        let pass: Int = Swift.max(1, tracks[t].clipSteps(s.slot))
        let chunk: Int = Swift.min(pass, maxLen)
        let n16: Int = Params.stepsPerPage
        let trackProb: Double = tracks[t].params["prob"] ?? Params.byId["prob"]?.def ?? 100
        var x: Int = s.start
        while x < s.end {
            let ph: Int = (s.offset + x - s.start) % pass
            let n: Int = Swift.min(s.end - x, chunk - ph % chunk, pass - ph)
            let pages: Int = (n + n16 - 1) / n16
            var c = Clip(pages: [[Step]](repeating: Track.emptyPage(), count: pages), length: n, playFrom: 0,
                         playTo: pages - 1, scale: src.scale, root: src.root, fx: src.fx)
            var i: Int = 0
            var any: Bool = false
            while i < n {
                let at: Int = x + i
                if let p = played[at], var st = heard[at] ?? src.step(p) {
                    if st.on {
                        if fired.contains(at) {
                            // Прозвучал — дальше звучит всегда.
                            if st.locks["prob"] != nil || trackProb < 100 { st.locks["prob"] = 100 }
                        } else {
                            // Не прозвучал — пустой шаг: без p-lock, нот и своего звука (решение пользователя 2.11).
                            st = Step()
                        }
                    }
                    if st.on { any = true }
                    c.pages[i / n16][i % n16] = st
                }
                i += 1
            }
            if Project.addLive(&c, live, from: x, count: n, level: tracks[t].params["level"] ?? 127) { any = true }
            // Блок без прозвучавших тригов (заглушённая дорожка, Chance не прошёл) — не пишется (решение пользователя).
            if any { tracks[t].placeBlock(ArrBlock(clip: s.slot, start: x, length: n, pattern: c)) }
            x += n
        }
    }

    /// Живые ноты в тишине (клип не играл): блоки по такту — только такты с нотами; клип блока — выбранный у дорожки.
    private mutating func placeLive(_ t: Int, _ s: ArrRecorder.Seg, _ live: [ArrRecorder.LiveNote]) {
        let bar: Int = ArrGrid.stepsPerBar
        let n16: Int = Params.stepsPerPage
        var x: Int = s.start
        while x < s.end {
            let n: Int = Swift.min(s.end - x, bar - ((x % bar) + bar) % bar)
            let pages: Int = (n + n16 - 1) / n16
            var c = Clip(pages: [[Step]](repeating: Track.emptyPage(), count: pages), length: n, playFrom: 0, playTo: pages - 1)
            if Project.addLive(&c, live, from: x, count: n, level: tracks[t].params["level"] ?? 127) {
                let k: Int = Swift.max(0, Swift.min(Params.patternSlots - 1, tracks[t].slot))
                tracks[t].placeBlock(ArrBlock(clip: k, start: x, length: n, pattern: c))
            }
            x += n
        }
    }

    /// Живые ноты с шагов [from, from + count) — в копию клипа c (к нотам шага; длина — не дальше конца копии; сила —
    /// Level ноты = Level дорожки × сила, как запись с REC). true — что-то легло.
    static func addLive(_ c: inout Clip, _ live: [ArrRecorder.LiveNote], from: Int, count: Int, level: Double) -> Bool {
        var any: Bool = false
        let n16: Int = Params.stepsPerPage
        for ln in live where ln.at >= from && ln.at < from + count {
            let i: Int = ln.at - from
            var st: Step = c.pages[i / n16][i % n16]
            let had: Bool = st.on
            if !had {
                st.lens = nil
                st.vels = nil
            }
            st.setNotes(had ? Array(Set(st.notes + ln.notes)).sorted() : ln.notes)
            st.on = true
            st.setAllLen(Swift.max(had ? st.len : 1, Swift.min(ln.len, count - i)))
            if let v = ln.velocity {
                let lv: Double = (level * v).rounded()
                for note in ln.notes {
                    guard let k = st.notes.firstIndex(of: note) else { continue }
                    st.setVelLinked(k, Swift.max(st.noteVel(k) ?? 0, lv), fallback: level)
                }
            }
            c.pages[i / n16][i % n16] = st
            any = true
        }
        return any
    }
}
