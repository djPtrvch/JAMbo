import Foundation

// Сетка паттернов: ячейки (клипы), строки, запуск и остановка (как patterns.ts и state.ts веба).
// Запуск при игре — командой в колбэк (там с точностью до отсчёта), без игры — сразу в проекте.

struct CellRef: Equatable {
    let track: Int
    let row: Int
}

/// Меню ячейки (быстрый свайп вверх): duplicate, copy, paste, delete.
struct CellMenuState: Equatable {
    let cell: CellRef
    let anchor: CGRect
}

extension AppModel {
    // MARK: — лидер: гамма и нота клипа, запущенного последним

    func started(_ t: Int) {
        startSeq += 1
        startOrder[t] = startSeq
        pendingStarts.append(t)
    }

    /// После всех запусков кадра (строка — сразу все дорожки): лидер — выбранная дорожка, иначе самая левая.
    func applyPendingLead() {
        if pendingStarts.isEmpty { return }
        let list = pendingStarts
        pendingStarts.removeAll()
        applyLead(list.contains(selectedTrack) ? selectedTrack : (list.min() ?? 0))
    }

    /// Лидер остановлен — значения переходят к последнему из ещё играющих.
    func leadStopped(_ t: Int) {
        if t != lead { return }
        var best = -1
        for (k, tr) in project.tracks.enumerated() where !tr.stopped && k != t {
            if best < 0 || startOrder[k] > startOrder[best] { best = k }
        }
        if best >= 0 { applyLead(best) }
    }

    func applyLead(_ i: Int) {
        guard i < project.tracks.count else { return }
        lead = i
        let tr = project.tracks[i]
        guard let c = tr.clips[tr.slot] else { return }
        mutatePlay({ p in
            if let s = c.scale { p.scale = s }
            if let r = c.root { p.root = r }
        }, publish: false)
    }

    /// Правка гаммы и ноты записывается и в клип лидера.
    func writeLead(_ p: inout Project) {
        let i = min(lead, p.tracks.count - 1)
        let k = p.tracks[i].slot
        guard p.tracks[i].clips[k] != nil else { return }
        p.tracks[i].clips[k]?.scale = p.scale
        p.tracks[i].clips[k]?.root = p.root
    }

    // MARK: — запуск

    /// Запуск клипа k (или Launcher.stop) дорожки i: при игре — с конца прохода, без игры — сразу.
    func queueClip(_ i: Int, _ k: Int) {
        if playing {
            audio.core.events.push(.launch(track: i, slot: k))
            return
        }
        mutatePlay({ p in
            if k == Launcher.stop {
                p.tracks[i].stopped = true
            } else {
                p.tracks[i].activate(k)
                p.tracks[i].stopped = false
            }
        }, publish: true)
        if k == Launcher.stop { leadStopped(i) } else { started(i) }
        applyPendingLead()
    }

    /// Тап по строке: при игре — с начала такта (повторный — отмена), без игры — сразу.
    func queueScene(_ k: Int, atPass: Bool = false) {
        if playing {
            audio.core.events.push(.scene(row: k, atPass: atPass))
            return
        }
        mutatePlay({ p in
            for i in p.tracks.indices {
                if p.tracks[i].clipFilled(k) {
                    p.tracks[i].activate(k)
                    p.tracks[i].stopped = false
                } else {
                    p.tracks[i].stopped = true
                }
            }
        }, publish: true)
        for i in project.tracks.indices where !project.tracks[i].stopped { started(i) }
        applyPendingLead()
    }

    // MARK: — ячейки

    /// Тап: пустая — новый клип с пустым паттерном и запуск; играющая — остановка; иначе — запуск.
    func tapCell(_ i: Int, _ k: Int) {
        guard i < project.tracks.count else { return }
        select(track: i)
        setEditSlot(i, k)
        let t = project.tracks[i]
        if !t.clipFilled(k) {
            var page = -1
            let s = project.scale, r = project.root
            edit { p in page = p.tracks[i].putEmptyClip(k, scale: s, root: r) }
            if page < 0 {
                deny(CellRef(track: i, row: k))
                return
            }
            viewPage = page
            queueClip(i, k)
        } else if k == t.slot && !t.stopped {
            queueClip(i, Launcher.stop)
        } else {
            queueClip(i, k)
        }
    }

    /// Удержание: пустая — только выбор (не играет — ячейка становится активной); заполненная — правка без запуска.
    func holdCell(_ i: Int, _ k: Int) {
        guard i < project.tracks.count else { return }
        select(track: i)
        editSlot = k
        let t = project.tracks[i]
        let idle: Bool = !playing || t.stopped
        if !t.clipFilled(k) {
            if idle { mutatePlay({ p in p.tracks[i].slot = k; p.tracks[i].stopped = true }, publish: true) }
            return
        }
        if k != t.slot {
            if idle {
                mutatePlay({ p in p.tracks[i].activate(k); p.tracks[i].stopped = true }, publish: true)
            }
        }
        viewPage = project.tracks[i].clipRange(k)?.lowerBound ?? 0
        heldSteps.removeAll()
    }

    func setEditSlot(_ i: Int, _ k: Int) {
        guard i == selectedTrack else { return }
        editSlot = k
        if let r = project.tracks[i].clipRange(k) {
            viewPage = r.lowerBound
            heldSteps.removeAll()
        }
    }

    func deny(_ c: CellRef) {
        deniedCell = c
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if self.deniedCell == c { self.deniedCell = nil }
        }
    }

    func copyClip(_ c: CellRef) {
        clipClipboard = project.tracks[c.track].clips[c.row]
    }

    func pasteClip(_ c: CellRef) {
        guard let clip = clipClipboard else { return }
        edit { p in p.tracks[c.track].setClip(c.row, clip) }
    }

    func deleteClip(_ c: CellRef) {
        edit { p in p.tracks[c.track].clearClip(c.row) }
        heldSteps.removeAll()
    }

    /// Перетаскивание: копия клипа в другую ячейку (в другом столбце — страницы той дорожки).
    func dropClip(from a: CellRef, to b: CellRef) {
        if a == b { return }
        guard let clip = project.tracks[a.track].clips[a.row] else { return }
        edit { p in p.tracks[b.track].setClip(b.row, clip) }
    }

    // MARK: — строки

    func addRow() {
        edit { p in p.addRow() }
        gridTop = Params.patternSlots
    }

    func duplicateRow(_ k: Int) {
        edit { p in p.duplicateRow(k) }
        if playing { audio.core.events.push(.adoptPlay) }
    }

    func deleteRow(_ k: Int) {
        edit { p in p.deleteRow(k) }
        if playing { audio.core.events.push(.adoptPlay) }
        heldSteps.removeAll()
        viewPage = min(viewPage, track.pages.count - 1)
    }

    func copyRow(_ k: Int) {
        rowClipboard = project.copyRow(k)
    }

    func pasteRow(_ k: Int) {
        guard let clip = rowClipboard else { return }
        edit { p in p.pasteRow(k, clip) }
    }

    func setScene(_ k: Int, name: String, repeats: Int) {
        edit { p in p.setScene(k, name: name, repeats: repeats) }
    }

    func setArrangement(start: Int? = nil, endStop: Bool? = nil, plusCopy: Bool? = nil, arrowSwitch: Bool? = nil) {
        edit { p in
            if let s = start { p.arrStart = s }
            if let e = endStop { p.arrEndStop = e }
            if let c = plusCopy { p.plusCopy = c }
            if let a = arrowSwitch { p.arrowSwitch = a }
        }
    }

    func toggleRowLoop() {
        edit { p in p.rowLoop.toggle() }
    }

    // MARK: — окно строк

    /// Окно строк: 8 строк сетки, «+» — тоже строка окна. Возвращает строки окна (nil — «+» или пусто) и можно ли листать.
    var gridWindow: (rows: [Int?], plusRow: Int?, top: Int, maxTop: Int) {
        let n = project.visibleRows
        let plus = project.canAddRow
        let total = n + (plus ? 1 : 0)
        let win = Params.gridRows
        let maxTop = max(0, total - win)
        let top = min(max(0, gridTop), maxTop)
        var rows: [Int?] = []
        var plusRow: Int? = nil
        for r in 0..<win {
            let k = top + r
            if k < n { rows.append(k) } else {
                rows.append(nil)
                if plus && k == n { plusRow = r }
            }
        }
        return (rows, plusRow, top, maxTop)
    }

    /// Стрелка ▲ (−1) / ▼ (+1): VIEW — окно на строку; SWITCH при игре — ещё и переход строки в конце прохода.
    func gridArrow(_ dir: Int) {
        let w = gridWindow
        if project.arrowSwitch && playing {
            let cur = live.sceneQueued >= 0 ? live.sceneQueued : max(0, live.sceneRow)
            let k = min(project.visibleRows - 1, max(0, cur + dir))
            if k != cur { queueScene(k, atPass: true) }
            if k < w.top { gridTop = k } else if k >= w.top + Params.gridRows { gridTop = k - Params.gridRows + 1 }
            return
        }
        gridTop = min(w.maxTop, max(0, w.top + dir))
    }

    func togglePatterns() {
        patternView.toggle()
        if patternView { editSlot = track.slot }
    }
}
