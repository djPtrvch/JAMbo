import Foundation

/// Где сделана правка (17.11, решение пользователя): UNDO и REDO сначала показывают это место — дорожку (MIX, MST),
/// её клип и страницу, окно (сетка ручек, FX / MOD в режиме toggle, PATTERNS, ARRANGE, пианоролл, EQ, редактор сэмпла,
/// окно модуля мастера, микшер) — и там отменяют или возвращают правку: видно, что именно меняется.
struct UndoPlace: Equatable {
    var channel: Channel
    /// Track.id выбранной дорожки (номер меняется при перестановке и удалении).
    var trackId: Int
    var clip: Int
    var page: Int
    var window: UndoWindow
    var arrange: Bool
    /// FX или MOD на сетке ручек (только кнопки в режиме toggle; удержание не воспроизводится).
    var grid: GridPage?
}

enum UndoWindow: Equatable {
    case main
    case patterns
    case roll
    case eq
    case editor
    case master(Int)
    case mixer
}

extension AppModel {
    /// Место на экране сейчас (как RootView.center: что на месте центра).
    func undoPlaceNow() -> UndoPlace {
        let t: Track = track
        var w: UndoWindow = .main
        if rollView {
            w = .roll
        } else if patternView {
            w = .patterns
        } else if eqView {
            w = .eq
        } else if channel == .master, let m = masterWin {
            w = .master(m)
        } else if editorOpen {
            w = .editor
        } else if channel == .mix && mixerOpen {
            w = .mixer
        }
        var g: GridPage? = nil
        if fxMode { g = .fx } else if modMode { g = .mod }
        return UndoPlace(channel: channel, trackId: t.id, clip: t.open, page: viewPage, window: w, arrange: arrangeView,
                         grid: g)
    }

    /// Показать место правки (перед UNDO / REDO). Уже там — ничего.
    func showUndoPlace(_ any: Any?) {
        guard let p = any as? UndoPlace else { return }
        if p == undoPlaceNow() { return }
        if p.channel == .track {
            if let i = project.tracks.firstIndex(where: { $0.id == p.trackId }) {
                if channel != .track || selectedTrack != i { select(track: i) }
                if project.tracks[i].open != p.clip && p.clip >= 0 && p.clip < project.tracks[i].clips.count {
                    openClip(i, p.clip)
                }
            }
        } else if channel != p.channel {
            select(channel: p.channel)
        }
        showUndoWindow(p)
        showUndoGrid(p.grid)
        let last: Int = max(0, seq.pages.count - 1)
        viewPage = max(0, min(p.page, last))
    }

    /// Окно места: лишние закрыть, нужное открыть (теми же функциями, что кнопки).
    private func showUndoWindow(_ p: UndoPlace) {
        let w: UndoWindow = p.window
        if rollView && w != .roll { closeRoll() }
        if patternView && w != .patterns { togglePatterns() }
        if eqView && w != .eq { toggleEqView() }
        if editorOpen && w != .editor { closeEditor() }
        if mixerOpen && w != .mixer { mixerOpen = false }
        if channel == .master, let m = masterWin, w != .master(m) { closeMasterWindow() }
        if arrangeView && !p.arrange { closeArrange() }
        if !arrangeView && p.arrange && w != .patterns && w != .eq && w != .editor { toggleArrange() }
        switch w {
        case .main:
            break
        case .patterns:
            if !patternView { togglePatterns() }
        case .roll:
            if !rollView { toggleRoll() }
        case .eq:
            if !eqView { toggleEqView() }
        case .editor:
            if !editorOpen && channel == .track { openEditor() }
        case .master(let m):
            if channel == .master && masterWin != m { openMasterWindow(m) }
        case .mixer:
            if channel == .mix && !mixerOpen { mixerOpen = true }
        }
    }

    /// FX / MOD на сетке ручек: только кнопки в режиме toggle (удержание без пальца не держится).
    private func showUndoGrid(_ g: GridPage?) {
        guard channel == .track else { return }
        for page in [GridPage.fx, GridPage.mod] where latched(page) {
            let want: Bool = g == page
            if pageOn(page) != want { setPageHeld(page, want) }
        }
    }
}
