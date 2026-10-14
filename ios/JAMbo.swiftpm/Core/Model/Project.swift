// Модель проекта (как Doc и Track в src/state.ts веба; имена полей те же — для импорта .jambo в S10).
// Значения (struct): копия — снимок для UNDO.

public struct Step: Codable, Equatable, Sendable {
    public var on: Bool = false
    /// Длина ноты в шагах.
    public var len: Int = 1
    /// Ноты шага (MIDI). Несколько нот — POLY.
    public var notes: [Int] = []
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
    public var pages: [[Step]]
    /// Длина паттерна в шагах (1…pages·16): одна на дорожку, укорочена только страница с последним шагом.
    public var length: Int
    /// Играющие страницы активного клипа: playFrom…playTo (копируются в clips[slot]).
    public var playFrom: Int = 0 { didSet { syncClip() } }
    public var playTo: Int = 0 { didSet { syncClip() } }
    /// Клипы столбца сетки паттернов (nil — пустая ячейка) и активная ячейка.
    public var clips: [Clip?] = Track.firstClips()
    public var slot: Int = 0
    public var mute: Bool = false
    public var solo: Bool = false
    /// Остановлена в сетке паттернов.
    public var stopped: Bool = false

    public init(index: Int) {
        id = Int.random(in: 0..<(1 << 31))
        name = "\(index + 1)"
        params = Params.defaults()
        pages = [Track.emptyPage()]
        length = Params.stepsPerPage
    }

    static func firstClips() -> [Clip?] {
        var c = [Clip?](repeating: nil, count: Params.patternSlots)
        c[0] = Clip(playFrom: 0, playTo: 0)
        return c
    }

    /// Активный клип пуст (его удалили): дорожка стоит, звук и паттерны остаются.
    public var blank: Bool { return clips[slot] == nil }

    private mutating func syncClip() {
        guard slot < clips.count, var c = clips[slot] else { return }
        if c.playFrom == playFrom && c.playTo == playTo { return }
        c.playFrom = playFrom
        c.playTo = playTo
        clips[slot] = c
    }

    public static func emptyPage() -> [Step] {
        return [Step](repeating: Step(), count: Params.stepsPerPage)
    }

    /// Шагов на странице p с учётом длины паттерна (как pageLen веба).
    public func pageLen(_ p: Int) -> Int {
        return pageLen(p, from: playFrom)
    }

    /// Шагов на странице p у клипа, который начинается со страницы from.
    public func pageLen(_ p: Int, from: Int) -> Int {
        let n = Params.stepsPerPage
        if length > from * n { return Swift.max(0, Swift.min(n, length - p * n)) }
        return n
    }

    /// Шагов в проходе: сумма длин играющих страниц.
    public var playLen: Int {
        return playLen(from: playFrom, to: playTo)
    }

    /// Шагов в проходе клипа from…to.
    public func playLen(from: Int, to: Int) -> Int {
        var n = 0
        for p in from...Swift.max(from, to) { n += pageLen(p, from: from) }
        return Swift.max(1, n)
    }

    /// Шаг (p·16 + s) на позиции n прохода, по кругу.
    public func playIndex(_ n: Int) -> Int {
        let len = playLen
        var r = ((n % len) + len) % len
        for p in playFrom...playTo {
            let l = pageLen(p)
            if r < l { return p * Params.stepsPerPage + r }
            r -= l
        }
        return playFrom * Params.stepsPerPage
    }

    public func step(_ index: Int) -> Step? {
        let p = index / Params.stepsPerPage
        guard p >= 0, p < pages.count else { return nil }
        return pages[p][index % Params.stepsPerPage]
    }

    /// Шаг за длиной паттерна — не играет.
    public func outside(_ index: Int) -> Bool {
        return index % Params.stepsPerPage >= pageLen(index / Params.stepsPerPage)
    }

    /// Значение параметра на шаге: p-lock шага, иначе ручка дорожки.
    public func value(_ id: String, step: Step?) -> Double {
        if let v = step?.locks[id] { return v }
        return params[id] ?? Params.byId[id]?.def ?? 0
    }
}

/// Клип — ячейка сетки паттернов: какие страницы дорожки играют (диапазон подряд), гамма, нота и общие FX.
/// Звук, шаги, длина — у дорожки (общие для всех её клипов).
public struct Clip: Codable, Equatable, Sendable {
    public var playFrom: Int
    public var playTo: Int
    public var scale: Int?
    public var root: Int?
    public var fx: [String: Double]?

    public init(playFrom: Int, playTo: Int, scale: Int? = nil, root: Int? = nil, fx: [String: Double]? = nil) {
        self.playFrom = playFrom
        self.playTo = playTo
        self.scale = scale
        self.root = root
        self.fx = fx
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
    public var version: Int = 2
    public var bpm: Double = 120
    public var scale: Int = 0
    public var root: Int = 0
    public var tracks: [Track]
    /// Строки сетки паттернов: имена и повторы.
    public var scenes: [SceneRow] = [SceneRow](repeating: SceneRow(), count: Params.patternSlots)
    /// Видимых строк (по умолчанию 1; заполненные видны всегда).
    public var rows: Int = 1
    /// Меню сетки: строка старта PLAY; в конце строк — STOP или LOOP.
    public var arrStart: Int = 0
    public var arrEndStop: Bool = false
    /// «+» под строками: true — копии играющих клипов (COPY PLAYING, по умолчанию), false — новые пустые.
    public var plusCopy: Bool = true
    /// LOOP ROW: играющая строка повторяется бесконечно (по умолчанию включена).
    public var rowLoop: Bool = true
    /// Стрелки ▲ ▼: false — только прокрутка (VIEW), true — при игре ещё и переход строки (SWITCH).
    public var arrowSwitch: Bool = false

    public init() {
        tracks = (0..<Params.trackCount).map { Track(index: $0) }
    }
}
