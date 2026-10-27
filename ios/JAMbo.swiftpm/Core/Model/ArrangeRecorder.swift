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
    public private(set) var active: Bool = false
    /// Курсор на текущем шаге.
    public private(set) var pos: Int = 0

    public init(tracks: Int = Params.maxTracks) {
        open = [Seg?](repeating: nil, count: tracks)
        muted = [Bool](repeating: false, count: tracks)
    }

    /// Начало записи на позиции at: у каждой дорожки — клип и место в его проходе (slot −1 — тишина; nil — дорожка
    /// на таймлайне, не пишется); audible — слышна ли дорожка (mute / solo).
    public mutating func begin(at: Int, states: [(slot: Int, offset: Int)?], audible: [Bool] = []) {
        active = true
        done = []
        pos = at
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
    public mutating func applyRecording(_ segs: [ArrRecorder.Seg]) {
        for s in segs where tracks.indices.contains(s.track) && s.end > s.start {
            tracks[s.track].clearArrange(from: s.start, to: s.end)
            if s.slot >= 0 && !s.silent && tracks[s.track].clipFilled(s.slot) {
                let pass: Int = tracks[s.track].clipSteps(s.slot)
                tracks[s.track].placeBlock(ArrBlock(clip: s.slot, start: s.start, length: s.end - s.start,
                                                    offset: s.offset % pass))
            }
        }
    }
}
