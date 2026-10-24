import Foundation

// Клипы и строки сетки паттернов (как slots, putEmptyClip, fillRows, строки в state.ts веба).
// Запуск и остановка клипов — игра (секвенсор в колбэке), здесь — только правки.

extension Track {
    public func clipFilled(_ k: Int) -> Bool {
        return k >= 0 && k < clips.count && clips[k] != nil
    }

    /// Сделать ячейку k активной; открытый клип идёт за активным, если был им. Клип со своим звуком (src: клип PREV
    /// перехода MIX, импортированный клип) приносит его, клип без своего — звук дорожки (moveSlot).
    public mutating func activate(_ k: Int) {
        if open == slot { open = k }
        moveSlot(k)
    }

    /// Активная ячейка — k (open не трогается). Звук прежнего клипа со своим звуком (правки) — обратно в его src,
    /// звук дорожки возвращается из home; у нового клипа со своим звуком он становится звуком дорожки, свой — в home.
    public mutating func moveSlot(_ k: Int) {
        if let own = home {
            if clipFilled(slot), let old = clips[slot]!.src {
                var cur: TrackSound = sound
                cur.vol = old.vol
                clips[slot]!.src = cur
            }
            sound = own
            home = nil
        }
        slot = k
        settleSound()
    }

    /// Копия клипа k: у клипа со своим звуком — его звук сейчас (у активного правки ещё в звуке дорожки).
    public func clipCopy(_ k: Int) -> Clip? {
        guard clipFilled(k), var c = clips[k] else { return nil }
        if k == slot && home != nil, let old = c.src {
            var cur: TrackSound = sound
            cur.vol = old.vol
            c.src = cur
        }
        return c
    }

    /// Правка клипа k (не открытого): например, запись с REC — в играющий клип, что бы ни было открыто.
    public mutating func editing<R>(_ k: Int, _ f: (inout Track) -> R) -> R {
        let saved = open
        open = k
        let r = f(&self)
        open = saved
        return r
    }

    /// Играющие страницы клипа k.
    public func clipRange(_ k: Int) -> ClosedRange<Int>? {
        return clips[k]?.range
    }

    /// Клип с пустым паттерном (одна пустая страница) в ячейку k.
    public mutating func putEmptyClip(_ k: Int, scale: Int?, root: Int?) {
        clips[k] = Clip(scale: scale, root: root)
    }

    /// Клип в ячейку k (вместо прежнего) — независимая копия.
    public mutating func setClip(_ k: Int, _ c: Clip?) {
        if k != slot {
            clips[k] = c
            return
        }
        // Активная ячейка: прежний свой звук клипа уходит, звук — нового клипа (или дорожки).
        if let own = home {
            sound = own
            home = nil
        }
        clips[k] = c
        settleSound()
    }

    /// Ближайшая пустая ячейка ниже k (потом сверху), −1 — свободных нет.
    public func freeSlot(after k: Int) -> Int {
        for d in 1..<Params.patternSlots {
            let j = (k + d) % Params.patternSlots
            if clips[j] == nil { return j }
        }
        return -1
    }

    /// DELETE клипа: шаги всех его страниц пустые (ноты, триги, p-lock, звуки шагов); клип, его страницы и длина
    /// остаются (пустых ячеек нет), другие клипы и звук дорожки не меняются.
    public mutating func clearClip(_ k: Int) {
        guard var c = clips[k] else { return }
        clips[k] = nil
        for p in c.pages.indices { c.pages[p] = Track.emptyPage() }
        clips[k] = c
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
    /// Строк проекта: при переходе MIX последняя строка — PREV (её нет среди строк проекта).
    public var rowLimit: Int { return prevRow ? Params.patternSlots - 1 : Params.patternSlots }

    public var visibleRows: Int {
        let lim = rowLimit
        var n = Swift.max(1, rows)
        for k in 0..<lim where rowFilled(k) { n = Swift.max(n, k + 1) }
        return Swift.min(n, lim)
    }

    public var canAddRow: Bool { return visibleRows < rowLimit }

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
                tracks[i].clips[r] = t.clipCopy(t.slot)
                // Копия клипа PREV — только паттерн (звук старой дорожки остаётся в PREV).
                if prevRow && t.slot == Project.prevIndex { tracks[i].clips[r]?.src = nil }
            } else {
                tracks[i].putEmptyClip(r, scale: scale, root: root)
            }
        }
        rows = r + 1
    }

    /// DUPLICATE строки: копия встаёт под ней, строки ниже сдвигаются вниз (строка PREV перехода MIX остаётся).
    public mutating func duplicateRow(_ k: Int) {
        if !canAddRow { return }
        let n = visibleRows
        let lim = rowLimit
        for i in tracks.indices {
            var c = tracks[i].clips
            c.insert(tracks[i].clipCopy(k), at: k + 1)
            c.remove(at: lim)
            tracks[i].clips = c
            if tracks[i].slot > k && tracks[i].slot < lim { tracks[i].slot += 1 }
            if tracks[i].open > k && tracks[i].open < lim { tracks[i].open += 1 }
        }
        scenes.insert(scenes[k], at: k + 1)
        scenes.remove(at: lim)
        rows = n + 1
    }

    /// DELETE строки: её клипы убираются, строки ниже сдвигаются вверх; дорожка, игравшая её, останавливается.
    /// Строка PREV перехода MIX остаётся на месте.
    public mutating func deleteRow(_ k: Int) {
        let n = visibleRows
        let lim = rowLimit
        for i in tracks.indices {
            var c = tracks[i].clips
            c.remove(at: k)
            c.insert(nil, at: lim - 1)
            let slot = tracks[i].slot
            let first: Int? = c.prefix(lim).firstIndex { $0 != nil }
            let fallback: Int = c[k] != nil ? k : (first ?? Swift.min(k, Swift.max(0, n - 2)))
            var active: Int = slot > k && slot < lim ? slot - 1 : slot
            if slot == k {
                active = fallback
                tracks[i].stopped = true
                // Свой звук удалённого клипа уходит вместе с ним.
                if let own = tracks[i].home {
                    tracks[i].sound = own
                    tracks[i].home = nil
                }
            }
            let open = tracks[i].open
            tracks[i].clips = c
            tracks[i].slot = active
            tracks[i].settleSound()
            tracks[i].open = open == k ? fallback : (open > k && open < lim ? open - 1 : open)
        }
        scenes.remove(at: k)
        scenes.insert(SceneRow(), at: lim - 1)
        rows = Swift.max(1, n - 1)
        if arrStart > k || arrStart >= rows { arrStart = Swift.max(0, arrStart - 1) }
    }

    /// Перенос строки (удержание и перетаскивание по колонке строк): строка a со всеми клипами, именем и повторами
    /// встаёт на место b, строки между ними сдвигаются; активные и открытые ячейки дорожек и строка старта идут за
    /// своими строками. Только среди видимых строк (строка PREV перехода MIX не двигается).
    public mutating func moveRow(_ a: Int, to b: Int) {
        let n = visibleRows
        guard a != b, a >= 0, b >= 0, a < n, b < n else { return }
        // Новое место прежнего номера строки k.
        func moved(_ k: Int) -> Int {
            if k == a { return b }
            if a < b && k > a && k <= b { return k - 1 }
            if b < a && k >= b && k < a { return k + 1 }
            return k
        }
        for i in tracks.indices {
            var c = tracks[i].clips
            let clip = c.remove(at: a)
            c.insert(clip, at: b)
            tracks[i].clips = c
            tracks[i].slot = moved(tracks[i].slot)
            tracks[i].open = moved(tracks[i].open)
        }
        let scene = scenes.remove(at: a)
        scenes.insert(scene, at: b)
        arrStart = moved(arrStart)
    }

    public func copyRow(_ k: Int) -> RowClip {
        return RowClip(clips: tracks.map { $0.clipCopy(k) }, scene: scenes[k])
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
