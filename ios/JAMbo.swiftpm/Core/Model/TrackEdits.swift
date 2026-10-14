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
        }
    }

    public mutating func clearLock(_ index: Int, _ id: String) {
        withStep(index) { s in s.locks[id] = nil }
    }

    /// SHIFT + двойной тап по ручке: снять все p-lock со всех шагов дорожки (свой звук шага остаётся).
    public mutating func clearAllLocks() {
        for p in 0..<pages.count {
            for s in 0..<pages[p].count { pages[p][s].locks = [:] }
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

    /// Ручной p-lock (не от пресета звука шага): шаг жёлтый.
    public static func hasManualLocks(_ s: Step) -> Bool {
        let sound = s.soundLocks ?? []
        return s.locks.keys.contains { !sound.contains($0) }
    }
}
