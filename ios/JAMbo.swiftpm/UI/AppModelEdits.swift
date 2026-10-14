import Foundation

// Правки из интерфейса: шаги, ручки (с p-lock), страницы.

/// Что показывает ручка: значение, положение 0…1, жёлтое (p-lock), неактивная.
struct KnobState {
    let param: ParamDef?
    let value: Double
    let norm: Double
    /// Положение ручки дорожки (без p-lock) — белая дуга.
    let baseNorm: Double
    let locked: Bool
}

extension AppModel {
    // MARK: — шаги

    func toggleStep(_ index: Int) {
        guard channel == .track else { return }
        let notes = trigNotes
        editTrack { t in t.toggleStep(index, notes: notes) }
    }

    /// Протягивание: триг на шаге index длиной len шагов.
    func setNoteLength(_ index: Int, _ len: Int) {
        guard channel == .track else { return }
        let notes = trigNotes
        editTrack { t in
            t.withStep(index) { s in
                if !s.on {
                    s.on = true
                    if s.notes.isEmpty { s.notes = notes }
                }
                s.len = max(1, len)
            }
        }
    }

    /// Удержание первого шага и двойной тап по другому: он становится последним шагом паттерна.
    func setPatternLength(lastIndex: Int) {
        guard channel == .track else { return }
        editTrack { t in t.length = lastIndex + 1 }
    }

    // MARK: — ручки

    /// Параметр ручки slot (0…15, ряд за рядом) в текущем режиме; nil — неактивная (MIX и MST — позже).
    func param(_ slot: Int) -> ParamDef? {
        switch channel {
        case .track: return Params.trackGrid[slot]
        case .mix: return mixParam(slot)
        case .master: return nil
        }
    }

    /// Что показать на ручке: p-lock зажатого шага, иначе p-lock играющего шага (жёлтым), иначе ручка дорожки.
    func knobState(_ slot: Int) -> KnobState {
        guard let p = param(slot) else { return KnobState(param: nil, value: 0, norm: 0, baseNorm: 0, locked: false) }
        if channel == .mix {
            let v: Double = project.tracks[slot].vol
            return KnobState(param: p, value: v, norm: p.toNorm(v), baseNorm: p.toNorm(v), locked: false)
        }
        let t = track
        let base: Double = t.params[p.id] ?? p.def
        var lock: Double? = nil
        if let held = heldSteps.min() {
            lock = t.step(held)?.locks[p.id]
        } else if playing {
            let pos = openPlayPos
            if pos >= 0 { lock = t.step(pos)?.locks[p.id] }
        }
        let v: Double = lock ?? base
        return KnobState(param: p, value: v, norm: p.toNorm(v), baseNorm: p.toNorm(base), locked: lock != nil)
    }

    /// Начало поворота: положение, от которого считать (p-lock зажатого шага или ручка).
    func knobStart(_ slot: Int) -> Double {
        guard let p = param(slot) else { return 0 }
        if channel == .mix { return p.toNorm(project.tracks[slot].vol) }
        if let held = heldSteps.min(), let v = track.step(held)?.locks[p.id] { return p.toNorm(v) }
        return p.toNorm(track.params[p.id] ?? p.def)
    }

    /// Поворот: с зажатыми шагами — p-lock на всех, иначе ручка дорожки.
    func setKnob(_ slot: Int, norm: Double) {
        guard let p = param(slot) else { return }
        let v: Double = p.fromNorm(norm)
        if channel == .mix {
            edit { pr in pr.tracks[slot].vol = v }
            return
        }
        let held = heldSteps
        if held.isEmpty {
            editTrack { t in t.params[p.id] = v }
        } else {
            usedSteps.formUnion(held)
            editTrack { t in
                for i in held { t.setLock(i, p.id, v) }
            }
        }
    }

    /// Двойной тап по ручке: с зажатым шагом — снять p-lock; с SHIFT — снять все p-lock дорожки.
    func knobDoubleTap(_ slot: Int) {
        // MIX: двойной тап по ручке громкости — меню дорожки (COPY, PASTE, DELETE TRACK, RENAME), по серой — ADD TRACK.
        if channel == .mix {
            openTrackMenu(slot)
            return
        }
        guard let p = param(slot) else { return }
        if shiftHeld {
            editTrack { t in t.clearAllLocks() }
            return
        }
        let held = heldSteps
        if held.isEmpty { return }
        usedSteps.formUnion(held)
        editTrack { t in
            for i in held { t.clearLock(i, p.id) }
        }
    }

    // MARK: — страницы

    func addPage() {
        guard channel == .track, track.pages.count < Params.maxPages else { return }
        editTrack { t in t.addPage() }
        viewPage = track.pages.count - 1
    }

    /// Тап по миниатюре: эта страница играет и открыта в секвенсоре.
    func playPages(_ a: Int, _ b: Int) {
        guard channel == .track else { return }
        editTrack { t in t.setPlayPages(a, b) }
        viewPage = min(a, b)
    }

    enum PageAction { case left, right, up, down, duplicate, copy, paste, clear, delete }

    func pageAction(_ action: PageAction, page i: Int) {
        guard channel == .track else { return }
        switch action {
        case .left: editTrack { t in _ = t.nudgePages(i, .left) }
        case .right: editTrack { t in _ = t.nudgePages(i, .right) }
        case .up: editTrack { t in _ = t.nudgePages(i, .up) }
        case .down: editTrack { t in _ = t.nudgePages(i, .down) }
        case .duplicate:
            let r = track.pageRange(i)
            editTrack { t in _ = t.duplicatePages(i) }
            viewPage = min(track.pages.count - 1, r.upperBound + 1)
        case .copy: pageClipboard = track.copyPages(i)
        case .paste:
            if let clip = pageClipboard { editTrack { t in t.pastePages(i, clip) } }
        case .clear: editTrack { t in t.clearPages(i) }
        case .delete:
            editTrack { t in _ = t.deletePages(i) }
            viewPage = min(viewPage, track.pages.count - 1)
        }
    }

    func canDuplicate(_ i: Int) -> Bool {
        return track.pages.count + track.pageRange(i).count <= Params.maxPages
    }

    func canDelete(_ i: Int) -> Bool {
        return track.pages.count - track.pageRange(i).count >= 1
    }
}
