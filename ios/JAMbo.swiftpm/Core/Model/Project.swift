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
    /// Играющие страницы: playFrom…playTo.
    public var playFrom: Int = 0
    public var playTo: Int = 0
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

    public static func emptyPage() -> [Step] {
        return [Step](repeating: Step(), count: Params.stepsPerPage)
    }

    /// Шагов на странице p с учётом длины паттерна (как pageLen веба).
    public func pageLen(_ p: Int) -> Int {
        let n = Params.stepsPerPage
        if length > playFrom * n { return Swift.max(0, Swift.min(n, length - p * n)) }
        return n
    }

    /// Шагов в проходе: сумма длин играющих страниц.
    public var playLen: Int {
        var n = 0
        for p in playFrom...playTo { n += pageLen(p) }
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

public struct Project: Codable, Equatable, Sendable {
    public var version: Int = 2
    public var bpm: Double = 120
    public var scale: Int = 0
    public var root: Int = 0
    public var tracks: [Track]

    public init() {
        tracks = (0..<Params.trackCount).map { Track(index: $0) }
    }
}
