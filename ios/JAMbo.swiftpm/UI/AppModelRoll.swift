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
