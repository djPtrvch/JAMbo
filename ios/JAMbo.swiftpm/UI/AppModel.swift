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
    /// Зажатые шаги (индекс p·16 + s) — белый контур.
    var heldSteps: Set<Int> = []
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
        project.bpm = bpm
        audio.core.events.push(.tempo(bpm))
    }

    // MARK: — правки

    private func edit(_ change: (inout Project) -> Void) {
        change(&project)
        audio.core.publish(project)
    }

    var track: Track { return project.tracks[selectedTrack] }

    /// Ноты трига: выбранные в пианоролле (S1c), иначе корневая нота октавы.
    var trigNotes: [Int] {
        return [12 * (octave + 1) + project.root]
    }

    func toggleStep(_ index: Int) {
        guard channel == .track else { return }
        let notes = trigNotes
        edit { p in
            let pg = index / Params.stepsPerPage
            let s = index % Params.stepsPerPage
            var step = p.tracks[selectedTrack].pages[pg][s]
            if step.on {
                step = Step()
            } else {
                step.on = true
                if step.notes.isEmpty { step.notes = notes }
            }
            p.tracks[selectedTrack].pages[pg][s] = step
        }
    }

    /// Протягивание: триг на шаге index длиной len шагов.
    func setNoteLength(_ index: Int, _ len: Int) {
        guard channel == .track else { return }
        let notes = trigNotes
        edit { p in
            let pg = index / Params.stepsPerPage
            let s = index % Params.stepsPerPage
            var step = p.tracks[selectedTrack].pages[pg][s]
            if !step.on {
                step.on = true
                if step.notes.isEmpty { step.notes = notes }
            }
            step.len = max(1, len)
            p.tracks[selectedTrack].pages[pg][s] = step
        }
    }

    /// Удержание первого шага и двойной тап по другому: он становится последним шагом паттерна.
    func setPatternLength(lastIndex: Int) {
        guard channel == .track else { return }
        edit { p in p.tracks[selectedTrack].length = lastIndex + 1 }
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
