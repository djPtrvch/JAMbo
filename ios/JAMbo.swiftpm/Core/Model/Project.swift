// Модель проекта (как Doc и Track в src/state.ts веба; имена полей те же — для импорта .jambo в S11).
// Значения (struct): копия — снимок для UNDO.

/// Назначение источника модуляции на ручку: lfo 1–3 — LFO1–3, 4 — ENV; amount −1…+1 (доля хода ручки).
public struct ModAssign: Codable, Equatable, Sendable {
    public var lfo: Int
    public var amount: Double
    /// Назначение на ручку FX: дорожка-источник (LFO/ENV дорожки, выбранной при назначении).
    public var track: Int?

    public init(lfo: Int, amount: Double, track: Int? = nil) {
        self.lfo = lfo
        self.amount = amount
        self.track = track
    }
}

public struct Step: Codable, Equatable, Sendable {
    public var on: Bool = false
    /// Длина ноты в шагах.
    public var len: Int = 1
    /// Ноты шага (MIDI). Несколько нот — POLY.
    public var notes: [Int] = []
    /// Длины нот в шагах (параллельно notes; S8, пианоролл); nil — у всех len. При lens len — самая длинная.
    public var lens: [Int]?
    /// Velocity нот — Level ноты 0…127 (параллельно notes; −1 — без своей); nil — ни у одной своей нет.
    public var vels: [Double]?
    /// P-lock: id параметра → значение. Может быть и на шаге без ноты.
    public var locks: [String: Double] = [:]
    /// Свой звук шага (S2).
    public var sound: String?
    /// P-lock, которые поставил пресет звука шага.
    public var soundLocks: [String]?

    public init() {}
}

public struct Track: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var sample: String = ""
    public var params: [String: Double]
    /// Клипы столбца сетки паттернов (nil — пустая ячейка): у каждого свой паттерн (страницы, длина, играющие
    /// страницы). Активная ячейка (играет или запустится) — slot; открытая в секвенсоре и миниатюрах — open.
    public var clips: [Clip?] = Track.firstClips()
    public var slot: Int = 0
    public var open: Int = 0
    public var mute: Bool = false
    public var solo: Bool = false
    /// Остановлена в сетке паттернов.
    public var stopped: Bool = false
    /// Папка звуков дорожки (стрелки ◀ ▶ под окном сэмпла), маркеры нарезки по ключу сэмпла, громкость микшера (dB).
    public var folder: Folder = Folder()
    public var slices: [String: [SliceMark]] = [:]
    /// Метки варпинга по ключу сэмпла (WARP; Warp.swift).
    public var warps: [String: WarpInfo] = [:]
    public var vol: Double = Params.volDef
    /// SETTINGS → LEVEL RELATIVE (S9): подстройка громкости регулятором справа, dB вниз от громкости MIX
    /// (0 — как в MIX, volMin — тишина); итог — vol + trim; при LEVEL ABSOLUTE не действует.
    public var trim: Double = 0
    /// Таблица WTABLE дорожки ("" — BASIC, "builtin:NAME" — встроенная; свои WAV — S11).
    public var table: String = ""
    /// Сэмпл GRANULAR дорожки (ключ хранилища; "" — нет, движок молчит): кнопка SOURCE в меню звука.
    public var grain: String = ""
    /// Назначения LFO1–3 / ENV на ручки дорожки (id параметра → источник и степень).
    public var assigns: [String: ModAssign] = [:]
    /// MORPH: значения ручек и назначений на момент включения режима (что меняли), дорожку меняли (жёлтая точка).
    public var morphOrig: [String: Double] = [:]
    public var morphOrigAssign: [String: ModAssign?] = [:]
    public var morphEdited: Bool = false
    /// EQ дорожки (doc.eqs[i] веба): один на все клипы, переезжает и копируется вместе с дорожкой.
    public var eq: Eq = Eq()
    /// Переход MIX (S10, t.home веба): свой звук дорожки, пока она играет клип PREV со звуком старой дорожки.
    public var home: TrackSound?
    /// MIDI дорожки: вход нот и выход (TrackMidi).
    public var midi: TrackMidi = TrackMidi()
    /// Аранжировщик (S15): блоки дорожки на таймлайне (по порядку, без перекрытий) и цвет (номер в ArrPalette).
    public var blocks: [ArrBlock] = []
    public var color: Int = ArrPalette.defaultColor
    /// Автоматизация на таймлайне (S15f): кривые ручек сетки дорожки, по одной на ручку.
    public var autos: [ArrAutoLane] = []

    public init(index: Int) {
        id = Int.random(in: 0..<(1 << 31))
        name = "\(index + 1)"
        params = Params.defaults()
    }

    /// Последовательность MIX или MST.
    static func channel(_ name: String) -> Track {
        var t = Track(index: 0)
        t.name = name
        return t
    }

    static func firstClips() -> [Clip?] {
        var c = [Clip?](repeating: nil, count: Params.patternSlots)
        c[0] = Clip()
        return c
    }

    /// Активный клип пуст (его удалили): дорожка стоит, звук остаётся.
    public var blank: Bool { return clips[slot] == nil }

    private var openIndex: Int { return Swift.max(0, Swift.min(open, clips.count - 1)) }

    /// Открытый клип (пустая ячейка — пустой паттерн).
    public var openClip: Clip { return clips[openIndex] ?? Clip() }

    /// Правка открытого клипа (пустой ячейки — создаёт клип). Ссылка в массиве снимается на время правки —
    /// массивы страниц меняются на месте, без копии.
    public mutating func withOpen(_ f: (inout Clip) -> Void) {
        let k = openIndex
        var c = clips[k] ?? Clip()
        clips[k] = nil
        f(&c)
        clips[k] = c
    }

    /// Паттерн открытого клипа: страницы, длина (1…pages·16; укорочена только страница с последним шагом),
    /// играющие страницы playFrom…playTo. Секвенсор, миниатюры и правки страниц работают с ним.
    public var pages: [[Step]] {
        get { return openClip.pages }
        set { withOpen { $0.pages = newValue } }
    }

    public var length: Int {
        get { return openClip.length }
        set { withOpen { $0.length = newValue } }
    }

    public var playFrom: Int {
        get { return openClip.playFrom }
        set { withOpen { $0.playFrom = newValue } }
    }

    public var playTo: Int {
        get { return openClip.playTo }
        set { withOpen { $0.playTo = newValue } }
    }

    public static func emptyPage() -> [Step] {
        return [Step](repeating: Step(), count: Params.stepsPerPage)
    }

    public func pageLen(_ p: Int) -> Int { return openClip.pageLen(p, from: openClip.playFrom) }
    public func pageLen(_ p: Int, from: Int) -> Int { return openClip.pageLen(p, from: from) }
    public var playLen: Int { return openClip.playLen }
    public func playLen(from: Int, to: Int) -> Int { return openClip.playLen(from: from, to: to) }
    public func playIndex(_ n: Int) -> Int { return openClip.playIndex(n) }
    public func step(_ index: Int) -> Step? { return openClip.step(index) }
    public func outside(_ index: Int) -> Bool { return openClip.outside(index) }

    /// Значение параметра на шаге: p-lock шага, иначе ручка дорожки.
    public func value(_ id: String, step: Step?) -> Double {
        if let v = step?.locks[id] { return v }
        return params[id] ?? Params.byId[id]?.def ?? 0
    }
}

/// Клип — ячейка сетки паттернов со своим паттерном: страницы (до 8), длина, играющие страницы (диапазон подряд),
/// гамма, нота и общие FX. Звук и ручки — у дорожки (общие для всех её клипов). Копия клипа — независимая.
public struct Clip: Codable, Equatable, Sendable {
    public var pages: [[Step]]
    public var length: Int
    public var playFrom: Int
    public var playTo: Int
    public var scale: Int?
    public var root: Int?
    public var fx: [String: Double]?
    /// Переход MIX (S10, src веба): только у клипа строки PREV — звук старой дорожки (старый проект).
    public var src: TrackSound?
    /// Скорость паттерна (S14): степень двойки — 1 (×2), 0 или nil (×1), −1…−4 (1/2…1/16).
    public var rate: Int?

    public static let rates: [Int] = [1, 0, -1, -2, -3, -4]
    public static let rateNames: [String] = ["2", "1", "1/2", "1/4", "1/8", "1/16"]

    public var speed: Int { return rate ?? 0 }

    /// Проход в тиках транспорта (шестнадцатых) с учётом скорости.
    public var passTicks: Int { return SeqData.passTicks(playLen, speed) }

    /// Позиция прохода, которая звучит на тике o от начала клипа (×2 — первая из двух).
    public func localStep(_ o: Int) -> Int {
        let pass: Int = passTicks
        let r: Int = ((o % pass) + pass) % pass
        if speed > 0 { return r * 2 }
        return r >> (-speed)
    }

    public init(pages: [[Step]] = [Track.emptyPage()], length: Int = Params.stepsPerPage, playFrom: Int = 0,
                playTo: Int = 0, scale: Int? = nil, root: Int? = nil, fx: [String: Double]? = nil) {
        self.pages = pages
        self.length = length
        self.playFrom = playFrom
        self.playTo = playTo
        self.scale = scale
        self.root = root
        self.fx = fx
    }

    /// Играющие страницы в пределах страниц клипа.
    public var range: ClosedRange<Int> {
        let to = Swift.max(0, Swift.min(playTo, pages.count - 1))
        return Swift.min(Swift.max(0, playFrom), to)...to
    }

    /// Шагов на странице p у прохода, который начинается со страницы from (как pageLen веба).
    public func pageLen(_ p: Int, from: Int) -> Int {
        let n = Params.stepsPerPage
        if length > from * n { return Swift.max(0, Swift.min(n, length - p * n)) }
        return n
    }

    /// Шагов в проходе: сумма длин играющих страниц.
    public var playLen: Int { return playLen(from: range.lowerBound, to: range.upperBound) }

    public func playLen(from: Int, to: Int) -> Int {
        var n = 0
        for p in from...Swift.max(from, to) { n += pageLen(p, from: from) }
        return Swift.max(1, n)
    }

    /// Шаг (p·16 + s) на позиции n прохода, по кругу.
    public func playIndex(_ n: Int) -> Int {
        let r0 = range
        let len = playLen
        var r = ((n % len) + len) % len
        for p in r0 {
            let l = pageLen(p, from: r0.lowerBound)
            if r < l { return p * Params.stepsPerPage + r }
            r -= l
        }
        return r0.lowerBound * Params.stepsPerPage
    }

    public func step(_ index: Int) -> Step? {
        let p = index / Params.stepsPerPage
        guard index >= 0, p < pages.count else { return nil }
        return pages[p][index % Params.stepsPerPage]
    }

    /// Шаг за длиной паттерна — не играет.
    public func outside(_ index: Int) -> Bool {
        return index % Params.stepsPerPage >= pageLen(index / Params.stepsPerPage, from: range.lowerBound)
    }
}

/// Строка сетки (сцена): имя (пустое — номер) и число повторов до следующей строки.
public struct SceneRow: Codable, Equatable, Sendable {
    public var name: String = ""
    public var repeats: Int = 1

    public init(name: String = "", repeats: Int = 1) {
        self.name = name
        self.repeats = repeats
    }
}

public struct Project: Codable, Equatable, Sendable {
    /// Версия формата: 3 — S12 (Swing без p-lock и LFO/ENV), 4 — S12 (ручки 1.4 своих движков, SynthMigration),
    /// 5 — S15 (аранжировка: Track.blocks, Track.color, arrange; в старых — пустая).
    public var version: Int = 5
    /// Сообщение при открытии проекта (перевод старой версии, например пропавший суб ANALOG); nil — нет.
    public var notice: String?
    public var bpm: Double = 120
    public var scale: Int = 0
    public var root: Int = 0
    /// Общие FX (сетка FX и пред-задержка): принадлежат клипам — действуют FX клипа, запущенного последним.
    public var fx: [String: Double] = Params.fxDefaults()
    /// Назначения LFO/ENV на ручки FX (источник — LFO/ENV дорожки track).
    public var fxAssigns: [String: ModAssign] = [:]
    /// Мастер (как doc.master веба, без убранных в Swift параметров — MasterChain.ids): RELEASE AUTO — значение
    /// MasterChain.autoValue; BYPASS модулей — отдельно.
    public var master: [String: Double] = MasterChain.defaultValues()
    public var satBypass: Bool = false
    public var cmpBypass: Bool = false
    public var clipBypass: Bool = false
    public var limBypass: Bool = false
    /// Громкость выхода мастера, dB (после лимитера; 0 — без ослабления, вниз до −∞ — Params.volMin).
    public var outVol: Double = 0
    /// EQ мастера (doc.masterEq) — первый в цепочке мастера.
    public var masterEq: Eq = Eq()
    public var tracks: [Track]
    /// Свои последовательности MIX и MST (doc.chanSeqs веба): страницы и p-lock шагов (нот нет) — у MIX громкости
    /// дорожек (mix.vol1…16), у MST — параметры мастера (ручки MST без p-lock — ставить нечего, как в вебе).
    /// Один клип; играют с PLAY с первого шага, без сетки паттернов.
    public var chanSeqs: [Track] = [Track.channel("MIX"), Track.channel("MST")]
    /// Строки сетки паттернов: имена и повторы.
    public var scenes: [SceneRow] = [SceneRow](repeating: SceneRow(), count: Params.patternSlots)
    /// Видимых строк (по умолчанию 1; заполненные видны всегда).
    public var rows: Int = 1
    /// Меню сетки: строка старта PLAY; в конце строк — STOP или LOOP.
    public var arrStart: Int = 0
    public var arrEndStop: Bool = false
    /// «+» под строками: true — копии играющих клипов (COPY PLAYING, по умолчанию), false — новые пустые.
    public var plusCopy: Bool = false
    /// Имена сэмплов (ключ по содержимому → имя файла) и определённая высота (MIDI-нота, только для индикации).
    public var files: [String: String] = [:]
    public var roots: [String: Int] = [:]
    /// LOOP ROW: играющая строка повторяется бесконечно (по умолчанию включена).
    public var rowLoop: Bool = true
    /// Стрелки ▲ ▼: false — только прокрутка (VIEW), true — при игре ещё и переход строки (SWITCH).
    public var arrowSwitch: Bool = false
    /// STEPS в сетке паттернов выключена: строка дорожек, секвенсор и клавиатура скрыты (как STEPS аранжировщика).
    public var gridHideSteps: Bool = false
    /// Идёт переход MIX (S10): последняя строка сетки — PREV (клипы старого проекта), строк проекта — на одну меньше.
    public var prevRow: Bool = false
    /// Аранжировщик (S15): маркеры, петля, сетка и магнит, STEPS (блоки — у дорожек).
    public var arrange: Arrangement = Arrangement()

    public init() {
        tracks = (0..<Params.trackCount).map { Track(index: $0) }
    }
}
