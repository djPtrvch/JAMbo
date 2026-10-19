import Foundation

/// Пианоролл (S8): окно на месте центра; PATTERNS, EQ, редактор сэмпла и окна модулей мастера не открыты вместе с ним.
extension AppModel {
    /// Кнопка с пианино в верхней панели: открыть и закрыть.
    func toggleRoll() {
        if rollView {
            closeRoll()
            return
        }
        patternView = false
        browser = nil
        editorOpen = false
        eqView = false
        eqMenu = nil
        eqMsMenu = nil
        eqDynMenu = nil
        eqPresetMenu = nil
        eqCompareMenu = false
        closeMasterWindow()
        rollView = true
    }

    func closeRoll() {
        rollView = false
        rollMenuOpen = false
    }

    /// Клип выбранной дорожки, открытый для правки.
    var rollClip: Clip { return track.openClip }

    /// Строки — ноты гаммы (гамма и нота — в верхней панели).
    var rollRows: [Int] { return Roll.rows(scale: project.scale, root: project.root) }

    /// Позиция играющего шага в проходе (−1 — не играет).
    var rollPlayPos: Int {
        let index: Int = playing ? trackPlayPos : -1
        if index < 0 { return -1 }
        return Roll.positions(rollClip).firstIndex(of: index) ?? -1
    }

    func setRollGrid(_ g: Int) {
        if !Roll.grids.contains(g) { return }
        updateSettings { s in s.rollGrid = g }
    }

    func setRollSound(_ on: Bool) {
        updateSettings { s in s.rollSound = on }
    }
}

/// Правки нот пианоролла (S8d) и звук ноты при нажатии (NOTE PREVIEW).
extension AppModel {
    /// Тап по пустому: нота на начало клетки GRID, длиной в клетку (не дальше конца прохода).
    func rollAdd(pos: Int, pitch: Int) {
        let ps: [Int] = Roll.positions(rollClip)
        let g: Int = settings.rollGrid
        let p0: Int = Roll.snap(pos, grid: g)
        guard p0 >= 0 && p0 < ps.count else { return }
        let len: Int = max(1, min(g, ps.count - p0))
        let index: Int = ps[p0]
        editTrack { t in t.addRollNote(index, pitch: pitch, len: len, vel: nil) }
        rollPreview(pitch: pitch, vel: nil, id: nil)
    }

    func rollRemove(_ n: RollNote) {
        editTrack { t in t.removeRollNote(n.index, pitch: n.pitch) }
    }

    func rollResize(_ n: RollNote, len: Int) {
        editTrack { t in t.setRollNoteLen(n.index, pitch: n.pitch, len: len) }
    }

    /// VEL: velocity ноты (Level 0…127).
    func rollSetVel(_ n: RollNote, _ v: Double) {
        let lv: Double = max(0, min(127, v.rounded()))
        editTrack { t in t.setRollNoteVel(n.index, pitch: n.pitch, vel: lv) }
    }

    /// Перенос ноты на позицию pos и высоту pitch; там уже такая нота — не переносится (nil).
    func rollMove(_ n: RollNote, pos: Int, pitch: Int) -> RollNote? {
        let ps: [Int] = Roll.positions(rollClip)
        guard pos >= 0 && pos < ps.count else { return nil }
        let dest: Int = ps[pos]
        if dest == n.index && pitch == n.pitch { return n }
        if let s = track.step(dest), s.on, s.notes.contains(pitch) { return nil }
        editTrack { t in t.moveRollNote(n.index, pitch: n.pitch, to: dest, pitch: pitch) }
        return RollNote(pos: pos, index: dest, k: 0, pitch: pitch, len: n.len, vel: n.vel)
    }

    /// NOTE PREVIEW: нота звучит на выбранной дорожке (со своей velocity); id — держится до rollPreviewOff,
    /// nil — коротко (0,25 с).
    func rollPreview(pitch: Int, vel: Double?, id: Int?) {
        if !settings.rollSound { return }
        ensureAudio()
        let t: Int = selectedTrack
        let level: Double = track.params["level"] ?? 127
        let k: Double = vel.map { $0 / max(1, level) } ?? 1
        let v: Float = Float(min(1, max(0, k)))
        let nid: Int = id ?? AppModel.nextRollId()
        audio.core.events.push(.noteOn(track: t, note: pitch, id: nid, velocity: v))
        if id == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.audio.core.events.push(.noteOff(track: t, id: nid))
            }
        }
    }

    func rollPreviewOff(id: Int) {
        audio.core.events.push(.noteOff(track: selectedTrack, id: id))
    }

    /// Номера живых нот пианоролла — отдельно от касаний клавиатуры.
    static func nextRollId() -> Int {
        rollIdCounter += 1
        return 2_000_000_000 + rollIdCounter % 1_000_000
    }
}

private var rollIdCounter: Int = 0
