import Foundation

/// Журнал запусков клипов в сетке паттернов (S15e, SEND TO ARRANGE): что играла каждая дорожка за последние 32 такта.
/// Пишет интерфейс по сообщениям clip колбэка; тики — шаги транспорта от PLAY.
public struct ArrJournal: Sendable {
    /// Окно журнала — 32 такта.
    public static let window: Int = 32 * ArrGrid.stepsPerBar

    /// С тика start дорожка играет клип slot (−1 — тишина: стоп или таймлайн).
    public struct Entry: Equatable, Sendable {
        public var slot: Int
        public var start: Int

        public init(slot: Int, start: Int) {
            self.slot = slot
            self.start = start
        }
    }

    public private(set) var entries: [[Entry]]

    public init(tracks: Int = Params.maxTracks) {
        entries = [[Entry]](repeating: [], count: tracks)
    }

    /// Ни одна дорожка ничего не играла.
    public var isEmpty: Bool {
        for list in entries where list.contains(where: { $0.slot >= 0 }) { return false }
        return true
    }

    /// Новый PLAY: журнал заново.
    public mutating func reset() {
        for t in entries.indices { entries[t] = [] }
    }

    /// Дорожка t с тика start играет клип slot (−1 — тишина). Старше окна — только последнее событие до него.
    public mutating func record(track t: Int, slot: Int, start: Int) {
        guard entries.indices.contains(t) else { return }
        var list: [Entry] = entries[t]
        list.removeAll { $0.start >= start }
        list.append(Entry(slot: slot, start: start))
        let from: Int = start - ArrJournal.window
        if let k = list.lastIndex(where: { $0.start <= from }), k > 0 { list.removeFirst(k) }
        entries[t] = list
    }

    /// Дорожка from встала на место to (как Launcher.move).
    public mutating func move(_ from: Int, _ to: Int) {
        guard entries.indices.contains(from), entries.indices.contains(to), from != to else { return }
        let x: [Entry] = entries.remove(at: from)
        entries.insert(x, at: to)
    }

    /// Блоки за окно до тика now (конец — по концу его такта; начало — не раньше такта первой записи): по дорожке,
    /// начала от начала окна, offset — место в проходе клипа от его запуска; длина окна.
    public func take(now: Int) -> (blocks: [[ArrBlock]], length: Int) {
        let bar: Int = ArrGrid.stepsPerBar
        let w1: Int = (Swift.max(0, now) / bar + 1) * bar
        var first: Int = w1
        for list in entries { if let e = list.first { first = Swift.min(first, e.start) } }
        let w0: Int = Swift.max(w1 - ArrJournal.window, Swift.max(0, first) / bar * bar)
        var out: [[ArrBlock]] = [[ArrBlock]](repeating: [], count: entries.count)
        for t in entries.indices {
            let list: [Entry] = entries[t]
            for (i, e) in list.enumerated() where e.slot >= 0 {
                let next: Int = i + 1 < list.count ? list[i + 1].start : w1
                let s: Int = Swift.max(e.start, w0)
                let end: Int = Swift.min(next, w1)
                if end <= s { continue }
                out[t].append(ArrBlock(clip: e.slot, start: s - w0, length: end - s, offset: s - e.start))
            }
        }
        return (out, w1 - w0)
    }
}

extension Project {
    /// SEND TO ARRANGE (S15e): блоки журнала — в аранжировку с позиции at (nil — в конец аранжировки); участок
    /// этих дорожек заменяется. Конец участка; nil — журнал пуст.
    @discardableResult
    public mutating func sendToArrange(_ blocks: [[ArrBlock]], length: Int, at: Int?) -> Int? {
        var any: Bool = false
        for list in blocks where !list.isEmpty { any = true }
        if !any || length <= 0 { return nil }
        let start: Int = Swift.max(0, at ?? arrangeEnd)
        let end: Int = start + length
        for t in tracks.indices where t < blocks.count && !blocks[t].isEmpty {
            tracks[t].clearArrange(from: start, to: end)
            for b in blocks[t] where tracks[t].clipFilled(b.clip) {
                let pass: Int = tracks[t].clipSteps(b.clip)
                tracks[t].placeBlock(ArrBlock(clip: b.clip, start: start + b.start, length: b.length, offset: b.offset % pass))
            }
        }
        return end
    }
}
