import Foundation
import Observation

/// Что выбрано в строке дорожек: дорожка, канал микшера MIX или мастер MST.
enum Channel: Equatable {
    case track
    case mix
    case master
}

/// Состояние интерфейса и проекта. Аудио меняется только через события (AudioCore.events) и снимки паттернов.
@Observable
final class AppModel {
    let audio = AudioHost()
    /// Ход игры из колбэка (позиции шагов, мигание) — отдельно, чтобы не перерисовывать всё.
    let live = LiveState()
    private(set) var project = Project()
    private(set) var selectedTrack: Int = 0
    private(set) var channel: Channel = .track
    var viewPage: Int = 0
    private(set) var playing: Bool = false
    private(set) var metronome: Bool = false
    private(set) var toneOn: Bool = false
    var showDiagnostics: Bool = false
    /// Зажатые шаги (индекс p·16 + s) — белый контур; с ними ручки ставят p-lock.
    var heldSteps: Set<Int> = []
    /// Зажатые шаги, на которых уже что-то сделали (p-lock) — триг на отпускании не переключается.
    @ObservationIgnored var usedSteps: Set<Int> = []
    /// Зажата SHIFT.
    var shiftHeld: Bool = false
    /// Скопированные страницы (copy в меню страницы).
    @ObservationIgnored var pageClipboard: [[Step]]? = nil
    /// Октава пианоролла (по умолчанию со второй: C2) — нота трига, пока нот не выбрали.
    var octave: Int = 2
    private(set) var appearance: Appearance = AppModel.loadAppearance()
    private var audioStarted: Bool = false
    @ObservationIgnored private var pump: Timer?

    init() {
        trace("model init")
        audio.core.publish(project)
        audio.core.events.push(.tempo(project.bpm))
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.drain()
        }
        RunLoop.main.add(timer, forMode: .common)
        pump = timer
    }

    // MARK: — звук

    /// Звук запускается первым касанием (и при возврате из фона).
    func ensureAudio() {
        if audioStarted { return }
        audioStarted = true
        audio.start()
    }

    /// Приложение стало активным: возврат из фона (первый запуск звука — первым касанием, как в вебе).
    func activate() {
        if audioStarted { audio.start() }
    }

    func pauseAudio() {
        if audioStarted { audio.stop() }
    }

    func toggleTone() {
        ensureAudio()
        toneOn.toggle()
        audio.core.events.push(.tone(on: toneOn))
    }

    /// Сообщения колбэка → состояние интерфейса (60 раз в секунду).
    private func drain() {
        audio.core.releaseRetired()
        live.drain(audio.core.sequencer.out, now: Date.timeIntervalSinceReferenceDate)
    }

    // MARK: — транспорт

    func togglePlay() {
        ensureAudio()
        playing.toggle()
        live.stopped()
        audio.core.events.push(.play(playing))
    }

    func toggleMetronome() {
        ensureAudio()
        metronome.toggle()
        audio.core.events.push(.metronome(metronome))
    }

    func setBpm(_ value: Double) {
        let bpm: Double = min(Params.bpmMax, max(Params.bpmMin, (value * 10).rounded() / 10))
        if bpm == project.bpm { return }
        edit { p in p.bpm = bpm }
        audio.core.events.push(.tempo(bpm))
    }

    // MARK: — правки и UNDO

    @ObservationIgnored var history = History<Project>()
    /// Есть что отменить или вернуть (для серых UNDO / REDO).
    private(set) var canUndo: Bool = false
    private(set) var canRedo: Bool = false

    /// Дискретное действие: одна запись в UNDO (внутри жеста — запись в конце жеста).
    func edit(_ change: (inout Project) -> Void) {
        let before = project
        change(&project)
        if project == before { return }
        history.record(before: before, after: project)
        changed()
    }

    /// Непрерывный жест (поворот ручки, протягивание, BPM): одна запись на весь жест.
    func beginGesture() {
        history.beginGesture(project)
    }

    func endGesture() {
        history.endGesture(project)
        refreshHistory()
    }

    func undo() {
        guard let prev = history.undo(project) else { return }
        restore(prev)
    }

    func redo() {
        guard let next = history.redo(project) else { return }
        restore(next)
    }

    /// Вернуть проект к снимку: что сейчас играет (остановленные дорожки), UNDO не меняет.
    private func restore(_ snap: Project) {
        var p = snap
        for i in 0..<p.tracks.count {
            if let cur = project.tracks.first(where: { $0.id == p.tracks[i].id }) { p.tracks[i].stopped = cur.stopped }
        }
        let bpmChanged = p.bpm != project.bpm
        project = p
        heldSteps.removeAll()
        selectedTrack = min(selectedTrack, project.tracks.count - 1)
        viewPage = min(viewPage, track.pages.count - 1)
        if bpmChanged { audio.core.events.push(.tempo(project.bpm)) }
        changed()
    }

    private func changed() {
        audio.core.publish(project)
        refreshHistory()
    }

    private func refreshHistory() {
        if canUndo != history.canUndo { canUndo = history.canUndo }
        if canRedo != history.canRedo { canRedo = history.canRedo }
    }

    var track: Track { return project.tracks[selectedTrack] }

    /// Ноты трига: выбранные в пианоролле (S1c), иначе корневая нота октавы.
    var trigNotes: [Int] {
        return [12 * (octave + 1) + project.root]
    }

    /// Правка выбранной дорожки.
    func editTrack(_ change: (inout Track) -> Void) {
        let i = selectedTrack
        edit { p in change(&p.tracks[i]) }
    }

    func select(track i: Int) {
        guard i < project.tracks.count else { return }
        selectedTrack = i
        channel = .track
        heldSteps.removeAll()
        viewPage = min(viewPage, project.tracks[i].pages.count - 1)
    }

    func select(channel c: Channel) {
        channel = c
        heldSteps.removeAll()
    }

    /// Свайп по дорожке: вниз — mute, вверх — solo; включённый mute или solo выключается любым свайпом.
    func swipe(track i: Int, down: Bool) {
        edit { p in
            if p.tracks[i].mute || p.tracks[i].solo {
                p.tracks[i].mute = false
                p.tracks[i].solo = false
            } else if down {
                p.tracks[i].mute = true
            } else {
                p.tracks[i].solo = true
            }
        }
    }

    // MARK: — тема

    func setAppearance(_ value: Appearance) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance")
    }

    private static func loadAppearance() -> Appearance {
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? ""
        return Appearance(rawValue: raw) ?? .system
    }
}

/// Ход игры: позиция шага каждой дорожки, мигание дорожек, доля метронома.
@Observable
final class LiveState {
    private(set) var playPos: [Int] = [Int](repeating: -1, count: Params.maxTracks)
    private(set) var flashing: [Bool] = [Bool](repeating: false, count: Params.maxTracks)
    /// Доля от старта (для полосы фазы и мигания метронома); −1 — стоп.
    private(set) var beat: Int = -1
    private(set) var beatFlash: Bool = false
    private(set) var beatAccent: Bool = false
    @ObservationIgnored private var flashUntil: [Double] = [Double](repeating: 0, count: Params.maxTracks)
    @ObservationIgnored private var beatUntil: Double = 0

    func drain(_ queue: SPSCQueue<SeqOut>, now: Double) {
        while let e = queue.pop() {
            switch e {
            case .none:
                break
            case .step(let t, let pos):
                if playPos[t] != pos { playPos[t] = pos }
            case .trig(let t, _):
                flashUntil[t] = now + 0.09
                if !flashing[t] { flashing[t] = true }
            case .beat(let accent):
                beat += 1
                beatAccent = accent
                beatFlash = true
                beatUntil = now + 0.09
            }
        }
        for t in 0..<Params.maxTracks where flashing[t] && now >= flashUntil[t] {
            flashing[t] = false
        }
        if beatFlash && now >= beatUntil { beatFlash = false }
    }

    func stopped() {
        beat = -1
        beatFlash = false
    }
}
