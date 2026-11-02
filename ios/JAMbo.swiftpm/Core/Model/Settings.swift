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
        quantize = (try? c.decode(Bool.self, forKey: .quantize)) ?? true
        overdub = (try? c.decode(Bool.self, forKey: .overdub)) ?? false
        autoRec = (try? c.decode(Bool.self, forKey: .autoRec)) ?? true
        arrFromStart = (try? c.decode(Bool.self, forKey: .arrFromStart)) ?? false
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

public struct AppSettings: Codable, Equatable, Sendable {
    /// SYSTEM, LIGHT или DARK.
    public var appearance: String = "SYSTEM"
    /// Октав гаммы на клавишах клавиатуры: 1 или 2.
    public var pianoOctaves: Int = 1
    /// Чувствительность клавиш к нажатию.
    public var velocity: Bool = false
    /// Меню под CHORD → CHORD ROW: строка выбора аккорда (TRIAD, 7, 9) под клавишами в режиме CHORD; по умолчанию — да.
    public var chordRow: Bool = true
    /// Меню под CHORD → CHORD NAMES: в режиме CHORD на клавишах имена аккордов (Am7) вместо имён нот.
    public var chordNames: Bool = false
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
    /// SETTINGS → MIX (S9, действуют с переходами S10): гамма и нота нового проекта при переходе; кроссфейдер
    /// (ON — темп по кроссфейдеру, OFF — темп старого паттерна).
    public var mixKey: Bool = true
    public var mixCrossfader: Bool = true
    /// SETTINGS → SAMPLER (S11b): загрузка звуков из библиотеки на дорожку снимает её сэмпл-локи (шаги со своим
    /// сэмплом играют звук дорожки своей нотой); пресет-локи остаются.
    public var clearSampleLocks: Bool = true
    /// SETTINGS → SAMPLER → STRETCH: алгоритм таймстретча RATE в режиме Stretch — NORMAL (фазовый вокодер, по
    /// умолчанию) или BEAT (WSOLA, для ударных лупов).
    public var stretchBeat: Bool = false
    /// SETTINGS → SAMPLER → PITCH (S12): ручка Pitch сэмпла и её p-lock — по полутонам (по умолчанию) или плавно.
    public var pitchSemitones: Bool = false
    /// Бутерброд → MIDI (S13): вход, обратная связь, ноты.
    public var midi = MidiSettings()
    /// SETTINGS → RECORD → STEP SWIPE (S13, решение пользователя): палец по шагам — длинная нота от первого шага
    /// (LENGTH, по умолчанию) или триг на каждом пройденном шаге (PAINT).
    public var stepPaint: Bool = false
    /// Бутерброд → SYNC (S13e): квант, MIDI-клок, настройки Ableton Link.
    public var sync = SyncSettings()
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

    private enum Keys: String, CodingKey { case appearance, pianoOctaves, velocity, chordRow, chordNames, record, sliceMap, scSends, latchFx, latchMod, rollGrid,
                                         rollSound, levelRelative, morphAll, morphReturn, mixKey, mixCrossfader,
                                         clearSampleLocks, pitchSemitones, midi, stepPaint, sync,
                                         arrangeCompact, fxPictures, backgroundAudio, arrangeRepeats, stretchBeat,
                                         metronomeVol, arrangeScale, arrangeFollow }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        appearance = (try? c.decode(String.self, forKey: .appearance)) ?? "SYSTEM"
        pianoOctaves = (try? c.decode(Int.self, forKey: .pianoOctaves)) ?? 1
        velocity = (try? c.decode(Bool.self, forKey: .velocity)) ?? false
        chordRow = (try? c.decode(Bool.self, forKey: .chordRow)) ?? true
        chordNames = (try? c.decode(Bool.self, forKey: .chordNames)) ?? false
        record = (try? c.decode(RecordSettings.self, forKey: .record)) ?? RecordSettings()
        sliceMap = (try? c.decode(SliceMap.self, forKey: .sliceMap)) ?? .chromatic
        scSends = (try? c.decode(SidechainSends.self, forKey: .scSends)) ?? SidechainSends()
        latchFx = (try? c.decode(Bool.self, forKey: .latchFx)) ?? false
        latchMod = (try? c.decode(Bool.self, forKey: .latchMod)) ?? false
        let g: Int = (try? c.decode(Int.self, forKey: .rollGrid)) ?? Roll.gridDef
        rollGrid = Roll.grids.contains(g) ? g : Roll.gridDef
        rollSound = (try? c.decode(Bool.self, forKey: .rollSound)) ?? true
        levelRelative = (try? c.decode(Bool.self, forKey: .levelRelative)) ?? false
        morphAll = (try? c.decode(Bool.self, forKey: .morphAll)) ?? true
        let mr: Int = (try? c.decode(Int.self, forKey: .morphReturn)) ?? 0
        morphReturn = mr >= 0 && mr < MorphReturn.beats.count ? mr : 0
        mixKey = (try? c.decode(Bool.self, forKey: .mixKey)) ?? true
        mixCrossfader = (try? c.decode(Bool.self, forKey: .mixCrossfader)) ?? true
        clearSampleLocks = (try? c.decode(Bool.self, forKey: .clearSampleLocks)) ?? true
        stretchBeat = (try? c.decode(Bool.self, forKey: .stretchBeat)) ?? false
        pitchSemitones = (try? c.decode(Bool.self, forKey: .pitchSemitones)) ?? false
        midi = (try? c.decode(MidiSettings.self, forKey: .midi)) ?? MidiSettings()
        stepPaint = (try? c.decode(Bool.self, forKey: .stepPaint)) ?? false
        sync = (try? c.decode(SyncSettings.self, forKey: .sync)) ?? SyncSettings()
        arrangeCompact = (try? c.decode(Bool.self, forKey: .arrangeCompact)) ?? false
        arrangeRepeats = (try? c.decode(Bool.self, forKey: .arrangeRepeats)) ?? true
        fxPictures = (try? c.decode(Bool.self, forKey: .fxPictures)) ?? true
        backgroundAudio = (try? c.decode(Bool.self, forKey: .backgroundAudio)) ?? true
        arrangeScale = (try? c.decode(Bool.self, forKey: .arrangeScale)) ?? false
        arrangeFollow = (try? c.decode(Bool.self, forKey: .arrangeFollow)) ?? true
        let mv: Double = (try? c.decode(Double.self, forKey: .metronomeVol)) ?? 100
        metronomeVol = Swift.min(200, Swift.max(0, mv))
    }
}
