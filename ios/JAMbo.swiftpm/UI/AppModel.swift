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
    private(set) var project = Project() {
        didSet { projectChanged() }
    }
    /// Проекты на диске; текущий проект (куда сохраняет SAVE, что сохранено); автосохранение — не раньше этого
    /// времени (0 — изменений нет), запись на диск — в своей очереди.
    @ObservationIgnored let projects = ProjectStore(dir: ProjectStore.appDir())
    var session = ProjectSession(id: "", name: "")
    @ObservationIgnored var autosaveDue: Double = 0
    @ObservationIgnored let saveQueue = DispatchQueue(label: "jambo.save", qos: .utility)
    /// Открытая вкладка SETTINGS (не в настройках: при запуске — первая, RECORD).
    var settingsTab: SettingsTab = .record
    /// Список проектов в меню PROJECTS (перечитывается при открытии меню и после действий).
    var projectList: [ProjectInfo] = []
    private(set) var selectedTrack: Int = 0
    private(set) var channel: Channel = .track
    var viewPage: Int = 0
    /// Секвенсор показывает все играющие страницы (если открытая среди них); удержание миниатюры — одну.
    var spanView: Bool = true
    private(set) var playing: Bool = false
    private(set) var metronome: Bool = false
    private(set) var toneOn: Bool = false
    /// Окно раздела APP поверх экрана: DIAGNOSTICS, SELF-TEST (nil — закрыто).
    var appWindow: AppWindow? = nil
    /// Зажатые шаги (индекс p·16 + s) — белый контур; с ними ручки ставят p-lock.
    var heldSteps: Set<Int> = []
    /// Зажатые шаги, на которых уже что-то сделали (p-lock) — триг на отпускании не переключается.
    @ObservationIgnored var usedSteps: Set<Int> = []
    /// Зажата SHIFT.
    var shiftHeld: Bool = false
    /// Зажата FX: ручки — общие эффекты; MOD — LFO1–3 и ENV дорожки; из двух — нажатая последней.
    var fxHeld: Bool = false
    var modHeld: Bool = false
    var lastPage: GridPage = .fx
    /// Зажатые LFO1–3 (1–3) и ENV (4); нажатая последней.
    var heldSources: Set<Int> = []
    var lastSource: Int = 1
    /// Ручки, которые сейчас держит палец (обводка кнопок назначенных источников).
    var knobFingers: Set<Int> = []
    /// MORPH: режим включён; кнопка зажата; на удержании нажали UNDO (отпускание не переключает режим).
    var morph: Bool = false
    var morphHeld: Bool = false
    var morphUsed: Bool = false
    /// Плавный возврат после выключения MORPH (SETTINGS → MORPH → RETURN; nil — нет).
    @ObservationIgnored var morphGlide: MorphGlide? = nil
    /// KEY VELOCITY (S12): толчки iPad (акселерометр).
    @ObservationIgnored let tapSensor = TapSensor()
    /// Кадры интерфейса и время drain (DIAGNOSTICS, S14a).
    @ObservationIgnored let frameMeter = FrameMeter()
    /// MIDI (S13): CoreMIDI, устройства.
    let midi = MidiHost()
    let midiLearn = MidiLearnState()
    @ObservationIgnored var midiRun = MidiRuntime()
    /// MIDI OUT дорожек (свой поток; создаётся с первым выходом — AppModelTrackMidi).
    @ObservationIgnored var midiOutPump: MidiOutPump? = nil
    /// Сэмплы, ноту которых уже определяли (AppModelRoots).
    @ObservationIgnored var rootTried: Set<String> = []
    /// Последний тап по FX или MOD с зажатой SHIFT (двойной — режим toggle кнопки).
    @ObservationIgnored var lastPageTap: (page: GridPage, at: Date)? = nil
    /// Последний тап по LFO1–3 / ENV (двойной тап — снять назначение с удерживаемой ручки).
    @ObservationIgnored var lastSourceTap: (source: Int, at: Date)? = nil
    /// Миниатюры LFO/ENV в окне сэмпла после поворота ручки MOD (до этого момента).
    var modPreviewUntil: Date = .distantPast
    /// Открытое меню страницы (двойной тап по миниатюре).
    var pageMenu: PageMenuState? = nil
    /// Скопированные страницы (copy в меню страницы).
    @ObservationIgnored var pageClipboard: [[Step]]? = nil
    /// Октава клавиатуры у каждой дорожки своя (по умолчанию у всех одна — со второй: C2; не в проекте) — нота трига,
    /// пока нот не выбрали; от неё же — ноты маркеров нарезки дорожки.
    var octaves: [Int] = [Int](repeating: Scales.octaveDef, count: Params.maxTracks)
    /// Октава клавиатуры выбранной дорожки.
    var octave: Int { return octaves[selectedTrack] }
    /// Настройки приложения (клавиатура, запись) — в UserDefaults, общие для проектов.
    private(set) var settings: AppSettings = AppModel.loadSettings()
    /// REC: ноты клавиатуры пишутся в секвенсор, пока идёт игра.
    var recOn: Bool = false
    /// У каждой дорожки свои режим аккордов, прогрессия и выбранные ноты (не в проекте).
    var chordMode: [Bool] = [Bool](repeating: false, count: Params.maxTracks)
    var progression: [Int] = [Int](repeating: 0, count: Params.maxTracks)
    var selNotes: [[Int]] = [[Int]](repeating: [], count: Params.maxTracks)
    /// Зажатые клавиши и аккорды: касание → ноты.
    var pressedKeys: [Int: [Int]] = [:]
    /// Сетка паттернов открыта; ячейка для правки выбранной дорожки (жёлтый контур); верх окна строк.
    var patternView: Bool = false
    /// Пианоролл на месте центра (S8): открыт, меню бутерброда, режим VEL.
    var rollView: Bool = false
    var rollMenuOpen: Bool = false
    var rollVel: Bool = true
    /// EQ на месте центра (EQ выбранной дорожки, при MIX и MST — мастера); выбранная полоса (−1 — нет); меню полосы.
    var eqView: Bool = false
    var eqBand: Int = -1
    var eqMenu: EqMenuState? = nil
    /// Меню STEREO / MID / SIDE: рамка поля M/S («root»); nil — закрыто.
    var eqMsMenu: CGRect? = nil
    /// Меню DYN (источник, THRESHOLD, RANGE): рамка поля DYN; ввод числом из меню (EqView открывает окно).
    var eqDynMenu: CGRect? = nil
    /// Сдвиг меню DYN пальцем (перетаскивание за заголовок); сбрасывается при открытии.
    var eqDynShift: CGSize = .zero
    var eqInputAsk: EqInput? = nil
    /// Меню PRESETS EQ (рамка кнопки и низ поля EQ, «root»); пресеты EQ — общие для каналов и проектов.
    var eqPresetMenu: EqPresetMenuState? = nil
    var eqPresets: EqPresetBook = AppModel.loadEqPresets()
    /// Сравнение у каждой дорожки своё: id дорожки → id сравниваемой (спектр после её EQ); меню выбора; спектр
    /// выхода у EQ мастера.
    var eqCompares: [Int: Int] = [:]
    var eqCompareMenu: Bool = false
    var eqOutOn: Bool = false
    var gridTop: Int = 0
    /// Открытые меню сетки: ячейки (свайп вверх), строки (удержание), бутерброд сетки.
    var cellMenu: CellMenuState? = nil
    var rowMenu: Int? = nil
    var gridMenuOpen: Bool = false
    /// Ячейка коротко вспыхивает красным (действие недоступно).
    var deniedCell: CellRef? = nil
    @ObservationIgnored var clipClipboard: Clip? = nil
    @ObservationIgnored var rowClipboard: RowClip? = nil
    /// Лидер (клип, запущенный последним): его гамма и нота — общие; дорожки, запущенные в этом кадре.
    @ObservationIgnored var lead: Int = 0
    @ObservationIgnored var startOrder: [Int] = [Int](repeating: 0, count: Params.maxTracks)
    @ObservationIgnored var startSeq: Int = 0
    @ObservationIgnored var pendingStarts: [Int] = []
    /// Переход MIX (S10): состояние (nil — нет перехода), параметры мастера кроссфейдера для колбэка (BYPASS — долей),
    /// CHANGE KEY OFF — гамма и нота старого проекта держатся, пока идёт игра.
    var mix: MixTransition? = nil
    @ObservationIgnored var mixMaster: [Double]? = nil
    @ObservationIgnored var keyHold: Bool = false
    /// CROSSFADER OFF: темп старого проекта держится, пока идёт игра; здесь — темп нового проекта (для записи).
    @ObservationIgnored var bpmHold: Double? = nil
    /// CROSSFADER OFF (решение пользователя): модули мастера и EQ мастера старого проекта держатся, пока идёт игра
    /// (громкости и выход — сразу нового); здесь — настройки нового проекта (для записи и после остановки).
    @ObservationIgnored var globalsHold: MixGlobals? = nil
    /// Следующие клипы дорожек в последнем снимке звука (nextSlots).
    @ObservationIgnored var publishedNext: [Int] = []
    /// Анимация MIX: клипы опускаются в PREV из строк окна (дорожка → строка окна), пока mixDropDone false.
    var mixDrop: [Int: Int] = [:]
    var mixDropDone: Bool = true
    /// Открытое меню выбора (SCALE, ROOT, PROGRESSION) и меню клавиатуры.
    var choice: ChoiceState? = nil
    var pianoMenuOpen: Bool = false
    /// Дубль записи: номер истории после первой ноты (−1 — дубля нет), дорожки и записанные шаги дубля.
    @ObservationIgnored var recTake: Int = -1
    @ObservationIgnored var takeTracks: Set<Int> = []
    @ObservationIgnored var takeWritten: Set<Int> = []
    @ObservationIgnored var lastRec: (track: Int, tick: Int) = (-1, -1)
    /// Зажатые клавиши: дорожка, ноты, записанный шаг (длина — при отпускании) и время нажатия.
    @ObservationIgnored var keyHolds: [Int: KeyHold] = [:]
    private(set) var appearance: Appearance = AppModel.loadAppearance()
    /// Сэмплы (в памяти и на диске); растёт при загрузке — окна перерисовываются.
    @ObservationIgnored let store = SampleStore()
    /// Таблицы WTABLE (строятся в фоне при первом использовании, дальше — из кэша).
    @ObservationIgnored let wavetables = WavetableStore(userDir: WtWav.appDir())
    /// Таблица достроилась — перерисовать кадр в окне синта.
    var wavetableSerial = 0
    var samplesVersion: Int = 0
    /// Редактор сэмпла (на месте центра), меню звука (для дорожки или зажатых шагов), выбор файлов.
    var editorOpen: Bool = false
    var soundMenu: SoundMenuState? = nil
    var importTarget: ImportTarget? = nil
    var importing: Bool = false
    /// Выбор файла — для IMPORT проекта (.jambo), а не сэмплов; итог IMPORT (меню PROJECTS показывает LOAD / MIX).
    var importingProject: Bool = false
    var projectImport: ProjectImport? = nil
    /// Браузер библиотеки (S11b) на месте центра: режим (nil — закрыт), дерево, открытая папка, выбор нескольких
    /// (nil — нет), строка внизу (что загружено, ошибка); выбор файлов — для IMPORT в библиотеку.
    var browser: BrowserMode? = nil
    var library: Library = Library()
    var libFolder: String = Library.root
    var libPicked: Set<String>? = nil
    var libNote: String = ""
    var importingLibrary: Bool = false
    @ObservationIgnored var libraryLoaded: Bool = false
    /// IMPORT таблиц WAV без метки размера кадра — по очереди спрашивается размер (S11b4).
    var libTableAsk: [TableImport] = []
    /// IMPORT: сколько пресетов добавлено (для строки внизу).
    @ObservationIgnored var libImportedPresets: Int = 0
    /// Сэмпл библиотеки на ▶ (в снимке звука — вне дорожек).
    @ObservationIgnored var libPreviewKey: String? = nil
    @ObservationIgnored let libraryStore = LibraryStore(url: LibraryStore.appFile())
    /// Рамка левой колонки (меню звука ложится на неё).
    var leftFrame: CGRect = .zero
    /// Колонка миниатюр страниц (в координатах «root») — по ней встаёт меню страницы.
    var pagesFrame: CGRect = .zero
    /// Звучащие голоса сэмплов (полоса воспроизведения): из колбэка; число — чтобы включать анимацию.
    @ObservationIgnored var heads: [Int: VoiceHead] = [:]
    var headCount: Int = 0
    /// Запись стемов (S11d): готовые и пишущиеся каналы (дорожки, StemRing.master) — не в проекте и не в UNDO.
    var stemArmed: Set<Int> = []
    var stemRecording: Set<Int> = []
    @ObservationIgnored let stems = StemCollector()
    @ObservationIgnored var stemNames: [Int: String] = [:]
    /// REC в редакторе сэмпла (S11e).
    let sampleRec = SampleRec()
    var previewOn: Bool = false
    /// Маркер нарезки, который держат в редакторе (не двигая): клавиша назначает ему ноту; отказ — красный.
    var heldFlag: Int? = nil
    /// Клавиша назначила ноту флажку, который держат (его отпускание — не тап).
    @ObservationIgnored var flagUsed: Bool = false
    var refusedFlag: (idx: Int, until: Double) = (-1, 0)
    /// MIX: меню дорожки у ручки громкости, переименование, скопированная дорожка.
    var trackMenu: TrackMenuState? = nil
    var renaming: Int? = nil
    @ObservationIgnored var trackClipboard: Track? = nil
    var hasTrackClip: Bool = false
    private var audioStarted: Bool = false
    @ObservationIgnored private var pump: Timer?
    /// Измеритель и метры MIX (читают виды по таймеру анимации; не наблюдается).
    @ObservationIgnored let meters = MeterState()
    /// Индикация COMP / CLIP / LIM при MST.
    @ObservationIgnored let dynMeters = MasterMeters()
    /// Скоп мастера: точки съёма SAT (всегда), COMP, CLIP, LIM (по умолчанию выключены — отличие от веба; в проекте
    /// не хранится).
    @ObservationIgnored let scope = ScopeState()
    var scopeOn: [Bool] = [true, false, false, false]
    /// Окно модуля мастера на месте центра (MasterScope.sat…lim; nil — закрыто) и его меню (название, PRESETS);
    /// ввод числом или имени пресета. Открытость и FREEZE не в проекте.
    var masterWin: Int? = nil
    var masterMenu: MasterMenuState? = nil
    var masterInput: MasterInputTarget? = nil
    /// Пресеты модулей мастера — общие для проектов (UserDefaults).
    var masterPresets: MasterPresetBook = AppModel.loadMasterPresets()

    init() {
        trace("model init")
        project = startProject()
        installSynth()
        syncTapSensor()
        startMidi()
        publishAudio()
        audio.core.events.push(.tempo(project.bpm))
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.drain()
        }
        RunLoop.main.add(timer, forMode: .common)
        pump = timer
        // Замеры S14a — всё время (DIAGNOSTICS закрывает экран): время колбэка по разделам, кадры интерфейса.
        audio.core.profile.enabled = true
        frameMeter.start()
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
        endInputRecForBackground()
        if audioStarted { audio.stop() }
    }

    func toggleTone() {
        ensureAudio()
        toneOn.toggle()
        audio.core.events.push(.tone(on: toneOn))
    }

    /// Сообщения колбэка → состояние интерфейса (60 раз в секунду).
    private func drain() {
        let t0: Double = Date.timeIntervalSinceReferenceDate
        defer { frameMeter.drained(Date.timeIntervalSinceReferenceDate - t0) }
        audio.core.releaseRetired()
        defer { applyPendingLead() }
        if autosaveDue > 0 && Date.timeIntervalSinceReferenceDate >= autosaveDue { autosave() }
        if morphGlide != nil { stepMorphGlide() }
        if mix != nil { updateMix() }
        drainVoices()
        drainStems()
        tickMeters()
        tickMidiFeedback()
        tickMidiClock()
        tickClockFollow()
        tickMidiOut()
        let tracks = project.tracks.count
        live.audible = { [weak self] t in
            guard let s = self, t < tracks else { return false }
            return s.project.audible(t)
        }
        live.drain(audio.core.sequencer.out, now: Date.timeIntervalSinceReferenceDate, onStep: { [weak self] t, pos in
            self?.recPassStep(t, pos)
        }, onPlay: { [weak self] e in
            self?.playEvent(e)
        })
        // Звук у клипа: колбэку — звук клипа, который дорожка запустит следующей (ожидание, строка).
        if nextSlots != publishedNext { publishAudio() }
    }

    // MARK: — транспорт

    func togglePlay() {
        ensureAudio()
        // PLAY во время записи стемов: клипы доигрывают проход, стемы дописываются, затем стоп (.ended).
        if playing && !stemRecording.isEmpty {
            audio.core.events.push(.stopAfterStems)
            return
        }
        playing.toggle()
        endRecTake()
        live.stopped()
        audio.core.events.push(.play(playing))
        if !playing { releaseHolds() }
    }

    /// Старт по MIDI-клоку (S13e): шаг 0 — в кадре frame.
    func startPlay(atFrame frame: Int64) {
        if playing { return }
        ensureAudio()
        playing = true
        endRecTake()
        live.stopped()
        audio.core.events.push(.playAt(frame: frame))
    }

    /// Ход игры из колбэка: клип запущен или дорожка остановлена; транспорт остановился сам (AT THE END: STOP).
    func playEvent(_ e: SeqOut) {
        switch e {
        case .clip(let t, let slot, let stopped, _):
            guard t < project.tracks.count else { return }
            // Другой клип — снимок звука заново: нарезка звучит в гамме и ноте этого клипа.
            let other: Bool = project.tracks[t].slot != slot
            mutatePlay({ p in
                if p.tracks[t].slot != slot { p.tracks[t].activate(slot) }
                p.tracks[t].stopped = stopped
            }, publish: other)
            if stopped {
                leadStopped(t)
            } else {
                started(t)
            }
            if t == selectedTrack {
                heldSteps.removeAll()
                viewPage = min(viewPage, seq.pages.count - 1)
            }
        case .ended:
            if playing {
                playing = false
                releaseHolds()
                endRecTake()
                live.stopped()
            }
        default:
            break
        }
    }

    func toggleMetronome() {
        ensureAudio()
        metronome.toggle()
        audio.core.events.push(.metronome(metronome))
    }

    /// Темп с MIDI-клока (S13e): BPM проекта — округлённый темп клока, без UNDO (звук идёт по точному — его шлёт
    /// AppModelSync).
    func setClockBpm(_ bpm: Double) {
        let b: Double = min(Params.bpmMax, max(Params.bpmMin, bpm.rounded()))
        if b != project.bpm { project.bpm = b }
    }

    func setBpm(_ value: Double) {
        let bpm: Double = min(Params.bpmMax, max(Params.bpmMin, (value * 10).rounded() / 10))
        if bpm == project.bpm { return }
        bpmHold = nil
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

    /// Ход игры (активная ячейка, остановка, гамма лидера) — не правка: без UNDO.
    func mutatePlay(_ change: (inout Project) -> Void, publish: Bool) {
        change(&project)
        if publish { publishAudio() }
    }

    /// Правка без новой записи в UNDO (продолжение дубля записи — UNDO отменяет весь дубль).
    func applyInTake(_ change: (inout Project) -> Void) {
        change(&project)
        publishAudio()
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
            // Что играет, UNDO не меняет: активная ячейка и остановка — как сейчас.
            if let cur = project.tracks.first(where: { $0.id == p.tracks[i].id }) {
                p.tracks[i].stopped = cur.stopped
                if p.tracks[i].clipFilled(cur.slot) || cur.blank { p.tracks[i].moveSlot(cur.slot) }
                p.tracks[i].open = cur.open
                // Звук — по активной ячейке (клип со своим звуком — его).
                p.tracks[i].settleSound()
            }
        }
        let bpmChanged = p.bpm != project.bpm
        project = p
        heldSteps.removeAll()
        selectedTrack = min(selectedTrack, project.tracks.count - 1)
        viewPage = min(viewPage, seq.pages.count - 1)
        if bpmChanged { audio.core.events.push(.tempo(project.bpm)) }
        changed()
    }

    func changed() {
        publishAudio()
        refreshHistory()
    }

    /// LOAD и NEW (S9c, как loadDoc веба): проект целиком вместо текущего. Игра останавливается (отличие от веба:
    /// во время игры — переход MIX, S10), UNDO сбрасывается, окна закрываются, выбрана первая дорожка.
    func loadProject(_ p: Project) {
        if playing {
            playing = false
            audio.core.events.push(.play(false))
        }
        mix = nil
        mixMaster = nil
        keyHold = false
        bpmHold = nil
        globalsHold = nil
        mixDrop = [:]
        live.stopped()
        resetForProject()
        project = p
        audio.core.events.push(.tempo(p.bpm))
        publishAudio()
        loadSamples(p.sampleKeys)
    }

    /// Другой проект (LOAD, NEW, MIX): окна и меню закрываются, UNDO сбрасывается, выбрана первая дорожка.
    func resetForProject() {
        endRecTake()
        morphGlide = nil
        morph = false
        closeEditor()
        closeMasterWindow()
        closeRoll()
        closeBrowser()
        eqView = false
        eqMenu = nil
        eqMsMenu = nil
        eqDynMenu = nil
        eqPresetMenu = nil
        pageMenu = nil
        soundMenu = nil
        trackMenu = nil
        cellMenu = nil
        rowMenu = nil
        gridMenuOpen = false
        history.reset()
        refreshHistory()
        selectedTrack = 0
        channel = .track
        viewPage = 0
        gridTop = 0
        heldSteps.removeAll()
        heldSources.removeAll()
        lead = 0
        startOrder = [Int](repeating: 0, count: Params.maxTracks)
        pendingStarts.removeAll()
    }

    func refreshHistory() {
        if canUndo != history.canUndo { canUndo = history.canUndo }
        if canRedo != history.canRedo { canRedo = history.canRedo }
    }

    var track: Track { return project.tracks[selectedTrack] }

    /// Действие ручки на другом месте (глобальный MIDI-маппинг, S13): на время body сетка ручек «показывает» place —
    /// страницу и дорожку, без зажатых шагов (p-lock не ставится) и MORPH; затем всё возвращается. Интерфейс видит
    /// только итог (всё — в одном проходе главного потока).
    func withKnobPlace(_ place: MidiPlace, _ body: () -> Void) {
        guard place.page == .mix || place.page == .master || place.track < project.tracks.count else { return }
        let saved = (selectedTrack, channel, fxHeld, modHeld, lastPage, heldSteps, morph)
        switch place.page {
        case .mix: channel = .mix
        case .master: channel = .master
        default:
            channel = .track
            selectedTrack = place.track
        }
        fxHeld = place.page == .fx
        modHeld = place.page == .mod
        lastPage = place.page == .mod ? .mod : .fx
        heldSteps = []
        morph = false
        body()
        (selectedTrack, channel, fxHeld, modHeld, lastPage, heldSteps, morph) = saved
    }

    /// Последовательность в секвенсоре и миниатюрах: выбранная дорожка, при MIX и MST — их свои (Project.chanSeqs).
    var seq: Track {
        switch channel {
        case .track: return track
        case .mix: return project.chanSeqs[Project.mixSeq]
        case .master: return project.chanSeqs[Project.mstSeq]
        }
    }

    /// Правка показанной последовательности.
    func editSeq(_ change: (inout Track) -> Void) {
        switch channel {
        case .track: editTrack(change)
        case .mix: edit { p in change(&p.chanSeqs[Project.mixSeq]) }
        case .master: edit { p in change(&p.chanSeqs[Project.mstSeq]) }
        }
    }

    /// Страницы в секвенсоре: несколько играющих — все подряд (16 × N шагов в один ряд), иначе открытая.
    var viewPages: ClosedRange<Int> {
        let t = seq
        let v: Int = max(0, min(viewPage, t.pages.count - 1))
        if spanView && t.playTo > t.playFrom && t.playTo < t.pages.count && t.playFrom <= v && v <= t.playTo {
            return t.playFrom...t.playTo
        }
        return v...v
    }

    /// Ячейка для правки выбранной дорожки (жёлтый контур): её клип открыт в секвенсоре и миниатюрах страниц.
    var editSlot: Int { return track.open }

    /// Открыть клип k дорожки i для правки (не правка проекта — без UNDO).
    func openClip(_ i: Int, _ k: Int) {
        guard i < project.tracks.count, project.tracks[i].open != k else { return }
        mutatePlay({ p in p.tracks[i].open = k }, publish: false)
        if i == selectedTrack {
            heldSteps.removeAll()
            viewPage = project.tracks[i].clipRange(k)?.lowerBound ?? 0
        }
    }

    /// Позиция играющего шага в открытом клипе выбранной дорожки (−1 — открыт не играющий клип); при MIX и MST —
    /// шаг их последовательности.
    var openPlayPos: Int {
        if channel == .mix { return live.playPos[SeqData.maxTracks + Project.mixSeq] }
        if channel == .master { return live.playPos[SeqData.maxTracks + Project.mstSeq] }
        return trackPlayPos
    }

    /// Позиция играющего шага в открытом клипе выбранной дорожки (и при MIX, MST — клавиатура, окно синта).
    var trackPlayPos: Int {
        let t = track
        if t.open != t.slot { return -1 }
        return live.playPos[selectedTrack]
    }

    /// Ноты трига: выбранные на клавиатуре (S1c), иначе корневая нота октавы.
    var trigNotes: [Int] {
        let sel = selNotes[selectedTrack]
        return sel.isEmpty ? [Scales.baseNote(root: project.root, octave: octave)] : sel.sorted()
    }

    /// Правка выбранной дорожки.
    func editTrack(_ change: (inout Track) -> Void) {
        let i = selectedTrack
        edit { p in change(&p.tracks[i]) }
    }

    /// Номер выбранной дорожки после правки списка (удаление, перестановка).
    func selectTrackIndex(_ i: Int) {
        selectedTrack = max(0, min(i, project.tracks.count - 1))
        heldSteps.removeAll()
        viewPage = min(viewPage, seq.pages.count - 1)
    }

    func select(track i: Int) {
        guard i < project.tracks.count else { return }
        selectedTrack = i
        channel = .track
        closeMasterWindow()
        heldSteps.removeAll()
        viewPage = min(viewPage, project.tracks[i].pages.count - 1)
    }

    func select(channel c: Channel) {
        channel = c
        heldSteps.removeAll()
        viewPage = min(viewPage, seq.pages.count - 1)
        // При MST на месте LFO1–3 и ENV — кнопки мастера: удержание источника не остаётся висеть.
        if c == .master { heldSources.removeAll() }
        // Выход из MST закрывает окно модуля мастера.
        if c != .master { closeMasterWindow() }
    }

    /// Свайп по дорожке: вниз — mute, вверх — solo; включённый mute или solo выключается любым свайпом.
    func swipe(track i: Int, down: Bool) {
        guard i < project.tracks.count else { return }
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

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        UserDefaults.standard.set(settings.encode(), forKey: "settings")
        syncTapSensor()
    }

    /// Акселерометр работает, только пока KEY VELOCITY включён.
    func syncTapSensor() {
        if settings.velocity { tapSensor.start() } else { tapSensor.stop() }
    }

    private static func loadSettings() -> AppSettings {
        return AppSettings.decode(UserDefaults.standard.data(forKey: "settings"))
    }

    private static func loadAppearance() -> Appearance {
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? ""
        return Appearance(rawValue: raw) ?? .system
    }
}
