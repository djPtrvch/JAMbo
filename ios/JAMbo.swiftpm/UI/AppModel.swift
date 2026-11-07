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
    // Свойства простых типов — вручную, без макроса (AppModelObserved.swift): put — запись с уведомлением, как
    // withMutation макроса; observedChanged — изменилось ли значение (AppModelObserved.swift).
    func put<T>(_ key: KeyPath<AppModel, T>, _ slot: ReferenceWritableKeyPath<AppModel, T>, _ value: T, _ notify: Bool) {
        if notify {
            _$observationRegistrar.willSet(self, keyPath: key)
            self[keyPath: slot] = value
            _$observationRegistrar.didSet(self, keyPath: key)
        } else {
            self[keyPath: slot] = value
        }
    }

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
    @ObservationIgnored var _settingsTab: SettingsTab = .record
    /// Список проектов в меню PROJECTS (перечитывается при открытии меню и после действий).
    var projectList: [ProjectInfo] = []
    /// Огибающие сэмплов SOURCE для иконки GRANULAR (по ключу сэмпла; ключ — по содержимому, правка — новый ключ).
    @ObservationIgnored var grainPeakCache: [String: [Double]] = [:]
    /// Стерео ли дорожка на метрах (trackStereo; по индексу дорожки) — до следующей правки проекта.
    @ObservationIgnored var stereoCache: [Int: Bool] = [:]
    /// TRIM, NORMALIZE, MONO: какая часть прежнего сэмпла (доли длины) стала копией — редактор переводит на неё
    /// масштаб и место (SampleEditor, смена ключа); nil — смена сэмпла не правкой.
    @ObservationIgnored var editorRemap: (Double, Double)? = nil
    /// Держат флажок нарезки: последняя клавиша (маркер, нота, время) — второй тап той же клавиши снимает ноту.
    @ObservationIgnored var flagKeyTap: (idx: Int, note: Int, t: Double) = (-1, -1, 0)
    /// Запись библиотеки после правки нарезки или варпинга уже назначена (одна на секунду, не на каждое движение).
    @ObservationIgnored var marksSaveDue: Bool = false
    private(set) var selectedTrack: Int = 0 {
        didSet { updateGrainSeconds() }
    }
    @ObservationIgnored private var _channel: Channel = .track
    private(set) var channel: Channel {
        get { access(keyPath: \.channel); return _channel }
        set { put(\.channel, \._channel, newValue, observedChanged(_channel, newValue)) }
    }
    @ObservationIgnored var _viewPage: Int = 0
    /// Секвенсор показывает все играющие страницы (если открытая среди них); удержание миниатюры — одну.
    @ObservationIgnored var _spanView: Bool = true
    @ObservationIgnored private var _playing: Bool = false
    private(set) var playing: Bool {
        get { access(keyPath: \.playing); return _playing }
        set { put(\.playing, \._playing, newValue, observedChanged(_playing, newValue)) }
    }
    @ObservationIgnored private var _metronome: Bool = false
    private(set) var metronome: Bool {
        get { access(keyPath: \.metronome); return _metronome }
        set { put(\.metronome, \._metronome, newValue, observedChanged(_metronome, newValue)) }
    }
    @ObservationIgnored private var _toneOn: Bool = false
    private(set) var toneOn: Bool {
        get { access(keyPath: \.toneOn); return _toneOn }
        set { put(\.toneOn, \._toneOn, newValue, observedChanged(_toneOn, newValue)) }
    }
    /// Окно раздела APP поверх экрана: DIAGNOSTICS (nil — закрыто).
    @ObservationIgnored var _appWindow: AppWindow? = nil
    /// Зажатые шаги (индекс p·16 + s) — белый контур; с ними ручки ставят p-lock.
    @ObservationIgnored var _heldSteps: Set<Int> = []
    /// Зажатые шаги, на которых уже что-то сделали (p-lock) — триг на отпускании не переключается.
    @ObservationIgnored var usedSteps: Set<Int> = []
    /// Зажата SHIFT.
    @ObservationIgnored var _shiftHeld: Bool = false
    /// Зажата FX: ручки — общие эффекты; MOD — LFO1–3 и ENV дорожки; из двух — нажатая последней.
    @ObservationIgnored var _fxHeld: Bool = false
    @ObservationIgnored var _modHeld: Bool = false
    @ObservationIgnored var _lastPage: GridPage = .fx
    /// Зажатые LFO1–3 (1–3) и ENV (4); нажатая последней.
    @ObservationIgnored var _heldSources: Set<Int> = []
    @ObservationIgnored var _lastSource: Int = 1
    /// Ручки, которые сейчас держит палец (обводка кнопок назначенных источников).
    @ObservationIgnored var _knobFingers: Set<Int> = []
    /// Картинка FX в окне сэмпла: колонка (0–3) ручки FX, тронутой последней; поворот ручки FX с MIDI — показ на 0,5 с.
    @ObservationIgnored var _fxPicCol: Int = 0
    @ObservationIgnored var _fxMidiShow: Bool = false
    @ObservationIgnored var fxMidiTask: LaterTask? = nil
    /// MORPH: режим включён; кнопка зажата; на удержании нажали UNDO (отпускание не переключает режим).
    @ObservationIgnored var _morph: Bool = false
    @ObservationIgnored var _morphHeld: Bool = false
    @ObservationIgnored var _morphUsed: Bool = false
    /// MORPH → MODE HOLD: SHIFT + MORPH держат — все дорожки (отпустили — MORPH выключается).
    @ObservationIgnored var _morphAllHeld: Bool = false
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
    /// Последний тап по LFO1–3 / ENV (двойной тап — снять назначение с удерживаемой ручки).
    @ObservationIgnored var lastSourceTap: (source: Int, at: Date)? = nil
    /// Открытое меню страницы (двойной тап по миниатюре).
    @ObservationIgnored var _pageMenu: PageMenuState? = nil
    /// Скопированные страницы (copy в меню страницы).
    @ObservationIgnored var pageClipboard: [[Step]]? = nil
    /// Октава клавиатуры у каждой дорожки своя (по умолчанию у всех одна — со второй: C2; не в проекте) — нота трига,
    /// пока нот не выбрали; от неё же — ноты маркеров нарезки дорожки.
    @ObservationIgnored var _octaves: [Int] = [Int](repeating: Scales.octaveDef, count: Params.maxTracks)
    /// Октава клавиатуры выбранной дорожки.
    /// Не выше topOctave: при смене ноты, гаммы, CHORD или числа октав — сама опускается.
    var octave: Int { return min(octaves[selectedTrack], topOctave) }
    /// Настройки приложения (клавиатура, запись) — в UserDefaults, общие для проектов.
    private(set) var settings: AppSettings = AppModel.loadSettings()
    /// REC: ноты клавиатуры пишутся в секвенсор, пока идёт игра.
    @ObservationIgnored var _recOn: Bool = false
    /// AUTO в аранжировщике: окно автоматизации; REC + PLAY + AUTO при игре по таймлайну — запись ручек в кривые.
    @ObservationIgnored var _arrAuto: Bool = false
    /// Кнопка записи аранжировки под STEPS сетки: пока играет сетка, запуски клипов пишутся на таймлайн блоками.
    @ObservationIgnored var _arrRecArm: Bool = false
    /// Докуда при игре можно прокрутить таймлайн (шаги; 0 — не играет): плейхед за концом аранжировки (arrViewEnd).
    @ObservationIgnored var _arrPlayEnd: Int = 0
    /// Конец таймлайна для прокрутки: аранжировка или место плейхеда при игре.
    var arrViewEnd: Int { return max(project.arrangeEnd, arrPlayEnd) }
    /// ARRANGE зажата (с тапом REC — запись аранжировки; отпустили без REC — обычный тап).
    @ObservationIgnored var arrangeHeld: Bool = false
    @ObservationIgnored var arrangeHoldUsed: Bool = false
    /// Игра по таймлайну (PLAY в окне аранжировщика): сетка и аранжировщик разделены — клипы в сетке не запускаются.
    @ObservationIgnored var _arrPlay: Bool = false
    /// Карандаш под измерителем аранжировщика (решение пользователя): рисование кривой в окне AUTO пальцем.
    @ObservationIgnored var _arrDraw: Bool = false
    /// Ручка, кривая которой открыта в окне AUTO (id параметра).
    @ObservationIgnored var _arrAutoId: String = ""
    /// Запись ручек в аранжировку (S15f3): кусок на ручку (ключ — дорожка·ArrAutoTarget.count + цель), кривые под рукой,
    /// отложенный конец куска (энкодер MIDI — без касания).
    @ObservationIgnored var autoTakes: [Int: AutoTake] = [:]
    @ObservationIgnored var autoHeld: Set<Int> = []
    /// Ручка под пальцем → её кривая (снять удержание и при смене режима до отпускания).
    @ObservationIgnored var autoSlotKeys: [Int: Int] = [:]
    @ObservationIgnored var autoFlush: DispatchWorkItem? = nil
    /// У каждой дорожки свои режим аккордов, прогрессия и выбранные ноты (не в проекте).
    @ObservationIgnored var _chordMode: [Bool] = [Bool](repeating: false, count: Params.maxTracks)
    /// Тип аккорда клавиш в режиме CHORD (Scales.chordKinds: Triad, 7th, 9th, sus2, sus4, add9) — у каждой дорожки
    /// свой; живёт до закрытия приложения (в проекте не хранится).
    @ObservationIgnored var _chordKind: [Int] = [Int](repeating: 0, count: Params.maxTracks)
    /// Окно CHORD (долгое нажатие на CHORD): тип аккорда и пресеты прогрессий.
    @ObservationIgnored var _chordMenuOpen: Bool = false
    /// Последняя случайная прогрессия (SHIFT + CHORD) — следующая будет другой.
    @ObservationIgnored var lastRandomProgression: [Int]? = nil
    /// Настройки арпеджиатора, уже отправленные в колбэк (по номеру дорожки).
    @ObservationIgnored var sentArp: [TrackArp?] = [TrackArp?](repeating: nil, count: SeqData.maxTracks)
    /// Тик последней ноты арпеджио дорожки (при игре на шаг пишется одна нота); касания Capture нот арпеджио.
    @ObservationIgnored var lastArpTick: [Int] = [Int](repeating: Int.min, count: SeqData.maxTracks)
    @ObservationIgnored var arpCaptureId: Int = -2_000_000_000
    /// Шаги основы прошлого случайного ритма по id дорожки (SHIFT + CHORD на ударном движке).
    @ObservationIgnored var lastRandomDrums: [Int: [Int]] = [:]
    @ObservationIgnored var _selNotes: [[Int]] = [[Int]](repeating: [], count: Params.maxTracks)
    /// Зажатые клавиши и аккорды: касание → ноты.
    @ObservationIgnored var _pressedKeys: [Int: [Int]] = [:]
    /// Сетка паттернов открыта; ячейка для правки выбранной дорожки (жёлтый контур); верх окна строк.
    @ObservationIgnored var _patternView: Bool = false
    /// Аранжировщик (S15) на месте центра: открыт; курсор без игры (шаги); выбранный блок; меню; вид (масштаб, прокрутка).
    @ObservationIgnored var _arrangeView: Bool = false
    @ObservationIgnored var _arrCursor: Int = 0
    @ObservationIgnored var _arrSel: ArrSel? = nil
    /// Выделение рамкой (S15, решение пользователя): блоки на разных дорожках (от двух) и рамка, пока её тянут.
    @ObservationIgnored var _arrGroup: [ArrSel] = []
    @ObservationIgnored var _arrMarquee: CGRect? = nil
    /// KNOBS (под UNDO): в аранжировщике на месте таймлайна — окно дорожки с ручками (запись ручек — REC + PLAY + AUTO).
    @ObservationIgnored var _arrKnobs: Bool = false
    /// Высота строки дорожек, секвенсора и клавиатуры: окно AUTO поверх низа аранжировщика при выключенной STEPS.
    @ObservationIgnored var _arrLowerH: CGFloat = 0
    /// Высота строки кнопок (RootView.units): строка папки, вторая строка аранжировщика, верх EQ и окон мастера.
    @ObservationIgnored var _barH: CGFloat = 40
    @ObservationIgnored var _arrMenu: ArrMenuState? = nil
    var arrPort: ArrPort = ArrPort()
    /// INSERT (S15d): режим вставки; только что вставленный блок (его правый край — длина со сдвигом).
    @ObservationIgnored var _arrInsert: Bool = false
    @ObservationIgnored var _arrInserted: ArrSel? = nil
    /// REF (S15g): A/B (true — слышен референс; не хранится в проекте), огибающая файла для строки REF.
    @ObservationIgnored var _arrRefB: Bool = false
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
    @ObservationIgnored var _rollView: Bool = false
    @ObservationIgnored var _rollMenuOpen: Bool = false
    @ObservationIgnored var _rollVel: Bool = true
    /// EQ на месте центра (EQ выбранной дорожки, при MIX и MST — мастера); выбранная полоса (−1 — нет); меню полосы.
    @ObservationIgnored var _eqView: Bool = false
    @ObservationIgnored var _eqBand: Int = -1
    /// LISTEN держат; полоса, которую слушают (−1 — нет).
    @ObservationIgnored var _eqListenHeld: Bool = false
    @ObservationIgnored var _eqListenBand: Int = -1
    @ObservationIgnored var _eqMenu: EqMenuState? = nil
    /// Меню STEREO / MID / SIDE: рамка поля M/S («root»); nil — закрыто.
    @ObservationIgnored var _eqMsMenu: CGRect? = nil
    /// Меню TRANSLATION (тап по полю в окне коррекции наушников): рамка поля («root»).
    @ObservationIgnored var _translationMenu: CGRect? = nil
    /// Меню DYN (источник, THRESHOLD, RANGE): рамка поля DYN; ввод числом из меню (EqView открывает окно).
    @ObservationIgnored var _eqDynMenu: CGRect? = nil
    /// Сдвиг меню DYN пальцем (перетаскивание за заголовок); сбрасывается при открытии.
    @ObservationIgnored var _eqDynShift: CGSize = .zero
    @ObservationIgnored var _eqInputAsk: EqInput? = nil
    /// Меню PRESETS EQ (рамка кнопки и низ поля EQ, «root»); пресеты EQ — общие для каналов и проектов.
    @ObservationIgnored var _eqPresetMenu: EqPresetMenuState? = nil
    var eqPresets: EqPresetBook = AppModel.loadEqPresets()
    /// Сравнение у каждой дорожки своё: id дорожки → id сравниваемой (спектр после её EQ); меню выбора.
    @ObservationIgnored var _eqCompares: [Int: Int] = [:]
    @ObservationIgnored var _eqCompareMenu: Bool = false
    /// Коррекция наушников: окно открыто вместо EQ мастера (тап по MASTER EQ), её полосы и пресеты — своя настройка
    /// приложения, не проекта (UserDefaults).
    @ObservationIgnored var _eqPhones: Bool = false
    var phonesEq: Eq = AppModel.loadPhonesEq()
    var phonesPresets: EqPresetBook = AppModel.loadPhonesPresets()
    /// Имя профиля коррекции (последний загруженный или импортированный пресет) — имя файла EXPORT.
    @ObservationIgnored var _phonesName: String = UserDefaults.standard.string(forKey: AppModel.phonesNameKey) ?? "Phones EQ"
    /// IMPORT профилей коррекции (тот же fileImporter, текстовые файлы); итог импорта — окно с OK.
    @ObservationIgnored var _importingPhones: Bool = false
    @ObservationIgnored var _phonesNote: String? = nil
    /// Headphone Monitor (AppModelMonitor): настройки цепочки, Trim по профилям, пресеты Translation, громкость файла
    /// референса (LUFS) и подгонка к миксу, dB.
    var monitor: MonitorSettings = AppModel.loadMonitor()
    var phonesTrims: [String: [Double]] = AppModel.loadTrims()
    @ObservationIgnored let translations: [TranslationPreset] = AppModel.loadTranslations()
    @ObservationIgnored var refLufs: (key: String, lufs: Double)? = nil
    @ObservationIgnored var refLufsPending: String = ""
    @ObservationIgnored var refMatchDb: Double = 0
    /// EXPORT: готовый временный файл профиля (окно сохранения в «Файлы»).
    @ObservationIgnored var _phonesExported: URL? = nil
    @ObservationIgnored var _gridTop: Int = 0
    /// Открытые меню сетки: ячейки (свайп вверх), строки (удержание), бутерброд сетки.
    @ObservationIgnored var _cellMenu: CellMenuState? = nil
    @ObservationIgnored var _rowMenu: Int? = nil
    /// Выделение рамкой в сетке паттернов (строки и клипы) — для TO ARRANGE.
    var gridSel = GridSelection()
    /// Строк в окне сетки паттернов: 8; STEPS выключена — сколько поместится той же высоты (RootView).
    @ObservationIgnored var _gridRowsShown: Int = Params.gridRows
    /// Перенос клипа из сетки на кнопку ARRANGE и в аранжировку (AppModelCarry); палец — в координатах «root».
    @ObservationIgnored var _clipCarry: ClipCarry? = nil
    @ObservationIgnored var _carryPoint: CGPoint = .zero
    /// Выделение, положенное поверх блоков, — ждёт выбора в меню (HERE, INSERT, TO END): что и с какого шага.
    @ObservationIgnored var _arrDropPending: (sel: GridSelection, start: Int)? = nil
    /// Рамки кнопки ARRANGE и таймлайна аранжировщика (координаты «root»).
    @ObservationIgnored var arrangeButtonFrame: CGRect = .zero
    /// Рамки кнопок верхней панели («root»): по ним выравниваются строки окон EQ и библиотеки.
    var topFrames: TopFrames = TopFrames()
    @ObservationIgnored var arrTimelineFrame: CGRect = .zero
    @ObservationIgnored var _gridMenuOpen: Bool = false
    /// Ячейка коротко вспыхивает красным (действие недоступно).
    @ObservationIgnored var _deniedCell: CellRef? = nil
    @ObservationIgnored var clipClipboard: Clip? = nil
    @ObservationIgnored var rowClipboard: RowClip? = nil
    /// Лидер (клип, запущенный последним): его гамма и нота — общие; дорожки, запущенные в этом кадре.
    @ObservationIgnored var lead: Int = 0
    @ObservationIgnored var startOrder: [Int] = [Int](repeating: 0, count: Params.maxTracks)
    @ObservationIgnored var startSeq: Int = 0
    @ObservationIgnored var pendingStarts: [Int] = []
    /// Переход MIX (S10): состояние (nil — нет перехода), параметры мастера кроссфейдера для колбэка (BYPASS — долей),
    /// CHANGE KEY OFF — гамма и нота старого проекта держатся, пока идёт игра.
    @ObservationIgnored var _mix: MixTransition? = nil
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
    @ObservationIgnored var _mixDrop: [Int: Int] = [:]
    @ObservationIgnored var _mixDropDone: Bool = true
    /// Открытое меню выбора (SCALE, ROOT) и меню клавиатуры.
    @ObservationIgnored var _choice: ChoiceState? = nil
    @ObservationIgnored var _pianoMenuOpen: Bool = false
    /// Дубль записи: номер истории после первой ноты (−1 — дубля нет), дорожки и записанные шаги дубля.
    @ObservationIgnored var recTake: Int = -1
    @ObservationIgnored var takeTracks: Set<Int> = []
    @ObservationIgnored var takeWritten: Set<Int> = []
    @ObservationIgnored var lastRec: (track: Int, tick: Int) = (-1, -1)
    /// Зажатые клавиши: дорожка, ноты, записанный шаг (длина — при отпускании) и время нажатия.
    @ObservationIgnored var keyHolds: [Int: KeyHold] = [:]
    /// Capture: ноты, сыгранные без REC, по дорожкам; ▲ ▼ мигают после Capture.
    @ObservationIgnored var captureLog: [[CapturedKey]] = [[CapturedKey]](repeating: [], count: Params.maxTracks)
    @ObservationIgnored var _captureFlash: Bool = false
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
    @ObservationIgnored var _wavetableSerial: Int = 0
    @ObservationIgnored var _samplesVersion: Int = 0
    /// Редактор сэмпла (на месте центра), меню звука (для дорожки или зажатых шагов), выбор файлов.
    @ObservationIgnored var _editorOpen: Bool = false
    /// Редактор в режиме WARP (метки варпинга вместо маркеров нарезки) и его GRID (в четвертях: 1/16 — 0,25).
    @ObservationIgnored var _editorWarp: Bool = false
    @ObservationIgnored var _warpGrid: Double = 0.25
    /// Выделенная метка варпинга (её тянут и из любого места полосы флажков).
    @ObservationIgnored var _warpSel: Int? = nil
    @ObservationIgnored var _soundMenu: SoundMenuState? = nil
    @ObservationIgnored var _importTarget: ImportTarget? = nil
    @ObservationIgnored var _importing: Bool = false
    /// Выбор файла — для IMPORT проекта (.jambo), а не сэмплов; итог IMPORT (меню PROJECTS показывает LOAD / MIX).
    @ObservationIgnored var _importingProject: Bool = false
    @ObservationIgnored var _projectImport: ProjectImport? = nil
    /// Браузер библиотеки (S11b) на месте центра: режим (nil — закрыт), дерево, открытая папка, выбор нескольких
    /// (nil — нет), строка внизу (что загружено, ошибка); выбор файлов — для IMPORT в библиотеку.
    @ObservationIgnored var _browser: BrowserMode? = nil
    var library: Library = Library()
    @ObservationIgnored var _libFolder: String = Library.root
    @ObservationIgnored var _libPicked: Set<String>? = nil
    @ObservationIgnored var _libNote: String = ""
    /// Предупреждение импорта в библиотеку (архив больше предела, пропущенные большие файлы) — окно с OK.
    @ObservationIgnored var _libWarning: String? = nil
    @ObservationIgnored var _importingLibrary: Bool = false
    @ObservationIgnored var libraryLoaded: Bool = false
    /// IMPORT таблиц WAV без метки размера кадра — по очереди спрашивается размер (S11b4).
    var libTableAsk: [TableImport] = []
    /// IMPORT: сколько пресетов добавлено (для строки внизу).
    @ObservationIgnored var libImportedPresets: Int = 0
    /// Сэмпл библиотеки на ▶ (в снимке звука — вне дорожек).
    @ObservationIgnored var libPreviewKey: String? = nil
    @ObservationIgnored let libraryStore = LibraryStore(url: LibraryStore.appFile())
    /// Рамка левой колонки (меню звука ложится на неё).
    @ObservationIgnored var _leftFrame: CGRect = .zero
    /// Колонка миниатюр страниц (в координатах «root») — по ней встаёт меню страницы.
    @ObservationIgnored var _pagesFrame: CGRect = .zero
    /// Клавиши клавиатуры (в координатах экрана): меню CHORD и бутерброда — от левого нижнего угла первой клавиши.
    @ObservationIgnored var _keysFrame: CGRect = .zero
    /// Строка дорожек (в координатах «root»): верх окна CHORD и предел меню бутерброда под CHORD.
    @ObservationIgnored var _tracksFrame: CGRect = .zero
    /// Звучащие голоса сэмплов (полоса воспроизведения): из колбэка; число — чтобы включать анимацию.
    @ObservationIgnored var heads: [Int: VoiceHead] = [:]
    @ObservationIgnored var _headCount: Int = 0
    /// Запись стемов (S11d): готовые и пишущиеся каналы (дорожки, StemRing.master) — не в проекте и не в UNDO.
    @ObservationIgnored var _stemArmed: Set<Int> = []
    @ObservationIgnored var _stemRecording: Set<Int> = []
    @ObservationIgnored let stems = StemCollector()
    @ObservationIgnored var stemNames: [Int: String] = [:]
    /// REC в редакторе сэмпла (S11e).
    let sampleRec = SampleRec()
    @ObservationIgnored var _previewOn: Bool = false
    /// Маркер нарезки, который держат в редакторе (не двигая): клавиша назначает ему ноту; отказ — красный.
    @ObservationIgnored var _heldFlag: Int? = nil
    /// Флажок держат 0,5 с, не двигая: в строке редактора — роли куска (LOW, MID, HIGH, LONG); сразу — не мешает
    /// перетаскиванию.
    @ObservationIgnored var _roleFlag: Int? = nil
    /// Номер удержания флажка (отложенный показ ролей — только для того же удержания).
    @ObservationIgnored var flagHoldId: Int = 0
    /// Клавиша назначила ноту флажку, который держат (его отпускание — не тап).
    @ObservationIgnored var flagUsed: Bool = false
    @ObservationIgnored var _refusedFlag: (idx: Int, until: Double) = (-1, 0)
    /// MIX: меню дорожки у ручки громкости, переименование, скопированная дорожка.
    @ObservationIgnored var _trackMenu: TrackMenuState? = nil
    @ObservationIgnored var _renaming: Int? = nil
    @ObservationIgnored var trackClipboard: Track? = nil
    @ObservationIgnored var _hasTrackClip: Bool = false
    @ObservationIgnored private var _audioStarted: Bool = false
    private var audioStarted: Bool {
        get { access(keyPath: \.audioStarted); return _audioStarted }
        set { put(\.audioStarted, \._audioStarted, newValue, observedChanged(_audioStarted, newValue)) }
    }
    @ObservationIgnored private var pump: Timer?
    /// Измеритель и метры MIX (читают виды по таймеру анимации; не наблюдается).
    @ObservationIgnored let meters = MeterState()
    /// Индикация COMP / CLIP / LIM при MST.
    @ObservationIgnored let dynMeters = MasterMeters()
    /// Скоп мастера: точки съёма SAT (всегда), COMP, CLIP, LIM (по умолчанию выключены — отличие от веба; в проекте
    /// не хранится).
    @ObservationIgnored let scope = ScopeState()
    @ObservationIgnored var _scopeOn: [Bool] = [true, false, false, false]
    /// Окно модуля мастера на месте центра (MasterScope.sat…lim; nil — закрыто) и его меню (название, PRESETS);
    /// ввод числом или имени пресета. Открытость и FREEZE не в проекте.
    @ObservationIgnored var _masterWin: Int? = nil
    @ObservationIgnored var _masterMenu: MasterMenuState? = nil
    @ObservationIgnored var _masterInput: MasterInputTarget? = nil
    /// Пресеты модулей мастера — общие для проектов (UserDefaults).
    var masterPresets: MasterPresetBook = AppModel.loadMasterPresets()
    /// Свои значения ручек по умолчанию (UserDefaults) и ручка, на которой на секунду видно SAVED.
    var knobDefaults: KnobDefaults = KnobDefaults.decode(UserDefaults.standard.data(forKey: AppModel.knobDefaultsKey))
    @ObservationIgnored var _defaultFlash: Int? = nil
    /// SAVE DEFAULT в PRESETS EQ или модуля мастера — на секунду SAVED жёлтым.
    @ObservationIgnored var _defaultSaved: DefaultSaved? = nil

    init() {
        trace("model init")
        project = startProject()
        installSynth()
        wavetables.preloadBuiltins()
        syncTapSensor()
        startMidi()
        publishAudio()
        publishMonitor()
        audio.core.events.push(.tempo(project.bpm))
        audio.core.events.push(.metronomeGain(Float(settings.metronomeVol / 100)))
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
        arrTrackPlayEnd()
        if arrangeView && playing { arrFollowPlayhead() }
        syncEditBlock()
        drainVoices()
        drainArp()
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
        live.stepAt = { [weak self] t, k, pos in
            guard let s = self, t < s.project.tracks.count, k >= 0, k < s.project.tracks[t].clips.count else { return nil }
            return s.project.tracks[t].clips[k]?.step(pos)
        }
        live.drain(audio.core.sequencer.out, now: Date.timeIntervalSinceReferenceDate, onStep: { [weak self] t, pos in
            self?.recPassStep(t, pos)
        }, onPlay: { [weak self] e in
            self?.playEvent(e)
        })
        // Запись аранжировки из сетки: mute и solo пишутся (заглушённый участок — пусто на таймлайне).
        if live.recorder.active { live.recordAudible(project, x: arrNowX) }
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
            // PLAY в окне ARRANGE — таймлайн (живая запись оттуда убрана — решение пользователя 2.11); запись аранжировки
            // из сетки — с плейхеда или с начала (SETTINGS → RECORD → ARRANGE REC START).
            let tl: Bool = arrangeView
            var from: Int = tl && a.loop && a.hasLoop ? a.loopFrom : arrCursor
            // Курсор за концом аранжировки (ушёл при игре из сетки) — с начала, иначе игра сразу кончается.
            if tl && !(a.loop && a.hasLoop) && project.arrangeEnd > 0 && from >= project.arrangeEnd {
                from = 0
                arrCursor = 0
            }
            if arrRecArm && !tl && settings.record.arrFromStart {
                from = 0
                arrCursor = 0
            }
            arrPlay = tl
            audio.core.events.push(.arrange(on: tl, from: from))
            live.stopped()
            live.begin(project, arrange: tl)
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
        let tl: Bool = arrangeView
        if arrRecArm && !tl && settings.record.arrFromStart { arrCursor = 0 }
        arrPlay = tl
        endRecTake()
        live.stopped()
        live.begin(project, arrange: tl)
        syncArrRecord(from: arrCursor)
        audio.core.events.push(.arrange(on: tl, from: arrCursor))
        audio.core.events.push(.playAt(frame: frame))
    }

    /// Ход игры из колбэка: клип запущен или дорожка остановлена; транспорт остановился сам (AT THE END: STOP).
    func playEvent(_ e: SeqOut) {
        switch e {
        case .clip(let t, let slot, let stopped, _):
            guard t < project.tracks.count else { return }
            // Ячейка блока аранжировки (своя копия клипа): активная ячейка сетки не меняется.
            if slot >= Params.patternSlots {
                if project.tracks[t].stopped != stopped { mutatePlay({ p in p.tracks[t].stopped = stopped }, publish: false) }
                if stopped { leadStopped(t) } else { started(t) }
                return
            }
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

    /// Громкость метронома, % (SETTINGS → RECORD); без UNDO — настройка приложения.
    func setMetronomeVol(_ v: Double) {
        let x: Double = Swift.min(200, Swift.max(0, v.rounded()))
        if x == settings.metronomeVol { return }
        updateSettings { $0.metronomeVol = x }
        audio.core.events.push(.metronomeGain(Float(x / 100)))
    }

    /// Темп с MIDI-клока (S13e): BPM проекта — округлённый темп клока, без UNDO (звук идёт по точному — его шлёт
    /// AppModelSync).
    func setClockBpm(_ bpm: Double) {
        let b: Double = min(Params.bpmMax, max(Params.bpmMin, bpm.rounded()))
        if b == project.bpm { return }
        project.bpm = b
        // WARP TO PROJECT BPM: BPM файла сэмплов с метками — новый темп.
        if settings.warpProjectBpm { publishAudio() }
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
    @ObservationIgnored private var _canUndo: Bool = false
    private(set) var canUndo: Bool {
        get { access(keyPath: \.canUndo); return _canUndo }
        set { put(\.canUndo, \._canUndo, newValue, observedChanged(_canUndo, newValue)) }
    }
    @ObservationIgnored private var _canRedo: Bool = false
    private(set) var canRedo: Bool {
        get { access(keyPath: \.canRedo); return _canRedo }
        set { put(\.canRedo, \._canRedo, newValue, observedChanged(_canRedo, newValue)) }
    }

    /// Дискретное действие: одна запись в UNDO (внутри жеста — запись в конце жеста).
    func edit(_ change: (inout Project) -> Void) {
        let before = project
        change(&project)
        // Новые блоки аранжировки (перенос из сетки, запись, вставка) — со своей копией клипа (решение пользователя).
        if AppModel.needsOwnPatterns(project) { project.ownArrPatterns() }
        if project == before { return }
        history.record(before: before, after: project)
        changed()
    }

    /// Есть блок аранжировки без своей копии клипа.
    static func needsOwnPatterns(_ p: Project) -> Bool {
        for t in p.tracks where t.blocks.contains(where: { $0.pattern == nil }) { return true }
        return false
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
                // Арпеджиатор — без UNDO (как ход игры): остаётся как сейчас.
                p.tracks[i].arp = cur.arp
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
        var own: Project = p
        // Прежние проекты: блоки аранжировки — со своей копией клипа сетки на момент открытия.
        own.ownArrPatterns()
        project = own
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
        translationMenu = nil
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
        rememberEditorMarks()
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
        let s: Int = selectedTrack
        let cell: Int = s < live.cell.count ? live.cell[s] : -1
        // STEPS аранжировщика: ход — только пока играет этот блок.
        if let i = t.editedBlock { return cell == SeqData.slots + i ? live.playPos[s] : -1 }
        if t.open != t.slot || cell >= SeqData.slots { return -1 }
        return live.playPos[s]
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
        MasterDraw.scale = CGFloat(settings.displayScale)
        UserDefaults.standard.set(settings.encode(), forKey: "settings")
        syncTapSensor()
    }

    /// Акселерометр работает, только пока KEY VELOCITY включён.
    func syncTapSensor() {
        if settings.velocity { tapSensor.start() } else { tapSensor.stop() }
    }

    private static func loadSettings() -> AppSettings {
        let s: AppSettings = AppSettings.decode(UserDefaults.standard.data(forKey: "settings"))
        MasterDraw.scale = CGFloat(s.displayScale)
        return s
    }

    private static func loadAppearance() -> Appearance {
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? ""
        return Appearance(rawValue: raw) ?? .system
    }
}
