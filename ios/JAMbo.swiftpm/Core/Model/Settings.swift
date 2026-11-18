import Foundation

// Настройки приложения: хранятся отдельно от проектов (UserDefaults, JSON), общие для проектов.

public struct RecordSettings: Codable, Equatable, Sendable {
    /// ON — нота на ближайший шаг, OFF — на шаг, в котором нажали.
    public var quantize: Bool = true
    /// OFF — шаги, по которым проходит запись, очищаются; ON — ноты добавляются.
    public var overdub: Bool = false
    /// Запись автоматизации с REC (S13).
    public var autoRec: Bool = true
    /// ARRANGE REC START (решение пользователя 2.11): запись аранжировки из сетки на PLAY — с начала таймлайна (true)
    /// или с плейхеда (false, по умолчанию).
    public var arrFromStart: Bool = false

    public init() {}


    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        quantize = c.value(CaseKey("quantize"), true)
        overdub = c.value(CaseKey("overdub"), false)
        autoRec = c.value(CaseKey("autoRec"), true)
        arrFromStart = c.value(CaseKey("arrFromStart"), false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(quantize, forKey: CaseKey("quantize"))
        try c.encode(overdub, forKey: CaseKey("overdub"))
        try c.encode(autoRec, forKey: CaseKey("autoRec"))
        try c.encode(arrFromStart, forKey: CaseKey("arrFromStart"))
    }
}

/// SETTINGS → SIDECHAIN: какие посылы приглушаются вместе с дорожкой (по умолчанию только Drive).
public struct SidechainSends: Codable, Equatable, Sendable {
    public var rev: Bool = false
    public var dly: Bool = false
    public var drv: Bool = true

    public init() {}
}

/// Поля настроек со строками и массивами (оформление, MIDI, SYNC) — «в коробке» AppSettings.more: копия настроек
/// (их читают многие виды) не тянет их по значению (объём сборки, 9.11).
public struct SettingsMore: Equatable, Sendable {
    public var appearance: String = "SYSTEM"
    public var midi = MidiSettings()
    public var sync = SyncSettings()

    public init() {}
}

public struct AppSettings: Codable, Equatable, Sendable {
    /// Оформление, MIDI и SYNC — в коробке (всегда один элемент).
    private var more: [SettingsMore] = [SettingsMore()]
    /// SYSTEM, LIGHT или DARK.
    public var appearance: String {
        get { return more[0].appearance }
        set { more[0].appearance = newValue }
    }
    /// Октав гаммы на клавишах клавиатуры: 1 или 2.
    public var pianoOctaves: Int = 1
    /// Чувствительность клавиш к нажатию.
    public var velocity: Bool = false
    public var record = RecordSettings()
    /// SETTINGS → SAMPLER → SLICE NOTES: ноты маркеров нарезки по порядку.
    public var sliceMap: SliceMap = .chromatic
    /// SETTINGS → SIDECHAIN: посылы Reverb, Delay, Drive приглушаются огибающей.
    public var scSends = SidechainSends()
    /// FX и MOD в режиме toggle (SHIFT + двойной тап по кнопке): тап включает страницу, следующий — выключает.
    public var latchFx: Bool = false
    public var latchMod: Bool = false
    /// Пианоролл (S8): GRID — шагов в клетке (1, 2, 4); звук ноты при нажатии.
    public var rollGrid: Int = Roll.gridDef
    public var rollSound: Bool = true
    /// SETTINGS → LEVEL (S9): регулятор справа у дорожки — ABSOLUTE (громкость MIX) или RELATIVE (подстройка
    /// Track.trim вниз от громкости MIX).
    public var levelRelative: Bool = false
    /// SETTINGS → MORPH (S9): возврат после выключения режима — MorphReturn.beats[morphReturn] долей (0 — сразу).
    /// ALL TRACKS и MODE SWITCH / HOLD убраны (9.11, решение пользователя): тап — выбранная дорожка, SHIFT + MORPH
    /// держат — все дорожки; прежние ключи morphAll и morphHold в настройках не читаются.
    public var morphReturn: Int = 0
    /// SETTINGS → MORPH → MODE (9.11, решение пользователя): false — TAP (по умолчанию: тап по MORPH включает и
    /// выключает режим), true — HOLD (режим на выбранной дорожке, пока держат MORPH; отпустили — выключен). SHIFT +
    /// MORPH держат — все дорожки, в обоих режимах. Ключ новый: прежний morphHold значил другое и не читается.
    public var morphHoldMode: Bool = false
    /// SETTINGS → RANDOM (SHIFT + CHORD): случайный ритм ударных и прогрессия — вкл./выкл.; AUTO SWING — Swing
    /// дорожки по стилю ритма; ритм сразу на все ударные дорожки. Стиль — всегда общий (STYLE ALL TRACKS убран 4.11).
    public var randomDrums: Bool = false
    public var randomChords: Bool = false
    public var randomSwing: Bool = false
    public var randomStepsAll: Bool = false
    /// SETTINGS → RANDOM → SAMPLES: случайный рисунок нарезанного сэмпла (SliceRhythm).
    public var randomSamples: Bool = false
    /// SETTINGS → RANDOM → SHOW PART TYPE: в окне CHORD — раздел PART (BASS, LEAD, PAD): тип случайной партии
    /// дорожки, выбор вместо определённого самим.
    public var showPartType: Bool = false
    /// SETTINGS → MIX (S9, действуют с переходами S10): гамма и нота нового проекта при переходе; кроссфейдер
    /// (ON — темп по кроссфейдеру, OFF — темп старого паттерна).
    public var mixKey: Bool = true
    public var mixCrossfader: Bool = true
    /// SETTINGS → SAMPLER (S11b): загрузка звуков из библиотеки на дорожку снимает её сэмпл-локи (шаги со своим
    /// сэмплом играют звук дорожки своей нотой); пресет-локи остаются.
    public var clearSampleLocks: Bool = true
    /// SETTINGS → SAMPLER → WARP TO PROJECT BPM (решение пользователя): у сэмплов с метками варпинга BPM файла всегда
    /// равен темпу проекта и идёт за ним (свой BPM не действует); при входе в WARP у сэмпла без меток и своего BPM
    /// файла BPM файла ставится равным темпу проекта; по умолчанию — нет.
    public var warpProjectBpm: Bool = false
    /// SETTINGS → SAMPLER → STRETCH: алгоритм таймстретча RATE в режиме Stretch — NORMAL (фазовый вокодер, по
    /// умолчанию) или BEAT (WSOLA, для ударных лупов).
    public var stretchBeat: Bool = false
    /// SETTINGS → SAMPLER → PITCH SHIFT и START / END SHIFT (9.11, решение пользователя; прежний PITCH SMOOTH /
    /// SEMITONES убран): как SHIFT даёт ступенчатый ход Pitch (полутоны) и Start / End (доли сэмпла). false — HOLD
    /// (по умолчанию): с зажатой SHIFT поворот ступенчатый; true — TAP: SHIFT + тап по ручке переключает её ход у
    /// дорожки (Params.stepModeId), поворот без SHIFT.
    public var pitchShiftTap: Bool = false
    public var startEndShiftTap: Bool = false
    /// SETTINGS → RECORD → DRUM STEP PAINT (17.11, решение пользователя): на ударной дорожке палец по шагам ставит
    /// триг на каждом пройденном шаге (выкл. — длинная нота, как на остальных дорожках). По умолчанию ON.
    public var drumPaint: Bool = true
    /// Бутерброд → MIDI (S13): вход, обратная связь, ноты.
    public var midi: MidiSettings {
        get { return more[0].midi }
        set { more[0].midi = newValue }
    }
    /// Бутерброд → SYNC (S13e): квант, MIDI-клок, настройки Ableton Link.
    public var sync: SyncSettings {
        get { return more[0].sync }
        set { more[0].sync = newValue }
    }
    /// Режим строк при FIX (кнопки EXPANDED / COMPACT под измерителем аранжировщика): EXPANDED (по умолчанию) — 8
    /// строк на окно, дорожки прокручиваются; COMPACT — все дорожки на высоту окна.
    public var arrangeCompact: Bool = false
    /// SETTINGS → ARRANGE → TRACKS (решение пользователя): FIX (по умолчанию) — высота строк по кнопкам EXPANDED и
    /// COMPACT под измерителем, масштаба по вертикали нет; SCALE — строки масштабируются двумя пальцами по вертикали
    /// (от EXPANDED), кнопок нет.
    public var arrangeScale: Bool = false
    /// Действующий режим строк: при SCALE — от EXPANDED.
    public var arrangeExpanded: Bool { return arrangeScale || !arrangeCompact }
    /// SETTINGS → ARRANGE → FOLLOW PLAYHEAD (решение пользователя): при игре окно едет за плейхедом.
    public var arrangeFollow: Bool = true
    /// SETTINGS → ARRANGE → ROW REPEATS (решение пользователя): в аранжировку клип строки ложится на длину × повторы
    /// строки (×4 у клипа в такт — блок в 4 такта); выключено — один проход. По умолчанию — да.
    public var arrangeRepeats: Bool = true
    /// SETTINGS → APPEARANCE → FX ANIMATION (решение пользователя): картинки FX в окне сэмпла, пока регулируют ручки FX;
    /// по умолчанию — да.
    public var fxPictures: Bool = true
    /// SETTINGS → AUDIO ENGINE → BACKGROUND AUDIO: звук играет, когда приложение свёрнуто или экран
    /// заблокирован; по умолчанию — да. Нужен ключ UIBackgroundModes: audio (Info.plist рядом с Package.swift).
    public var backgroundAudio: Bool = true
    /// SETTINGS → AUDIO ENGINE → MULTICORE (17.11): дорожки синта на нескольких ядрах (RenderPool); по умолчанию — да.
    public var multicore: Bool = true
    /// SETTINGS → APPEARANCE → SCALE: шкала дисплеев окон модулей мастера, dB (48, 32, 16).
    public var displayScale: Int = 48
    public static let displayScales: [Int] = [48, 32, 16]
    /// SETTINGS → APPEARANCE → KNOB GROUPS (16.11, решение пользователя): группы ручек сеток 4×4 — строками (false,
    /// по умолчанию) или столбцами (true, как до 8.11). Только раскладка на экране: ручка хранится по группе и месту
    /// (p-lock, LFO/ENV, автоматизация, MIDI KNOB группа.место не меняются).
    public var knobColumns: Bool = false
    /// Громкость метронома, % (0…200; 100 — прежний уровень).
    public var metronomeVol: Double = 100

    public init() {}

    /// Чтение из JSON: неизвестные и недостающие поля — значения по умолчанию.
    public static func decode(_ data: Data?) -> AppSettings {
        guard let data = data, let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }


    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        appearance = c.value(CaseKey("appearance"), "SYSTEM")
        pianoOctaves = c.value(CaseKey("pianoOctaves"), 1)
        velocity = c.value(CaseKey("velocity"), false)
        record = c.value(CaseKey("record"), RecordSettings())
        sliceMap = c.value(CaseKey("sliceMap"), .chromatic)
        scSends = c.value(CaseKey("scSends"), SidechainSends())
        latchFx = c.value(CaseKey("latchFx"), false)
        latchMod = c.value(CaseKey("latchMod"), false)
        let g: Int = c.value(CaseKey("rollGrid"), Roll.gridDef)
        rollGrid = Roll.grids.contains(g) ? g : Roll.gridDef
        rollSound = c.value(CaseKey("rollSound"), true)
        levelRelative = c.value(CaseKey("levelRelative"), false)
        morphHoldMode = c.value(CaseKey("morphHoldMode"), false)
        let mr: Int = c.value(CaseKey("morphReturn"), 0)
        morphReturn = mr >= 0 && mr < MorphReturn.beats.count ? mr : 0
        mixKey = c.value(CaseKey("mixKey"), true)
        mixCrossfader = c.value(CaseKey("mixCrossfader"), true)
        clearSampleLocks = c.value(CaseKey("clearSampleLocks"), true)
        warpProjectBpm = c.value(CaseKey("warpProjectBpm"), false)
        stretchBeat = c.value(CaseKey("stretchBeat"), false)
        pitchShiftTap = c.value(CaseKey("pitchShiftTap"), false)
        startEndShiftTap = c.value(CaseKey("startEndShiftTap"), false)
        midi = c.value(CaseKey("midi"), MidiSettings())
        drumPaint = c.value(CaseKey("drumPaint"), true)
        sync = c.value(CaseKey("sync"), SyncSettings())
        arrangeCompact = c.value(CaseKey("arrangeCompact"), false)
        arrangeRepeats = c.value(CaseKey("arrangeRepeats"), true)
        fxPictures = c.value(CaseKey("fxPictures"), true)
        backgroundAudio = c.value(CaseKey("backgroundAudio"), true)
        multicore = c.value(CaseKey("multicore"), true)
        arrangeScale = c.value(CaseKey("arrangeScale"), false)
        arrangeFollow = c.value(CaseKey("arrangeFollow"), true)
        let ds: Int = c.value(CaseKey("displayScale"), 48)
        displayScale = AppSettings.displayScales.contains(ds) ? ds : 48
        knobColumns = c.value(CaseKey("knobColumns"), false)
        randomDrums = c.value(CaseKey("randomDrums"), false)
        randomChords = c.value(CaseKey("randomChords"), false)
        randomSwing = c.value(CaseKey("randomSwing"), false)
        randomStepsAll = c.value(CaseKey("randomStepsAll"), false)
        randomSamples = c.value(CaseKey("randomSamples"), false)
        showPartType = c.value(CaseKey("showPartType"), false)
        let mv: Double = c.value(CaseKey("metronomeVol"), 100)
        metronomeVol = Swift.min(200, Swift.max(0, mv))
    }

    /// Запись — по тем же ключам, что прежде (коробка more в файле не видна).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(appearance, forKey: CaseKey("appearance"))
        try c.encode(pianoOctaves, forKey: CaseKey("pianoOctaves"))
        try c.encode(velocity, forKey: CaseKey("velocity"))
        try c.encode(record, forKey: CaseKey("record"))
        try c.encode(sliceMap, forKey: CaseKey("sliceMap"))
        try c.encode(scSends, forKey: CaseKey("scSends"))
        try c.encode(latchFx, forKey: CaseKey("latchFx"))
        try c.encode(latchMod, forKey: CaseKey("latchMod"))
        try c.encode(rollGrid, forKey: CaseKey("rollGrid"))
        try c.encode(rollSound, forKey: CaseKey("rollSound"))
        try c.encode(levelRelative, forKey: CaseKey("levelRelative"))
        try c.encode(morphReturn, forKey: CaseKey("morphReturn"))
        try c.encode(morphHoldMode, forKey: CaseKey("morphHoldMode"))
        try c.encode(mixKey, forKey: CaseKey("mixKey"))
        try c.encode(mixCrossfader, forKey: CaseKey("mixCrossfader"))
        try c.encode(clearSampleLocks, forKey: CaseKey("clearSampleLocks"))
        try c.encode(pitchShiftTap, forKey: CaseKey("pitchShiftTap"))
        try c.encode(startEndShiftTap, forKey: CaseKey("startEndShiftTap"))
        try c.encode(midi, forKey: CaseKey("midi"))
        try c.encode(drumPaint, forKey: CaseKey("drumPaint"))
        try c.encode(sync, forKey: CaseKey("sync"))
        try c.encode(arrangeCompact, forKey: CaseKey("arrangeCompact"))
        try c.encode(fxPictures, forKey: CaseKey("fxPictures"))
        try c.encode(backgroundAudio, forKey: CaseKey("backgroundAudio"))
        try c.encode(multicore, forKey: CaseKey("multicore"))
        try c.encode(arrangeRepeats, forKey: CaseKey("arrangeRepeats"))
        try c.encode(stretchBeat, forKey: CaseKey("stretchBeat"))
        try c.encode(metronomeVol, forKey: CaseKey("metronomeVol"))
        try c.encode(arrangeScale, forKey: CaseKey("arrangeScale"))
        try c.encode(arrangeFollow, forKey: CaseKey("arrangeFollow"))
        try c.encode(displayScale, forKey: CaseKey("displayScale"))
        try c.encode(knobColumns, forKey: CaseKey("knobColumns"))
        try c.encode(randomDrums, forKey: CaseKey("randomDrums"))
        try c.encode(randomChords, forKey: CaseKey("randomChords"))
        try c.encode(randomSwing, forKey: CaseKey("randomSwing"))
        try c.encode(randomStepsAll, forKey: CaseKey("randomStepsAll"))
        try c.encode(randomSamples, forKey: CaseKey("randomSamples"))
        try c.encode(showPartType, forKey: CaseKey("showPartType"))
        try c.encode(warpProjectBpm, forKey: CaseKey("warpProjectBpm"))
    }
}

// Запись — как у синтезированной, но без своего перечисления CodingKeys (общий CaseKey; объём сборки, 18.11).
extension SidechainSends {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        rev = try c.decode(Bool.self, forKey: CaseKey("rev"))
        dly = try c.decode(Bool.self, forKey: CaseKey("dly"))
        drv = try c.decode(Bool.self, forKey: CaseKey("drv"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(rev, forKey: CaseKey("rev"))
        try c.encode(dly, forKey: CaseKey("dly"))
        try c.encode(drv, forKey: CaseKey("drv"))
    }
}
