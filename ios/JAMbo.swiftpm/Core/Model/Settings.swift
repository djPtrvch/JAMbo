import Foundation

// Настройки приложения (как settings.ts веба): хранятся отдельно от проектов (UserDefaults, JSON), общие для проектов.

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

    private enum Keys: String, CodingKey { case quantize, overdub, autoRec, arrFromStart }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        quantize = c.value(.quantize, true)
        overdub = c.value(.overdub, false)
        autoRec = c.value(.autoRec, true)
        arrFromStart = c.value(.arrFromStart, false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(quantize, forKey: .quantize)
        try c.encode(overdub, forKey: .overdub)
        try c.encode(autoRec, forKey: .autoRec)
        try c.encode(arrFromStart, forKey: .arrFromStart)
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
    /// SETTINGS → MORPH (S9): ручки в режиме MORPH — на все дорожки (сдвиг на ту же величину) или на выбранную;
    /// возврат после выключения — MorphReturn.beats[morphReturn] долей (0 — сразу).
    /// По умолчанию — на все дорожки (решение пользователя).
    public var morphAll: Bool = true
    public var morphReturn: Int = 0
    /// SETTINGS → MORPH → MODE (3.11, решение пользователя): false — SWITCH (как прежде: ALL TRACKS — переключатель,
    /// SHIFT + тап по MORPH), true — HOLD (тап — только выбранная дорожка; SHIFT + MORPH держат — все дорожки,
    /// отпустили — режим выключен).
    public var morphHold: Bool = false
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
    /// SETTINGS → SAMPLER → PITCH (S12): ручка Pitch сэмпла и её p-lock — по полутонам (по умолчанию) или плавно.
    public var pitchSemitones: Bool = false
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
    /// SETTINGS → AUDIO ENGINE → BACKGROUND AUDIO (как в вебе): звук играет, когда приложение свёрнуто или экран
    /// заблокирован; по умолчанию — да. Нужен ключ UIBackgroundModes: audio (Info.plist рядом с Package.swift).
    public var backgroundAudio: Bool = true
    /// SETTINGS → APPEARANCE → SCALE: шкала дисплеев окон модулей мастера, dB (48, 32, 16; как в вебе).
    public var displayScale: Int = 48
    public static let displayScales: [Int] = [48, 32, 16]
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

    private enum CodingKeys: String, CodingKey { case appearance, pianoOctaves, velocity, record, sliceMap, scSends, latchFx, latchMod, rollGrid,
                                         rollSound, levelRelative, morphAll, morphReturn, morphHold, mixKey, mixCrossfader,
                                         clearSampleLocks, pitchSemitones, midi, sync,
                                         arrangeCompact, fxPictures, backgroundAudio, arrangeRepeats, stretchBeat,
                                         metronomeVol, arrangeScale, arrangeFollow, displayScale,
                                         randomDrums, randomChords, randomSwing, randomStepsAll, randomSamples, showPartType,
                                         warpProjectBpm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = c.value(.appearance, "SYSTEM")
        pianoOctaves = c.value(.pianoOctaves, 1)
        velocity = c.value(.velocity, false)
        record = c.value(.record, RecordSettings())
        sliceMap = c.value(.sliceMap, .chromatic)
        scSends = c.value(.scSends, SidechainSends())
        latchFx = c.value(.latchFx, false)
        latchMod = c.value(.latchMod, false)
        let g: Int = c.value(.rollGrid, Roll.gridDef)
        rollGrid = Roll.grids.contains(g) ? g : Roll.gridDef
        rollSound = c.value(.rollSound, true)
        levelRelative = c.value(.levelRelative, false)
        morphAll = c.value(.morphAll, true)
        morphHold = c.value(.morphHold, false)
        let mr: Int = c.value(.morphReturn, 0)
        morphReturn = mr >= 0 && mr < MorphReturn.beats.count ? mr : 0
        mixKey = c.value(.mixKey, true)
        mixCrossfader = c.value(.mixCrossfader, true)
        clearSampleLocks = c.value(.clearSampleLocks, true)
        warpProjectBpm = c.value(.warpProjectBpm, false)
        stretchBeat = c.value(.stretchBeat, false)
        pitchSemitones = c.value(.pitchSemitones, false)
        midi = c.value(.midi, MidiSettings())
        sync = c.value(.sync, SyncSettings())
        arrangeCompact = c.value(.arrangeCompact, false)
        arrangeRepeats = c.value(.arrangeRepeats, true)
        fxPictures = c.value(.fxPictures, true)
        backgroundAudio = c.value(.backgroundAudio, true)
        arrangeScale = c.value(.arrangeScale, false)
        arrangeFollow = c.value(.arrangeFollow, true)
        let ds: Int = c.value(.displayScale, 48)
        displayScale = AppSettings.displayScales.contains(ds) ? ds : 48
        randomDrums = c.value(.randomDrums, false)
        randomChords = c.value(.randomChords, false)
        randomSwing = c.value(.randomSwing, false)
        randomStepsAll = c.value(.randomStepsAll, false)
        randomSamples = c.value(.randomSamples, false)
        showPartType = c.value(.showPartType, false)
        let mv: Double = c.value(.metronomeVol, 100)
        metronomeVol = Swift.min(200, Swift.max(0, mv))
    }

    /// Запись — по тем же ключам, что прежде (коробка more в файле не видна).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(pianoOctaves, forKey: .pianoOctaves)
        try c.encode(velocity, forKey: .velocity)
        try c.encode(record, forKey: .record)
        try c.encode(sliceMap, forKey: .sliceMap)
        try c.encode(scSends, forKey: .scSends)
        try c.encode(latchFx, forKey: .latchFx)
        try c.encode(latchMod, forKey: .latchMod)
        try c.encode(rollGrid, forKey: .rollGrid)
        try c.encode(rollSound, forKey: .rollSound)
        try c.encode(levelRelative, forKey: .levelRelative)
        try c.encode(morphAll, forKey: .morphAll)
        try c.encode(morphReturn, forKey: .morphReturn)
        try c.encode(morphHold, forKey: .morphHold)
        try c.encode(mixKey, forKey: .mixKey)
        try c.encode(mixCrossfader, forKey: .mixCrossfader)
        try c.encode(clearSampleLocks, forKey: .clearSampleLocks)
        try c.encode(pitchSemitones, forKey: .pitchSemitones)
        try c.encode(midi, forKey: .midi)
        try c.encode(sync, forKey: .sync)
        try c.encode(arrangeCompact, forKey: .arrangeCompact)
        try c.encode(fxPictures, forKey: .fxPictures)
        try c.encode(backgroundAudio, forKey: .backgroundAudio)
        try c.encode(arrangeRepeats, forKey: .arrangeRepeats)
        try c.encode(stretchBeat, forKey: .stretchBeat)
        try c.encode(metronomeVol, forKey: .metronomeVol)
        try c.encode(arrangeScale, forKey: .arrangeScale)
        try c.encode(arrangeFollow, forKey: .arrangeFollow)
        try c.encode(displayScale, forKey: .displayScale)
        try c.encode(randomDrums, forKey: .randomDrums)
        try c.encode(randomChords, forKey: .randomChords)
        try c.encode(randomSwing, forKey: .randomSwing)
        try c.encode(randomStepsAll, forKey: .randomStepsAll)
        try c.encode(randomSamples, forKey: .randomSamples)
        try c.encode(showPartType, forKey: .showPartType)
        try c.encode(warpProjectBpm, forKey: .warpProjectBpm)
    }
}
