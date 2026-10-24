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
    /// Назначенный LFO/ENV и удерживаемый источник (виден весь ход, на ручке — степень).
    var assign: ModAssign? = nil
    var heldSource: Int? = nil
}

extension AppModel {
    // MARK: — шаги

    func toggleStep(_ index: Int) {
        guard channel == .track else { return }
        let notes = trigNotes
        editTrack { t in t.toggleStep(index, notes: notes) }
    }

    /// STEP SWIPE = PAINT: триги на шагах from…to (стоящие не трогаются; ноты — как у нового трига).
    func paintSteps(_ from: Int, _ to: Int) {
        guard channel == .track, from <= to else { return }
        let notes = trigNotes
        editTrack { t in
            var i: Int = from
            while i <= to {
                t.withStep(i) { s in
                    if !s.on {
                        s.on = true
                        if s.notes.isEmpty { s.notes = notes }
                    }
                }
                i += 1
            }
        }
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
                s.setAllLen(len)
            }
        }
    }

    /// Зажат шаг a, тап по шагу b: b становится копией a (триг, ноты, длина, p-lock, свой звук; у MIX и MST — p-lock).
    /// Возвращает прежний шаг b (двойной тап при зажатом первом шаге отменяет копию и ставит длину паттерна).
    func copyStep(from a: Int, to b: Int) -> Step? {
        guard a != b, let src = seq.step(a), let old = seq.step(b) else { return nil }
        editSeq { t in t.withStep(b) { s in s = src } }
        return old
    }

    /// Вернуть шаг index (отмена копии).
    func restoreStep(_ index: Int, _ step: Step) {
        editSeq { t in t.withStep(index) { s in s = step } }
    }

    /// Удержание первого шага и двойной тап по другому: он становится последним шагом паттерна (и у MIX, MST).
    func setPatternLength(lastIndex: Int) {
        editSeq { t in t.length = lastIndex + 1 }
    }

    // MARK: — ручки

    /// Параметр ручки slot (0…15, ряд за рядом) в текущем режиме; nil — неактивная (MIX — несуществующая дорожка).
    func param(_ slot: Int) -> ParamDef? {
        switch channel {
        case .track:
            if modMode { return modParam(slot) }
            if fxMode { return fxParam(slot) }
            let p: ParamDef = Params.grid(sound: track.sample)[slot]
            return p.id.isEmpty ? nil : p
        case .mix: return mixParam(slot)
        case .master: return Params.masterGrid[slot]
        }
    }

    /// Что показать на ручке: p-lock зажатого шага, иначе p-lock играющего шага (жёлтым), иначе ручка дорожки.
    func knobState(_ slot: Int) -> KnobState {
        guard let p = param(slot) else { return KnobState(param: nil, value: 0, norm: 0, baseNorm: 0, locked: false) }
        if channel == .mix {
            let base: Double = project.tracks[slot].vol
            let lock: Double? = seqLock(p)
            let v: Double = lock ?? base
            return KnobState(param: p, value: v, norm: p.toNorm(v), baseNorm: p.toNorm(base), locked: lock != nil)
        }
        if channel == .master {
            let v: Double = masterValue(p)
            return KnobState(param: p, value: v, norm: p.toNorm(v), baseNorm: p.toNorm(v), locked: false)
        }
        let t = track
        let base: Double = fxMode ? fxValue(p) : t.params[p.id] ?? p.def
        var lock: Double? = nil
        if let held = heldSteps.min() {
            lock = t.step(held)?.locks[p.id]
        } else if playing {
            let pos = openPlayPos
            if pos >= 0 { lock = t.step(pos)?.locks[p.id] }
        }
        let v: Double = lock ?? base
        return KnobState(param: p, value: v, norm: p.toNorm(v), baseNorm: p.toNorm(base), locked: lock != nil,
                         assign: assign(slot), heldSource: canAssign ? heldSource : nil)
    }

    /// Начало поворота: положение, от которого считать (p-lock зажатого шага или ручка).
    func knobStart(_ slot: Int) -> Double {
        guard let p = param(slot) else { return 0 }
        if channel == .mix {
            if let held = heldSteps.min(), let v = seq.step(held)?.locks[p.id] { return p.toNorm(v) }
            return p.toNorm(project.tracks[slot].vol)
        }
        if channel == .master { return p.toNorm(masterValue(p)) }
        if let held = heldSteps.min(), let v = track.step(held)?.locks[p.id] { return p.toNorm(v) }
        if fxMode { return p.toNorm(fxValue(p)) }
        return p.toNorm(track.params[p.id] ?? p.def)
    }

    /// Поворот: с зажатыми шагами — p-lock на всех, иначе ручка дорожки.
    func setKnob(_ slot: Int, norm: Double) {
        guard let p = param(slot) else { return }
        var v: Double = p.fromNorm(norm)
        // Pitch сэмпла по полутонам (SETTINGS → SAMPLER → PITCH: SEMITONES).
        if p.id == "pitch" && settings.pitchSemitones && channel == .track && !fxMode && !modMode { v = v.rounded() }
        // MIX: с зажатыми шагами — p-lock громкости на шагах последовательности MIX, иначе громкость дорожки.
        if channel == .mix {
            let held = heldSteps
            if held.isEmpty {
                edit { pr in pr.tracks[slot].vol = v }
            } else {
                usedSteps.formUnion(held)
                editSeq { t in
                    for i in held { t.setLock(i, p.id, v) }
                }
            }
            return
        }
        // Мастер: без p-lock — с зажатым шагом крутится само значение (noLock, как в вебе).
        if channel == .master {
            edit { pr in pr.master[p.id] = v }
            return
        }
        let held = heldSteps
        if held.isEmpty && fxMode {
            setFx(p, v)
        } else if held.isEmpty {
            let m = morph
            // MORPH на все дорожки (SETTINGS → MORPH): та же ручка у остальных — сдвиг на ту же долю хода.
            let all: Bool = m && settings.morphAll
            let i = selectedTrack
            edit { pr in
                if m { pr.tracks[i].morphParam(p.id) }
                pr.tracks[i].params[p.id] = v
                if all { pr.morphShift(from: i, id: p.id, norm: norm) }
            }
        } else {
            usedSteps.formUnion(held)
            editTrack { t in
                for i in held { t.setLock(i, p.id, v) }
            }
        }
    }

    /// Двойной тап по ручке: с зажатым шагом — снять p-lock; с SHIFT — снять все p-lock дорожки.
    func knobDoubleTap(_ slot: Int) {
        // MIX: с зажатым шагом — снять p-lock громкости; без — меню дорожки (COPY, PASTE, DELETE TRACK, RENAME),
        // по серой — ADD TRACK.
        if channel == .mix {
            let held = heldSteps
            if held.isEmpty || slot >= project.tracks.count {
                openTrackMenu(slot)
                return
            }
            usedSteps.formUnion(held)
            let id: String = Params.mixGrid[slot].id
            editSeq { t in
                for i in held { t.clearLock(i, id) }
            }
            return
        }
        guard let p = param(slot), channel == .track else { return }
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

    /// P-lock ручки на показанной последовательности: зажатого шага, иначе играющего (жёлтым).
    func seqLock(_ p: ParamDef) -> Double? {
        let t = seq
        if let held = heldSteps.min() { return t.step(held)?.locks[p.id] }
        if playing {
            let pos = openPlayPos
            if pos >= 0 { return t.step(pos)?.locks[p.id] }
        }
        return nil
    }

    /// Значение параметра мастера (нет в проекте — по умолчанию).
    func masterValue(_ p: ParamDef) -> Double {
        return project.master[p.id] ?? p.def
    }

    // MARK: — страницы

    func addPage() {
        guard seq.pages.count < Params.maxPages else { return }
        editSeq { t in t.addPage() }
        viewPage = seq.pages.count - 1
    }

    /// Тап по миниатюре: эта страница играет и открыта в секвенсоре.
    func playPages(_ a: Int, _ b: Int) {
        editSeq { t in t.setPlayPages(a, b) }
        viewPage = min(a, b)
        spanView = true
    }

    enum PageAction { case left, right, up, down, duplicate, copy, paste, clear, delete }

    /// Скорость открытого клипа выбранной дорожки (меню страницы, S14): Clip.rates — 2, 1, 1/2…1/16 (UNDO).
    func setClipRate(_ r: Int) {
        guard channel == .track, Clip.rates.contains(r) else { return }
        editTrack { t in t.withOpen { c in c.rate = r == 0 ? nil : r } }
    }

    func pageAction(_ action: PageAction, page i: Int) {
        switch action {
        case .left: editSeq { t in _ = t.nudgePages(i, .left) }
        case .right: editSeq { t in _ = t.nudgePages(i, .right) }
        case .up: editSeq { t in _ = t.nudgePages(i, .up) }
        case .down: editSeq { t in _ = t.nudgePages(i, .down) }
        case .duplicate:
            let r = seq.pageRange(i)
            editSeq { t in _ = t.duplicatePages(i) }
            viewPage = min(seq.pages.count - 1, r.upperBound + 1)
        case .copy: pageClipboard = seq.copyPages(i)
        case .paste:
            if let clip = pageClipboard { editSeq { t in t.pastePages(i, clip) } }
        case .clear: editSeq { t in t.clearPages(i) }
        case .delete:
            editSeq { t in _ = t.deletePages(i) }
            viewPage = min(viewPage, seq.pages.count - 1)
        }
    }

    func canDuplicate(_ i: Int) -> Bool {
        return seq.pages.count + seq.pageRange(i).count <= Params.maxPages
    }

    func canDelete(_ i: Int) -> Bool {
        return seq.pages.count - seq.pageRange(i).count >= 1
    }
}
