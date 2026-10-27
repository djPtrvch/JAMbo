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
    /// Огибающие сэмплов SOURCE для иконки GRANULAR (по ключу сэмпла; ключ — по содержимому, правка — новый ключ).
    @ObservationIgnored var grainPeakCache: [String: [Double]] = [:]
    private(set) var selectedTrack: Int = 0 {
        didSet { updateGrainSeconds() }
    }
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
    /// Пасхалка: панда вместо полос уровня в окне MIX (SHIFT + тап по окну; не в проекте).
    var pandaShown: Bool = false
    /// Зажата FX: ручки — общие эффекты; MOD — LFO1–3 и ENV дорожки; из двух — нажатая последней.
    var fxHeld: Bool = false
    var modHeld: Bool = false
    var lastPage: GridPage = .fx
    /// Зажатые LFO1–3 (1–3) и ENV (4); нажатая последней.
    var heldSources: Set<Int> = []
    var lastSource: Int = 1
    /// Ручки, которые сейчас держит палец (обводка кнопок назначенных источников).
    var knobFingers: Set<Int> = []
    /// Картинка FX в окне сэмпла: колонка (0–3) ручки FX, тронутой последней; поворот ручки FX с MIDI — показ на 0,5 с.
    var fxPicCol: Int = 0
    var fxMidiShow: Bool = false
    @ObservationIgnored var fxMidiTask: Task<Void, Never>? = nil
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
    /// Первый тап по MORPH с зажатой SHIFT (второй за 0,35 с — ALL TRACKS вкл./выкл.).
    @ObservationIgnored var lastMorphShiftTap: Date? = nil
    /// Последний тап по LFO1–3 / ENV (двойной тап — снять назначение с удерживаемой ручки).
    @ObservationIgnored var lastSourceTap: (source: Int, at: Date)? = nil
    /// Открытое меню страницы (двойной тап по миниатюре).
    var pageMenu: PageMenuState? = nil
    /// Скопированные страницы (copy в меню страницы).
    @ObservationIgnored var pageClipboard: [[Step]]? = nil
    /// Октава клавиатуры у каждой дорожки своя (по умолчанию у всех одна — со второй: C2; не в проекте) — нота трига,
    /// пока нот не выбрали; от неё же — ноты маркеров нарезки дорожки.
    var octaves: [Int] = [Int](repeating: Scales.octaveDef, count: Params.maxTracks)
    /// Октава клавиатуры выбранной дорожки.
    /// Не выше topOctave: при смене ноты, гаммы, CHORD или числа октав — сама опускается.
    var octave: Int { return min(octaves[selectedTrack], topOctave) }
    /// Настройки приложения (клавиатура, запись) — в UserDefaults, общие для проектов.
    private(set) var settings: AppSettings = AppModel.loadSettings()
    /// REC: ноты клавиатуры пишутся в секвенсор, пока идёт игра.
    var recOn: Bool = false
    /// AUTO в аранжировщике: окно автоматизации; REC + PLAY + AUTO при игре по таймлайну — запись ручек в кривые.
    var arrAuto: Bool = false
    /// Кнопка записи аранжировки под STEPS сетки: пока играет сетка, запуски клипов пишутся на таймлайн блоками.
    var arrRecArm: Bool = false
    /// Игра по таймлайну (PLAY в окне аранжировщика): сетка и аранжировщик разделены — клипы в сетке не запускаются.
    var arrPlay: Bool = false
    /// Ручка, кривая которой открыта в окне AUTO (id параметра).
    var arrAutoId: String = ""
    /// Запись ручек в аранжировку (S15f3): кусок на ручку (ключ — дорожка·ArrAutoTarget.count + цель), кривые под рукой,
    /// отложенный конец куска (энкодер MIDI — без касания).
    @ObservationIgnored var autoTakes: [Int: AutoTake] = [:]
    @ObservationIgnored var autoHeld: Set<Int> = []
    /// Ручка под пальцем → её кривая (снять удержание и при смене режима до отпускания).
    @ObservationIgnored var autoSlotKeys: [Int: Int] = [:]
    @ObservationIgnored var autoFlush: DispatchWorkItem? = nil
    /// У каждой дорожки свои режим аккордов, прогрессия и выбранные ноты (не в проекте).
    var chordMode: [Bool] = [Bool](repeating: false, count: Params.maxTracks)
    var progression: [Int] = [Int](repeating: 0, count: Params.maxTracks)
    var selNotes: [[Int]] = [[Int]](repeating: [], count: Params.maxTracks)
    /// Зажатые клавиши и аккорды: касание → ноты.
    var pressedKeys: [Int: [Int]] = [:]
    /// Сетка паттернов открыта; ячейка для правки выбранной дорожки (жёлтый контур); верх окна строк.
    var patternView: Bool = false
    /// Аранжировщик (S15) на месте центра: открыт; курсор без игры (шаги); выбранный блок; меню; вид (масштаб, прокрутка).
    var arrangeView: Bool = false
    var arrCursor: Int = 0
    var arrSel: ArrSel? = nil
    /// Выделение рамкой (S15, решение пользователя): блоки на разных дорожках (от двух) и рамка, пока её тянут.
    var arrGroup: [ArrSel] = []
    var arrMarquee: CGRect? = nil
    /// KNOBS (под UNDO): в аранжировщике на месте таймлайна — окно дорожки с ручками (запись ручек — REC + PLAY + AUTO).
    var arrKnobs: Bool = false
    /// Высота строки дорожек, секвенсора и клавиатуры: окно AUTO поверх низа аранжировщика при выключенной STEPS.
    var arrLowerH: CGFloat = 0
    /// Высота строки кнопок (RootView.units): строка папки, вторая строка аранжировщика, верх EQ и окон мастера.
    var barH: CGFloat = 40
    var arrMenu: ArrMenuState? = nil
    var arrPort: ArrPort = ArrPort()
    /// INSERT (S15d): режим вставки; только что вставленный блок (его правый край — длина со сдвигом).
    var arrInsert: Bool = false
    var arrInserted: ArrSel? = nil
    /// REF (S15g): A/B (true — слышен референс; не хранится в проекте), огибающая файла для строки REF.
    var arrRefB: Bool = false
    /// EXPORT SONG (AppModelSongExport): формат, ход, экспорт в работе.
    var songFormat: SongFormat = SongFormat()
    var songExport: SongExportState = SongExportState()
    @ObservationIgnored var songExporter: SongExporter? = nil
    var refWave: RefWave? = nil
    /// Файл, темп которого уже ищется (второй поиск не запускается).
    @ObservationIgnored var refBpmKey: String = ""
    @ObservationIgnored var arrBlockClipboard: ArrBlock? = nil
    /// Рамка измерителя справа в окне дорожки («root»): в аранжировщике он стоит ровно там же и того же размера.
    @ObservationIgnored var meterFrame: CGRect = .zero
    @ObservationIgnored var arrTrackClipboard: [ArrBlock]? = nil
    /// Пианоролл на месте центра (S8): открыт, меню бутерброда, режим VEL.
    var rollView: Bool = false
    var rollMenuOpen: Bool = false
    var rollVel: Bool = true
    /// EQ на месте центра (EQ выбранной дорожки, при MIX и MST — мастера); выбранная полоса (−1 — нет); меню полосы.
    var eqView: Bool = false
    var eqBand: Int = -1
    /// LISTEN держат; полоса, которую слушают (−1 — нет).
    var eqListenHeld: Bool = false
    var eqListenBand: Int = -1
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
    /// Сравнение у каждой дорожки своё: id дорожки → id сравниваемой (спектр после её EQ); меню выбора.
    var eqCompares: [Int: Int] = [:]
    var eqCompareMenu: Bool = false
    /// Коррекция наушников: окно открыто вместо EQ мастера (тап по MASTER EQ), её полосы и пресеты — своя настройка
    /// приложения, не проекта (UserDefaults).
    var eqPhones: Bool = false
    var phonesEq: Eq = AppModel.loadPhonesEq()
    var phonesPresets: EqPresetBook = AppModel.loadPhonesPresets()
    /// Имя профиля коррекции (последний загруженный или импортированный пресет) — имя файла EXPORT.
    var phonesName: String = UserDefaults.standard.string(forKey: AppModel.phonesNameKey) ?? "Phones EQ"
    /// IMPORT профилей коррекции (тот же fileImporter, текстовые файлы); итог импорта — окно с OK.
    var importingPhones: Bool = false
    var phonesNote: String? = nil
    /// EXPORT: готовый временный файл профиля (окно сохранения в «Файлы»).
    var phonesExported: URL? = nil
    var gridTop: Int = 0
    /// Открытые меню сетки: ячейки (свайп вверх), строки (удержание), бутерброд сетки.
    var cellMenu: CellMenuState? = nil
    var rowMenu: Int? = nil
    /// Выделение рамкой в сетке паттернов (строки и клипы) — для TO ARRANGE.
    var gridSel = GridSelection()
    /// Строк в окне сетки паттернов: 8; STEPS выключена — сколько поместится той же высоты (RootView).
    var gridRowsShown: Int = Params.gridRows
    /// Перенос клипа из сетки на кнопку ARRANGE и в аранжировку (AppModelCarry); палец — в координатах «root».
    var clipCarry: ClipCarry? = nil
    var carryPoint: CGPoint = .zero
    /// Выделение, положенное поверх блоков, — ждёт выбора в меню (HERE, INSERT, TO END): что и с какого шага.
    var arrDropPending: (sel: GridSelection, start: Int)? = nil
    /// Рамки кнопки ARRANGE и таймлайна аранжировщика (координаты «root»).
    @ObservationIgnored var arrangeButtonFrame: CGRect = .zero
    @ObservationIgnored var arrTimelineFrame: CGRect = .zero
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
    /// CROSSFADER OFF (решение пользователя): громкость выхода, модули мастера и EQ мастера старого проекта держатся,
    /// пока идёт игра (громкости дорожек — у клипов своего проекта); здесь — настройки нового проекта (для записи и
    /// после остановки).
    @ObservationIgnored var globalsHold: MixGlobals? = nil
    /// Следующий снимок звука — после MIX: голоса остаются на своих местах (SoundData.rebind).
    @ObservationIgnored var rebindNext: Bool = false
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
    /// Capture: ноты, сыгранные без REC, по дорожкам; ▲ ▼ мигают после Capture.
    @ObservationIgnored var captureLog: [[CapturedKey]] = [[CapturedKey]](repeating: [], count: Params.maxTracks)
    var captureFlash: Bool = false
    private(set) var appearance: Appearance = AppModel.loadAppearance()
    /// Сэмплы (в памяти и на диске); растёт при загрузке — окна перерисовываются.
    @ObservationIgnored let store = SampleStore()
    /// Таблицы WTABLE (строятся в фоне при первом использовании, дальше — из кэша).
    @ObservationIgnored let wavetables = WavetableStore(userDir: WtWav.appDir())
    /// Последняя готовая таблица каждой дорожки (звучит, пока новая строится).
    @ObservationIgnored var heldTables: [Int: WtTable] = [:]
    /// Таблицы, по готовности которых снимок звука публикуется заново.
    @ObservationIgnored var pendingTables: Set<String> = []
    /// Таблица достроилась — перерисовать кадр в окне синта.
    var wavetableSerial = 0
    var samplesVersion: Int = 0
    /// Редактор сэмпла (на месте центра), меню звука (для дорожки или зажатых шагов), выбор файлов.
    var editorOpen: Bool = false
    /// Редактор в режиме WARP (метки варпинга вместо маркеров нарезки) и его GRID (в четвертях: 1/16 — 0,25).
    var editorWarp: Bool = false
    var warpGrid: Double = 0.25
    /// Выделенная метка варпинга (её тянут и из любого места полосы флажков).
    var warpSel: Int? = nil
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
    /// Предупреждение импорта в библиотеку (архив больше предела, пропущенные большие файлы) — окно с OK.
    var libWarning: String? = nil
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
    /// Свои значения ручек по умолчанию (UserDefaults) и ручка, на которой на секунду видно SAVED.
    var knobDefaults: KnobDefaults = KnobDefaults.decode(UserDefaults.standard.data(forKey: AppModel.knobDefaultsKey))
    var defaultFlash: Int? = nil
    /// SAVE DEFAULT в PRESETS EQ или модуля мастера — на секунду SAVED жёлтым.
    var defaultSaved: DefaultSaved? = nil

    init() {
        trace("model init")
        project = startProject()
        installSynth()
        wavetables.preloadBuiltins()
        syncTapSensor()
        startMidi()
        publishAudio()
        audio.core.phones.publish(phonesEq)
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

    /// Уход в фон: BACKGROUND AUDIO включён — звук играет дальше (запись входа всё равно кончается), иначе — пауза.
    func enterBackground() {
        if settings.backgroundAudio {
            endInputRecForBackground()
        } else {
            pauseAudio()
        }
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
        // Аранжировщик (S15): PLAY в его окне — дорожки по таймлайну с курсора; стоп — курсор остаётся, где был.
        if playing {
            // Петля включена — PLAY в аранжировщике играет её сначала.
            let a: Arrangement = project.arrange
            var from: Int = arrangeView && a.loop && a.hasLoop ? a.loopFrom : arrCursor
            // Курсор за концом аранжировки (ушёл при игре из сетки) — с начала, иначе игра сразу кончается.
            if arrangeView && !(a.loop && a.hasLoop) && project.arrangeEnd > 0 && from >= project.arrangeEnd {
                from = 0
                arrCursor = 0
            }
            arrPlay = arrangeView
            audio.core.events.push(.arrange(on: arrangeView, from: from))
            live.stopped()
            live.begin(project, arrange: arrangeView)
            syncArrRecord(from: from)
        } else {
            arrCursor = live.arrPos
            arrPlay = false
            syncArrRecord()
            live.stopped()
        }
        audio.core.events.push(.play(playing))
        if !playing { releaseHolds() }
    }

    /// Старт по MIDI-клоку (S13e): шаг 0 — в кадре frame.
    func startPlay(atFrame frame: Int64) {
        if playing { return }
        ensureAudio()
        playing = true
        arrPlay = arrangeView
        endRecTake()
        live.stopped()
        live.begin(project, arrange: arrangeView)
        syncArrRecord(from: arrCursor)
        audio.core.events.push(.arrange(on: arrangeView, from: arrCursor))
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
                arrCursor = live.arrPos
                arrPlay = false
                syncArrRecord()
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
        arrGroup = []
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
        let oldIds: [Int] = project.tracks.map { $0.id }
        project = p
        if playing { followTrackOrder(oldIds) }
        heldSteps.removeAll()
        selectedTrack = min(selectedTrack, project.tracks.count - 1)
        viewPage = min(viewPage, seq.pages.count - 1)
        if bpmChanged { audio.core.events.push(.tempo(project.bpm)) }
        changed()
    }

    /// UNDO / REDO перестановки дорожек во время игры: ход дорожек в колбэке переезжает в новый порядок.
    private func followTrackOrder(_ oldIds: [Int]) {
        var cur: [Int] = oldIds
        let want: [Int] = project.tracks.map { $0.id }
        if cur.count != want.count || Set(cur) != Set(want) { return }
        for i in 0..<want.count {
            guard let j = cur.firstIndex(of: want[i]), j != i else { continue }
            let x: Int = cur.remove(at: j)
            cur.insert(x, at: i)
            audio.core.events.push(.moveTrack(from: j, to: i))
            live.moveTrack(j, i)
        }
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
        gridSel = GridSelection()
        clipCarry = nil
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
