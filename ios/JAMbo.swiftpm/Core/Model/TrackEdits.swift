// Правки дорожки (как в state.ts веба): страницы (добавить, меню страницы), p-lock, триги.

extension Track {
    /// Изменение числа страниц: при полной длине длина растёт вместе со страницами; если играли все — играют все.
    public mutating func changePages(_ change: (inout [[Step]]) -> Void) {
        let n = Params.stepsPerPage
        let full: Bool = length == pages.count * n
        let allPlay: Bool = playFrom == 0 && playTo == pages.count - 1
        change(&pages)
        let last = pages.count - 1
        let maxLen = pages.count * n
        length = full ? maxLen : Swift.min(length, maxLen)
        if allPlay {
            playFrom = 0
            playTo = last
        }
        playTo = Swift.min(playTo, last)
        playFrom = Swift.min(playFrom, playTo)
    }

    /// Страницы, на которые действует меню страницы i: весь играющий диапазон, если i в нём, иначе только i.
    public func pageRange(_ i: Int) -> ClosedRange<Int> {
        if i >= playFrom && i <= playTo { return playFrom...playTo }
        return i...i
    }

    public mutating func setPlayPages(_ a: Int, _ b: Int) {
        playFrom = Swift.max(0, Swift.min(a, b))
        playTo = Swift.min(pages.count - 1, Swift.max(a, b))
    }

    public mutating func addPage() {
        if pages.count >= Params.maxPages { return }
        changePages { $0.append(Track.emptyPage()) }
    }

    /// DUPLICATE: копии диапазона встают сразу за ним; false — страниц стало бы больше 8.
    @discardableResult
    public mutating func duplicatePages(_ i: Int) -> Bool {
        let r = pageRange(i)
        if pages.count + r.count > Params.maxPages { return false }
        let copy: [[Step]] = Array(pages[r])
        changePages { $0.insert(contentsOf: copy, at: r.upperBound + 1) }
        if playFrom > r.upperBound {
            playFrom += r.count
            playTo += r.count
        }
        return true
    }

    public func copyPages(_ i: Int) -> [[Step]] {
        return Array(pages[pageRange(i)])
    }

    /// PASTE: скопированные страницы встают с первой страницы диапазона (не хватает — добавляются, до 8).
    public mutating func pastePages(_ i: Int, _ clip: [[Step]]) {
        let a = pageRange(i).lowerBound
        changePages { pg in
            for (k, page) in clip.enumerated() {
                if a + k < pg.count {
                    pg[a + k] = page
                } else if pg.count < Params.maxPages {
                    pg.append(page)
                }
            }
        }
    }

    /// CLEAR: все шаги диапазона пустые.
    public mutating func clearPages(_ i: Int) {
        for k in pageRange(i) { pages[k] = Track.emptyPage() }
    }

    /// DELETE: убрать страницы диапазона (одна остаётся всегда); false — не осталось бы ни одной.
    @discardableResult
    public mutating func deletePages(_ i: Int) -> Bool {
        let r = pageRange(i)
        if pages.count - r.count < 1 { return false }
        let from = playFrom
        let to = playTo
        changePages { $0.removeSubrange(r) }
        if from >= r.lowerBound && to <= r.upperBound {
            playFrom = Swift.min(r.lowerBound, pages.count - 1)
            playTo = playFrom
        } else if from > r.upperBound {
            playFrom = from - r.count
            playTo = to - r.count
        }
        return true
    }

    public enum Nudge { case left, right, up, down }

    /// Стрелки меню страницы: ◀ ▶ — шаги диапазона по кругу на один шаг, ▲ ▼ — ноты на октаву
    /// (если нота вышла бы за 0–127 — сдвига нет). false — ничего не изменилось.
    @discardableResult
    public mutating func nudgePages(_ i: Int, _ dir: Nudge) -> Bool {
        let r = pageRange(i)
        var steps: [Step] = r.flatMap { pages[$0] }
        switch dir {
        case .left, .right:
            if dir == .left { steps.append(steps.removeFirst()) } else { steps.insert(steps.removeLast(), at: 0) }
            let n = Params.stepsPerPage
            for (k, p) in r.enumerated() { pages[p] = Array(steps[(k * n)..<((k + 1) * n)]) }
            return true
        case .up, .down:
            let d = dir == .up ? 12 : -12
            let notes: [Int] = steps.flatMap { $0.notes }
            if notes.isEmpty || notes.contains(where: { $0 + d < 0 || $0 + d > 127 }) { return false }
            for p in r {
                for s in 0..<pages[p].count { pages[p][s].notes = pages[p][s].notes.map { $0 + d } }
            }
            return true
        }
    }

    // MARK: — шаги и p-lock

    public mutating func withStep(_ index: Int, _ change: (inout Step) -> Void) {
        let p = index / Params.stepsPerPage
        guard p >= 0 && p < pages.count else { return }
        change(&pages[p][index % Params.stepsPerPage])
    }

    /// Тап по шагу: триг с нотами notes или снять (снятый триг забывает p-lock и свой звук).
    public mutating func toggleStep(_ index: Int, notes: [Int]) {
        withStep(index) { s in
            if s.on {
                s = Step()
            } else {
                s.on = true
                if s.notes.isEmpty { s.notes = notes }
            }
        }
    }

    /// P-lock на шаге: значение параметра id (ручной — убирается из soundLocks).
    public mutating func setLock(_ index: Int, _ id: String, _ value: Double) {
        withStep(index) { s in
            s.locks[id] = value
            if let sl = s.soundLocks { s.soundLocks = sl.filter { $0 != id } }
            // P-lock Level шага — velocity всех его нот (S8): своих velocity больше нет.
            if id == "level" { s.clearVels() }
        }
    }

    public mutating func clearLock(_ index: Int, _ id: String) {
        withStep(index) { s in
            s.locks[id] = nil
            // Velocity нот привязана к Level (S8).
            if id == "level" { s.clearVels() }
        }
    }

    /// SHIFT + двойной тап по ручке: снять все p-lock со всех шагов дорожки (свой звук шага остаётся).
    public mutating func clearAllLocks() {
        for p in 0..<pages.count {
            for s in 0..<pages[p].count {
                pages[p][s].locks = [:]
                pages[p][s].clearVels()
            }
        }
    }

    /// Шаг держит длинная нота с предыдущих шагов (по всем страницам подряд).
    public func isTail(_ index: Int) -> Bool {
        var k = index - 1
        while k >= 0 {
            if let s = step(k), s.on { return s.len > index - k }
            k -= 1
        }
        return false
    }

    /// Ручной p-lock (не от пресета звука шага) или velocity ноты (S8): шаг жёлтый.
    public static func hasManualLocks(_ s: Step) -> Bool {
        if s.hasVel { return true }
        let sound = s.soundLocks ?? []
        return s.locks.keys.contains { !sound.contains($0) }
    }
}

extension Track {
    /// P-lock громкостей (mix.vol1…16) на всех шагах: дорожка k → map(k) (nil — снять).
    public mutating func remapMixLocks(_ map: (Int) -> Int?) {
        for c in 0..<clips.count {
            guard var clip = clips[c] else { continue }
            for p in 0..<clip.pages.count {
                for s in 0..<clip.pages[p].count {
                    let locks = clip.pages[p][s].locks
                    if locks.isEmpty { continue }
                    var out: [String: Double] = [:]
                    for (id, v) in locks {
                        if let k = Params.mixTrack(id) {
                            if let m = map(k) { out[Params.mixGrid[m].id] = v }
                        } else {
                            out[id] = v
                        }
                    }
                    clip.pages[p][s].locks = out
                }
            }
            clips[c] = clip
        }
    }

    /// Перенос страницы (удержание миниатюры и протягивание): страница from встаёт на место to, страницы между
    /// ними сдвигаются. Играющие страницы остаются на своих местах, но если играла одна перенесённая — обводка идёт за ней.
    public mutating func movePage(_ from: Int, _ to: Int) {
        let n = pages.count
        if from == to || from < 0 || to < 0 || from >= n || to >= n { return }
        let single: Bool = playFrom == from && playTo == from
        var pg = pages
        let page = pg.remove(at: from)
        pg.insert(page, at: to)
        pages = pg
        if single {
            playFrom = to
            playTo = to
        }
    }
}

extension Project {
    public var canAddTrack: Bool { return tracks.count < Params.maxTracks }

    /// Удалить можно любую дорожку, пока их больше 8.
    public func canDeleteTrack(_ i: Int) -> Bool {
        return tracks.count > Params.trackCount && i >= 0 && i < tracks.count
    }

    /// Новая дорожка в конце (громкость по умолчанию, своя папка); у неё клипы во всех видимых строках.
    public mutating func addTrack() {
        if !canAddTrack { return }
        var t = Track(index: tracks.count)
        t.stopped = true
        tracks.append(t)
        fillRows()
    }

    public mutating func deleteTrack(_ i: Int) {
        if !canDeleteTrack(i) { return }
        tracks.remove(at: i)
        // P-lock громкостей на шагах MIX — за дорожками: удалённой снимаются, правые сдвигаются.
        chanSeqs[Project.mixSeq].remapMixLocks { k in k == i ? nil : (k > i ? k - 1 : k) }
        remapEqDyn { k in k == i ? nil : (k > i ? k - 1 : k) }
    }

    /// Перестановка: дорожка from встаёт на место to, дорожки между ними сдвигаются (со звуком, паттернами,
    /// папкой, громкостью, mute и solo).
    public mutating func moveTrack(_ from: Int, _ to: Int) {
        let n = tracks.count
        if from == to || from < 0 || to < 0 || from >= n || to >= n { return }
        let t = tracks.remove(at: from)
        tracks.insert(t, at: to)
        let map: (Int) -> Int? = { k in
            if k == from { return to }
            if from < to && k > from && k <= to { return k - 1 }
            if to < from && k >= to && k < from { return k + 1 }
            return k
        }
        chanSeqs[Project.mixSeq].remapMixLocks(map)
        remapEqDyn(map)
    }

    /// Номера последовательностей MIX и MST в chanSeqs.
    public static let mixSeq = 0
    public static let mstSeq = 1

    /// PASTE дорожки на место i: только настройки скопированной (звук, ручки, назначения LFO/ENV, EQ, папка, громкость);
    /// имя, клипы сетки, ход игры, mute, solo и номер id — свои (решение пользователя, S14; в вебе — с паттернами и именем).
    public mutating func pasteTrack(_ i: Int, _ c: Track) {
        guard i >= 0 && i < tracks.count else { return }
        let old = tracks[i]
        // Переход MIX: свой звук скопированной — home, если она играла клип PREV.
        let own: TrackSound = c.home ?? c.sound
        var t = c
        t.clips = old.clips
        t.slot = old.slot
        t.open = old.open
        t.stopped = old.stopped
        t.mute = old.mute
        t.solo = old.solo
        t.id = old.id
        t.name = old.name
        if old.home != nil {
            // Дорожка играет клип PREV: звучит старая дорожка, вставленное станет её звуком после PREV.
            t.sound = old.sound
            t.home = own
        } else {
            t.sound = own
            t.home = nil
        }
        tracks[i] = t
    }

    public mutating func renameTrack(_ i: Int, _ name: String) {
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(12))
        if !n.isEmpty && i >= 0 && i < tracks.count { tracks[i].name = n }
    }
}

// MARK: — MORPH (как targetTracks и undoTrackEdits веба)

extension Track {
    /// Ручку id меняют в режиме MORPH: исходное значение — при первом изменении.
    public mutating func morphParam(_ id: String) {
        morphEdited = true
        if morphOrig[id] == nil { morphOrig[id] = params[id] ?? Params.byId[id]?.def ?? 0 }
    }

    /// Назначение LFO/ENV на ручку id меняют в режиме MORPH: исходное (или его отсутствие) — при первом изменении.
    public mutating func morphAssign(_ id: String) {
        morphEdited = true
        if !morphOrigAssign.keys.contains(id) { morphOrigAssign[id] = .some(assigns[id]) }
    }

    /// Вернуть всё, что меняли в режиме MORPH (p-lock шагов не трогаются).
    public mutating func undoMorph() {
        for (id, v) in morphOrig { params[id] = v }
        for (id, a) in morphOrigAssign {
            if let x = a { assigns[id] = x } else { assigns.removeValue(forKey: id) }
        }
        morphOrig = [:]
        morphOrigAssign = [:]
        morphEdited = false
    }
}
