import Foundation

/// Запись аранжировки с AUTO (S15e): REC + PLAY + AUTO — что играет в сетке, пишется отрезками в позициях курсора.
/// Пишет интерфейс по сообщениям колбэка (arrange — курсор каждого шага, clip — запуск или стоп); на конце записи
/// отрезки ложатся в проект одной правкой (Project.applyRecording). Дорожки, которые идут по таймлайну, не пишутся.
public struct ArrRecorder: Sendable {
    /// Отрезок: дорожка, клип (−1 — тишина), начало и конец (шаги таймлайна), место в проходе клипа на начале.
    public struct Seg: Equatable, Sendable {
        public var track: Int
        public var slot: Int
        public var start: Int
        public var end: Int
        public var offset: Int

        public init(track: Int, slot: Int, start: Int, end: Int, offset: Int) {
            self.track = track
            self.slot = slot
            self.start = start
            self.end = end
            self.offset = offset
        }
    }

    private var open: [Seg?]
    public private(set) var done: [Seg] = []
    public private(set) var active: Bool = false
    /// Курсор на текущем шаге.
    public private(set) var pos: Int = 0

    public init(tracks: Int = Params.maxTracks) {
        open = [Seg?](repeating: nil, count: tracks)
    }

    /// Начало записи на позиции at: у каждой дорожки — клип и место в его проходе (slot −1 — тишина; nil — дорожка
    /// на таймлайне, не пишется).
    public mutating func begin(at: Int, states: [(slot: Int, offset: Int)?]) {
        active = true
        done = []
        pos = at
        for t in open.indices {
            open[t] = nil
            if t < states.count, let s = states[t] {
                open[t] = Seg(track: t, slot: s.slot, start: at, end: at, offset: s.offset)
            }
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
            open[t] = Seg(track: t, slot: s.slot, start: p, end: p, offset: s.offset + (end - s.start))
        }
        pos = p
    }

    /// Дорожка t с текущего шага играет клип slot (−1 — тишина; nil — ушла на таймлайн, дальше не пишется).
    public mutating func clip(track t: Int, slot: Int?) {
        guard active, open.indices.contains(t) else { return }
        close(t, at: pos)
        open[t] = nil
        if let k = slot { open[t] = Seg(track: t, slot: k, start: pos, end: pos, offset: 0) }
    }

    /// Дорожка from встала на место to (как Launcher.move).
    public mutating func move(_ from: Int, _ to: Int) {
        guard open.indices.contains(from), open.indices.contains(to), from != to else { return }
        let x: Seg? = open.remove(at: from)
        open.insert(x, at: to)
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
    /// клип — блоком, тишина — пусто.
    public mutating func applyRecording(_ segs: [ArrRecorder.Seg]) {
        for s in segs where tracks.indices.contains(s.track) && s.end > s.start {
            tracks[s.track].clearArrange(from: s.start, to: s.end)
            if s.slot >= 0 && tracks[s.track].clipFilled(s.slot) {
                let pass: Int = tracks[s.track].clipSteps(s.slot)
                tracks[s.track].placeBlock(ArrBlock(clip: s.slot, start: s.start, length: s.end - s.start,
                                                    offset: s.offset % pass))
            }
        }
    }
}
