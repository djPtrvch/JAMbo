import Foundation

// Клипы и строки сетки паттернов (как slots, putEmptyClip, fillRows, строки в state.ts веба).
// Запуск и остановка клипов — игра (секвенсор в колбэке), здесь — только правки.

extension Track {
    public func clipFilled(_ k: Int) -> Bool {
        return k >= 0 && k < clips.count && clips[k] != nil
    }

    /// Сделать ячейку k активной: её диапазон страниц встаёт в playFrom…playTo (пустая — активная пустая).
    public mutating func activate(_ k: Int) {
        slot = k
        guard let c = clips[k] else { return }
        let last = pages.count - 1
        let to = Swift.max(0, Swift.min(c.playTo, last))
        playTo = to
        playFrom = Swift.max(0, Swift.min(c.playFrom, to))
    }

    /// Диапазон страниц клипа k в пределах страниц дорожки.
    public func clipRange(_ k: Int) -> ClosedRange<Int>? {
        guard let c = clips[k] else { return nil }
        let last = pages.count - 1
        let to = Swift.max(0, Swift.min(c.playTo, last))
        return Swift.min(c.playFrom, to)...to
    }

    private static func pageEmpty(_ pg: [Step]) -> Bool {
        return pg.allSatisfy { !$0.on && $0.locks.isEmpty && $0.sound == nil }
    }

    /// Клип с пустым паттерном в ячейку k: пустая страница, на которую не ссылается другой клип; нет — новая в конце;
    /// страниц уже 8 — любая пустая. Возвращает страницу или −1 (свободной нет).
    @discardableResult
    public mutating func putEmptyClip(_ k: Int, scale: Int?, root: Int?) -> Int {
        var used = Set<Int>()
        for (j, c) in clips.enumerated() where j != k {
            if let c = c { for p in c.playFrom...Swift.max(c.playFrom, c.playTo) { used.insert(p) } }
        }
        var page: Int = pages.indices.first { !used.contains($0) && Track.pageEmpty(pages[$0]) } ?? -1
        if page < 0 && pages.count < Params.maxPages { page = pages.count }
        if page < 0 { page = pages.indices.first { Track.pageEmpty(pages[$0]) } ?? -1 }
        if page < 0 { return -1 }
        if page == pages.count {
            let full: Bool = length == pages.count * Params.stepsPerPage
            pages.append(Track.emptyPage())
            if full { length = pages.count * Params.stepsPerPage }
        }
        clips[k] = Clip(playFrom: page, playTo: page, scale: scale, root: root)
        if k == slot { activate(k) }
        return page
    }

    /// Клип в ячейку k (вместо прежнего); активная — сразу его страницы.
    public mutating func setClip(_ k: Int, _ c: Clip?) {
        clips[k] = c
        if k == slot && c != nil { activate(k) }
    }

    /// Ближайшая пустая ячейка ниже k (потом сверху), −1 — свободных нет.
    public func freeSlot(after k: Int) -> Int {
        for d in 1..<Params.patternSlots {
            let j = (k + d) % Params.patternSlots
            if clips[j] == nil { return j }
        }
        return -1
    }

    /// DELETE клипа: шаги его страниц пустые (клип остаётся — пустых ячеек нет; звук дорожки остаётся).
    public mutating func clearClip(_ k: Int) {
        guard let r = clipRange(k) else { return }
        for p in r { pages[p] = Track.emptyPage() }
    }
}

/// Скопированная строка: клипы дорожек и сцена.
public struct RowClip: Sendable {
    public let clips: [Clip?]
    public let scene: SceneRow
}

extension Project {
    /// Слышна ли дорожка (mute / solo).
    public func audible(_ i: Int) -> Bool {
        if tracks.contains(where: { $0.solo }) { return tracks[i].solo }
        return !tracks[i].mute
    }

    public func rowFilled(_ k: Int) -> Bool {
        return tracks.contains { $0.clipFilled(k) }
    }

    /// Видимых строк: заданное число, но не меньше, чем нужно для заполненных ячеек.
    public var visibleRows: Int {
        var n = Swift.max(1, rows)
        for k in 0..<Params.patternSlots where rowFilled(k) { n = Swift.max(n, k + 1) }
        return Swift.min(n, Params.patternSlots)
    }

    public var canAddRow: Bool { return visibleRows < Params.patternSlots }

    /// Пустых ячеек нет: в видимых строках у каждой дорожки клип.
    public mutating func fillRows() {
        let n = visibleRows
        for i in tracks.indices {
            for k in 0..<n where !tracks[i].clipFilled(k) {
                tracks[i].putEmptyClip(k, scale: scale, root: root)
            }
        }
    }

    /// «+» под строками: COPY PLAYING — копии клипов играющих (и слышимых) дорожек, остальным — пустые паттерны.
    public mutating func addRow() {
        if !canAddRow { return }
        let r = visibleRows
        for i in tracks.indices {
            let t = tracks[i]
            if t.clipFilled(r) { continue }
            if plusCopy && !t.stopped && !t.blank && audible(i) {
                tracks[i].clips[r] = t.clips[t.slot]
            } else {
                tracks[i].putEmptyClip(r, scale: scale, root: root)
            }
        }
        rows = r + 1
    }

    /// DUPLICATE строки: копия встаёт под ней, строки ниже сдвигаются вниз.
    public mutating func duplicateRow(_ k: Int) {
        if !canAddRow { return }
        let n = visibleRows
        for i in tracks.indices {
            var c = tracks[i].clips
            c.insert(c[k], at: k + 1)
            tracks[i].clips = Array(c.prefix(Params.patternSlots))
            if tracks[i].slot > k { tracks[i].slot += 1 }
        }
        scenes.insert(scenes[k], at: k + 1)
        scenes = Array(scenes.prefix(Params.patternSlots))
        rows = n + 1
    }

    /// DELETE строки: её клипы убираются, строки ниже сдвигаются вверх; дорожка, игравшая её, останавливается.
    public mutating func deleteRow(_ k: Int) {
        let n = visibleRows
        for i in tracks.indices {
            var c = tracks[i].clips
            c.remove(at: k)
            c.append(nil)
            let slot = tracks[i].slot
            var active: Int = slot > k ? slot - 1 : slot
            if slot == k {
                active = c[k] != nil ? k : (c.firstIndex { $0 != nil } ?? Swift.min(k, Swift.max(0, n - 2)))
                tracks[i].stopped = true
            }
            tracks[i].clips = c
            tracks[i].activate(active)
        }
        scenes.remove(at: k)
        scenes.append(SceneRow())
        rows = Swift.max(1, n - 1)
        if arrStart > k || arrStart >= rows { arrStart = Swift.max(0, arrStart - 1) }
    }

    public func copyRow(_ k: Int) -> RowClip {
        return RowClip(clips: tracks.map { $0.clips[k] }, scene: scenes[k])
    }

    /// PASTE строки: клипы дорожек (пустые ячейки копии — пустые), имя и повторы.
    public mutating func pasteRow(_ k: Int, _ clip: RowClip) {
        for i in tracks.indices where i < clip.clips.count {
            if let c = clip.clips[i] { tracks[i].setClip(k, c) }
        }
        fillRows()
        scenes[k] = clip.scene
    }

    public mutating func setScene(_ k: Int, name: String, repeats: Int) {
        scenes[k] = SceneRow(name: String(name.trimmingCharacters(in: .whitespaces).prefix(12)),
                          repeats: Swift.max(1, Swift.min(64, repeats)))
    }

    public func sceneName(_ k: Int) -> String {
        return scenes[k].name.isEmpty ? "\(k + 1)" : scenes[k].name
    }
}
