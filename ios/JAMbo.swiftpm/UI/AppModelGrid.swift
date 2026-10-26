import Foundation

// Сетка паттернов: ячейки (клипы), строки, запуск и остановка (как patterns.ts и state.ts веба).
// Запуск при игре — командой в колбэк (там с точностью до отсчёта), без игры — сразу в проекте.

/// Меню ячейки (быстрый свайп вверх): copy, paste, delete.
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
        // CHANGE KEY OFF (переход MIX): гамма и нота старого проекта держатся, пока идёт игра.
        let hold: Bool = keyHold
        mutatePlay({ p in
            if let s = c.scale, !hold { p.scale = s }
            if let r = c.root, !hold { p.root = r }
            if let f = c.fx { p.fx.merge(f) { _, b in b } }
        }, publish: true)
    }

    /// Правка гаммы и ноты записывается в клип лидера и в активные клипы остальных играющих дорожек: при PLAY и на
    /// каждом круге строки лидером снова становится клип выбранной дорожки — со старой гаммой он возвращал её назад;
    /// клипы PREV не трогаются (у каждого клипа своя гамма). FX — только в клип лидера.
    func writeLead(_ p: inout Project) {
        let i = min(lead, p.tracks.count - 1)
        for t in p.tracks.indices where t == i || !p.tracks[t].stopped {
            let k = p.tracks[t].slot
            // Клипы PREV (старого проекта) держат свою гамму и ноту.
            guard p.tracks[t].clips[k] != nil, !isPrev(k) else { continue }
            p.tracks[t].clips[k]?.scale = p.scale
            p.tracks[t].clips[k]?.root = p.root
        }
        let k = p.tracks[i].slot
        guard p.tracks[i].clips[k] != nil else { return }
        p.tracks[i].clips[k]?.fx = p.fx
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
        // Пустая ячейка PREV (у дорожки не было старого паттерна) не нажимается.
        if isPrev(k) && !project.tracks[i].clipFilled(k) { return }
        select(track: i)
        setEditSlot(i, k)
        let t = project.tracks[i]
        if !t.clipFilled(k) {
            let s = project.scale, r = project.root
            edit { p in p.tracks[i].putEmptyClip(k, scale: s, root: r) }
            viewPage = 0
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
        if isPrev(k) && !project.tracks[i].clipFilled(k) { return }
        select(track: i)
        let t = project.tracks[i]
        let idle: Bool = !playing || t.stopped
        if !t.clipFilled(k) {
            if idle { mutatePlay({ p in p.tracks[i].moveSlot(k); p.tracks[i].stopped = true }, publish: true) }
            openClip(i, k)
            return
        }
        if k != t.slot && idle {
            mutatePlay({ p in p.tracks[i].moveSlot(k); p.tracks[i].stopped = true }, publish: true)
        }
        openClip(i, k)
        viewPage = project.tracks[i].clipRange(k)?.lowerBound ?? 0
        heldSteps.removeAll()
    }

    func setEditSlot(_ i: Int, _ k: Int) {
        guard i == selectedTrack else { return }
        openClip(i, k)
    }

    func deny(_ c: CellRef) {
        deniedCell = c
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if self.deniedCell == c { self.deniedCell = nil }
        }
    }

    /// Копия клипа со своим звуком — с ним (звук привязан к клипу); копия клипа PREV — только паттерн (звук старой
    /// дорожки остаётся в PREV).
    func copyClip(_ c: CellRef) {
        clipClipboard = project.tracks[c.track].clipCopy(c.row)
        if isPrev(c.row) { clipClipboard?.src = nil }
    }

    func pasteClip(_ c: CellRef) {
        guard let clip = clipClipboard else { return }
        if isPrev(c.row) {
            deny(c)
            return
        }
        edit { p in p.tracks[c.track].setClip(c.row, clip) }
        viewPage = min(viewPage, seq.pages.count - 1)
    }

    func deleteClip(_ c: CellRef) {
        if isPrev(c.row) {
            deny(c)
            return
        }
        edit { p in p.tracks[c.track].clearClip(c.row) }
        heldSteps.removeAll()
        viewPage = max(0, min(viewPage, seq.pages.count - 1))
    }

    /// Перетаскивание: независимая копия клипа (его паттерн, гамма, нота, свой звук) в любую ячейку любого столбца.
    func dropClip(from a: CellRef, to b: CellRef) {
        if a == b { return }
        guard var clip = project.tracks[a.track].clipCopy(a.row) else { return }
        if isPrev(b.row) {
            deny(b)
            return
        }
        if isPrev(a.row) { clip.src = nil }
        edit { p in p.tracks[b.track].setClip(b.row, clip) }
        viewPage = min(viewPage, seq.pages.count - 1)
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

    /// Перенос строки удержанием: строка со всеми клипами, именем и повторами — на место b.
    func moveRow(_ a: Int, to b: Int) {
        if a == b || isPrev(a) || isPrev(b) { return }
        edit { p in p.moveRow(a, to: b) }
        if playing { audio.core.events.push(.adoptPlay) }
    }

    func deleteRow(_ k: Int) {
        edit { p in p.deleteRow(k) }
        if playing { audio.core.events.push(.adoptPlay) }
        heldSteps.removeAll()
        viewPage = min(viewPage, seq.pages.count - 1)
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

    /// Куда встаёт TO ARRANGE (решения пользователя): с курсора, с магнитом — на линии сетки.
    var arrPlaceAt: Int {
        return project.arrange.snapped(arrCursor)
    }

    /// TO ARRANGE в меню строки (S15e): имя и повторы из окна строки и перенос — одна запись UNDO. В строке есть
    /// выделение рамкой — переносится всё выделенное.
    func rowToArrange(_ k: Int, name: String, repeats: Int) {
        let at: Int = arrPlaceAt
        let rp: Bool = settings.arrangeRepeats
        let sel: GridSelection = gridSel
        let many: Bool = sel.touches(row: k)
        edit { p in
            p.setScene(k, name: name, repeats: repeats)
            if many { p.selectionToArrange(sel, at: at, repeats: rp) } else { p.rowToArrange(k, at: at, repeats: rp) }
        }
        gridSel = GridSelection()
    }

    /// TO ARRANGE в меню клипа: клип в выделении рамкой — всё выделенное, иначе — один проход этого клипа.
    func clipToArrange(_ c: CellRef) {
        let at: Int = arrPlaceAt
        let rp: Bool = settings.arrangeRepeats
        let sel: GridSelection = gridSel.contains(c) ? gridSel : GridSelection(cells: [c])
        edit { p in p.selectionToArrange(sel, at: at, repeats: rp) }
        gridSel = GridSelection()
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

    /// Кнопка STEPS под LOOP ROW: строка дорожек, секвенсор и клавиатура под сеткой паттернов скрыты — сетка до низа.
    func toggleGridSteps() {
        edit { p in p.gridHideSteps.toggle() }
    }

    // MARK: — окно строк

    /// Окно строк: 8 строк сетки, «+» — тоже строка окна. Возвращает строки окна (nil — «+» или пусто) и можно ли листать.
    /// Переход MIX: строк проекта в окне 7, восьмая — PREV (всегда внизу).
    var gridWindow: (rows: [Int?], plusRow: Int?, top: Int, maxTop: Int) {
        let n = project.visibleRows
        let plus = project.canAddRow
        let total = n + (plus ? 1 : 0)
        let prev: Bool = project.prevRow
        let shown: Int = gridRowsShown
        let win = prev ? shown - 1 : shown
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
        if prev { rows.append(AppModel.prevRow) }
        return (rows, plusRow, top, maxTop)
    }

    /// Стрелка ▲ (−1) / ▼ (+1): VIEW — окно на строку; SWITCH при игре — ещё и переход строки в конце прохода.
    func gridArrow(_ dir: Int) {
        let w = gridWindow
        if project.arrowSwitch && playing {
            let cur = live.sceneQueued >= 0 ? live.sceneQueued : max(0, live.sceneRow)
            let k = min(project.visibleRows - 1, max(0, cur + dir))
            if k != cur { queueScene(k, atPass: true) }
            let win: Int = project.prevRow ? gridRowsShown - 1 : gridRowsShown
            if k < w.top { gridTop = k } else if k >= w.top + win { gridTop = k - win + 1 }
            return
        }
        gridTop = min(w.maxTop, max(0, w.top + dir))
    }

    func togglePatterns() {
        patternView.toggle()
        if patternView {
            browser = nil
            editorOpen = false
            eqView = false
            closeRoll()
            closeArrange()
            closeMasterWindow()
            openClip(selectedTrack, track.slot)
        }
    }
}
