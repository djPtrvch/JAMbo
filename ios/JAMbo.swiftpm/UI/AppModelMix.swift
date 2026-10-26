import Foundation

// Переход MIX между проектами (S10, как switchWithTransition, setCrossfade, updateTransition веба): клипы старого
// проекта — в строке PREV внизу сетки, кроссфейдер ведёт общие настройки от старого проекта к новому, переход
// кончается, когда кроссфейдер у NEW и из PREV ничего не играет и не ждёт запуска. Модель — Core/Model/Transition.

extension AppModel {
    static let prevRow = Params.patternSlots - 1

    /// MIX из списка PROJECTS: проект в том виде, в каком сохранён SAVE.
    func mixProject(id: String) {
        let store = projects
        guard let f = saveQueue.sync(execute: { store.load(id) }) else {
            refreshProjects()
            return
        }
        session = ProjectSession.open(f, store: store)
        UserDefaults.standard.set(session.id, forKey: AppModel.currentKey)
        startMix(f.doc)
        projectChanged()
        refreshProjects()
    }

    /// Начать переход к next (и во время игры, и без неё). CROSSFADER OFF — общие настройки сразу нового проекта, но
    /// при игре модули мастера и EQ мастера — старого, пока игра идёт (globalsHold, решение пользователя).
    func startMix(_ next: Project) {
        // Аранжировщик (S15): переход MIX — все дорожки в сетку паттернов.
        audio.core.events.push(.leaveArrange)
        let last = AppModel.prevRow
        let leaving: [Bool] = (0..<Params.maxTracks).map { live.queued[$0] == Launcher.stop }
        let top: Int = gridWindow.top
        // CROSSFADER OFF: клипы PREV звучат с громкостью своих старых дорожек (решение пользователя).
        let made: (Project, MixTransition) = project.mixed(into: next, playing: playing, leaving: leaving,
                                                           clipVolumes: !settings.mixCrossfader)
        var tr = made.1
        if !settings.mixCrossfader { tr.pos = 1 }
        // Откуда клипы опускаются (строка окна сетки; ниже окна — с нижней строки).
        var drop: [Int: Int] = [:]
        for m in tr.moves { drop[m.track] = min(gridRowsShown - 1, max(0, m.from - top)) }
        resetForProject()
        keyHold = playing && !settings.mixKey
        bpmHold = playing && !settings.mixCrossfader ? next.bpm : nil
        globalsHold = playing && !settings.mixCrossfader ? tr.to : nil
        mix = tr
        mutatePlay({ p in p = made.0 }, publish: false)
        // Голоса играют дальше на своих местах (у дорожек нового проекта свои id).
        rebindNext = true
        applyMix(tr.pos)
        // Колбэк берёт активные ячейки из снимка: играющие дорожки продолжают свой клип уже из строки PREV.
        if playing { audio.core.events.push(.adoptPlay) }
        loadSamples(project.sampleKeys)
        mixDrop = drop
        mixDropDone = drop.isEmpty
        if !drop.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000)
                self.mixDropDone = true
            }
        }
        trace("mix → \(session.name), prev \(project.tracks.filter { $0.clipFilled(last) }.count)")
    }

    /// Кроссфейдер: 0 — OLD (внизу), 1 — NEW (вверху).
    func setCrossfade(_ pos: Double) {
        guard mix != nil else { return }
        applyMix(min(1, max(0, pos)))
    }

    /// Общие настройки проекта — смесь (без UNDO); параметры мастера — колбэку; темп — в колбэк.
    private func applyMix(_ pos: Double) {
        guard var tr = mix else { return }
        tr.pos = pos
        mix = tr
        var b: MixBlend = tr.blend(pos)
        // CROSSFADER OFF во время игры: громкость выхода, модули мастера (параметры, BYPASS) и EQ мастера — старого
        // проекта; громкости дорожек — у каждого клипа своего проекта (решение пользователя).
        let held: Bool = globalsHold != nil
        if held { b.globals.holdMaster(tr.from) }
        // CROSSFADER OFF во время игры: темп — старого проекта.
        if bpmHold != nil { b.globals.bpm = tr.from.bpm }
        let bpm0: Double = project.bpm
        mutatePlay({ p in b.globals.apply(to: &p) }, publish: false)
        mixMaster = pos >= 1 || held ? nil : b.master
        publishAudio()
        if project.bpm != bpm0 { audio.core.events.push(.tempo(project.bpm)) }
    }

    /// Каждый кадр: конец перехода — строка PREV уступает место последней строке нового проекта.
    func updateMix() {
        guard let tr = mix else { return }
        let last = AppModel.prevRow
        if tr.pos < 1 || project.prevPlaying { return }
        if live.queued.contains(last) || live.sceneRow == last || live.sceneQueued == last { return }
        mutatePlay({ p in p.endMix(tr) }, publish: true)
        mix = nil
        mixMaster = nil
        mixDrop = [:]
        history.reset()
        refreshHistory()
        if selectedTrack >= project.tracks.count { select(track: project.tracks.count - 1) }
        gridTop = min(gridTop, gridWindow.maxTop)
        viewPage = min(viewPage, seq.pages.count - 1)
        trace("mix end")
    }

    /// Проект для SAVE, SAVE AS, EXPORT и пометки unsaved: во время перехода — новый проект без PREV; темп старого
    /// проекта не пишется. CROSSFADER OFF во время игры: мастер — тот, что звучит (старого проекта; решение
    /// пользователя: сохранённые проекты сами не меняются).
    var savedProject: Project {
        var p = project.forSave(mix)
        if globalsHold != nil {
            var cur = MixGlobals(p)
            cur.holdMaster(MixGlobals(project))
            cur.apply(to: &p)
        }
        if let b = bpmHold { p.bpm = b }
        return p
    }

    /// Проект для autosave: мастер — нового проекта (каким станет после остановки).
    var autosavedProject: Project {
        var p = project.forSave(mix)
        if let g = globalsHold {
            var cur = MixGlobals(p)
            cur.holdMaster(g)
            cur.apply(to: &p)
        }
        if let b = bpmHold { p.bpm = b }
        return p
    }

    /// Игра остановилась: гамма и нота больше не держатся; темп, мастер и EQ мастера — нового проекта.
    func releaseHolds() {
        keyHold = false
        if let g = globalsHold {
            globalsHold = nil
            // Только мастер: громкости и выход уже нового проекта (правки во время игры остаются).
            var cur = MixGlobals(project)
            cur.holdMaster(g)
            mutatePlay({ p in cur.apply(to: &p) }, publish: true)
        }
        guard let b = bpmHold else { return }
        bpmHold = nil
        if project.bpm != b {
            mutatePlay({ p in p.bpm = b }, publish: true)
            audio.core.events.push(.tempo(b))
        }
    }

    /// Ячейка строки PREV (во время перехода): пустую не создать, в неё не вставить и не перетащить.
    func isPrev(_ k: Int) -> Bool {
        return mix != nil && k == AppModel.prevRow
    }
}
