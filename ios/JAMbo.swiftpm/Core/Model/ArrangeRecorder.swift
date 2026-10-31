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
    public private(set) var active: Bool = false
    /// Курсор на текущем шаге.
    public private(set) var pos: Int = 0

    public init(tracks: Int = Params.maxTracks) {
        open = [Seg?](repeating: nil, count: tracks)
        muted = [Bool](repeating: false, count: tracks)
        played = [[Int: Int]](repeating: [:], count: tracks)
        fired = [Set<Int>](repeating: [], count: tracks)
    }

    /// Шаг pos клипа дорожки t начал звучать на текущем шаге таймлайна (дорожка пишется).
    public mutating func notePlayed(track t: Int, pos p: Int) {
        guard active, p >= 0, open.indices.contains(t), open[t] != nil else { return }
        played[t][pos] = p
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
        }
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
        for t in open.indices { open[t]?.track = t }
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
    /// которые звучали на каждом шаге таймлайна (переключение страниц — как играли); шаг, не прошедший Chance, — без
    /// трига, прошедший — с Chance 100 %. Блок — не длиннее 8 страниц (128 шагов), длиннее — несколько блоков подряд.
    /// Клип с другой скоростью (×2, 1/2…) и запись без этих данных — блок со ссылкой на клип, как прежде.
    public mutating func applyRecording(_ segs: [ArrRecorder.Seg], played: [[Int: Int]] = [], fired: [Set<Int>] = []) {
        for s in segs where tracks.indices.contains(s.track) && s.end > s.start {
            tracks[s.track].clearArrange(from: s.start, to: s.end)
            guard s.slot >= 0 && !s.silent && tracks[s.track].clipFilled(s.slot), let src = tracks[s.track].clips[s.slot] else {
                continue
            }
            let t: Int = s.track
            if src.speed == 0 && t < played.count && t < fired.count {
                placeFired(t, s, src, played[t], fired[t])
                continue
            }
            let pass: Int = tracks[t].clipSteps(s.slot)
            tracks[t].placeBlock(ArrBlock(clip: s.slot, start: s.start, length: s.end - s.start, offset: s.offset % pass))
        }
    }

    /// Отрезок s дорожки t — блоками со своей копией из прозвучавших шагов клипа src.
    private mutating func placeFired(_ t: Int, _ s: ArrRecorder.Seg, _ src: Clip, _ played: [Int: Int], _ fired: Set<Int>) {
        let maxLen: Int = Params.maxPages * Params.stepsPerPage
        let n16: Int = Params.stepsPerPage
        let trackProb: Double = tracks[t].params["prob"] ?? Params.byId["prob"]?.def ?? 100
        var x: Int = s.start
        while x < s.end {
            let n: Int = Swift.min(maxLen, s.end - x)
            let pages: Int = (n + n16 - 1) / n16
            var c = Clip(pages: [[Step]](repeating: Track.emptyPage(), count: pages), length: n, playFrom: 0,
                         playTo: pages - 1, scale: src.scale, root: src.root, fx: src.fx)
            var i: Int = 0
            while i < n {
                let at: Int = x + i
                if let p = played[at], var st = src.step(p) {
                    if st.on {
                        if fired.contains(at) {
                            // Прозвучал — дальше звучит всегда.
                            if st.locks["prob"] != nil || trackProb < 100 { st.locks["prob"] = 100 }
                        } else {
                            st.on = false
                        }
                    }
                    c.pages[i / n16][i % n16] = st
                }
                i += 1
            }
            tracks[t].placeBlock(ArrBlock(clip: s.slot, start: x, length: n, pattern: c))
            x += n
        }
    }
}
