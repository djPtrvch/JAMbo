// Capture (как в Live): ноты, сыгранные без REC, запоминаются; ▲ + ▼ ставит последнюю фразу в паттерн дорожки.

/// Сыгранная нота для Capture: шаг паттерна (с игрой — от начала клипа, без счёта по кругу; без игры — от первой
/// ноты по BPM), ноты (аккорд — вместе), сила (nil — без KEY VELOCITY), длина в шагах.
public struct PhraseNote: Equatable, Sendable {
    public var step: Int
    public var notes: [Int]
    public var velocity: Double?
    public var len: Int

    public init(step: Int, notes: [Int], velocity: Double? = nil, len: Int = 1) {
        self.step = step
        self.notes = notes
        self.velocity = velocity
        self.len = Swift.max(1, len)
    }
}

public enum NoteCapture {
    /// Пауза, после которой начинается новая фраза (шагов без нажатий).
    public static let gap: Int = 16
    /// Длины паттерна для пустого паттерна (страниц).
    public static let lengths: [Int] = [1, 2, 4, 8]

    /// Фраза: ноты после последней паузы ≥ 16 шагов; не длиннее 8 страниц от страницы первой ноты
    /// (ранние ноты отбрасываются).
    public static func phrase(_ all: [PhraseNote]) -> [PhraseNote] {
        let s: [PhraseNote] = all.enumerated().sorted { a, b in
            a.element.step != b.element.step ? a.element.step < b.element.step : a.offset < b.offset
        }.map { $0.element }
        guard !s.isEmpty else { return [] }
        var start: Int = 0
        var end: Int = s[0].step + s[0].len
        for i in 1..<s.count {
            if s[i].step - end >= gap { start = i }
            end = Swift.max(end, s[i].step + s[i].len)
        }
        var p: [PhraseNote] = Array(s[start...])
        let n: Int = Params.stepsPerPage
        let maxSteps: Int = Params.maxPages * n
        let last: Int = p[p.count - 1].step
        while let f = p.first, last - pageStart(f.step) >= maxSteps { p.removeFirst() }
        return p
    }

    /// Начало страницы шага (шаг может быть отрицательным — до начала клипа).
    static func pageStart(_ step: Int) -> Int {
        let n: Int = Params.stepsPerPage
        let p: Int = step >= 0 ? step / n : -((-step + n - 1) / n)
        return p * n
    }

    /// Страниц у пустого паттерна: наименьшая из 1, 2, 4, 8, в которую входит фраза от страницы первой ноты.
    public static func pages(_ phrase: [PhraseNote]) -> Int {
        guard let f = phrase.first, let l = phrase.last else { return 1 }
        let need: Int = l.step - pageStart(f.step) + 1
        let n: Int = Params.stepsPerPage
        return lengths.first { $0 * n >= need } ?? Params.maxPages
    }
}

extension Track {
    /// Capture в открытый клип: ноты добавляются к стоящим (как OVERDUB), на шаг по месту в проходе (по кругу).
    /// Паттерн без тригов — длина по фразе (1, 2, 4 или 8 страниц, играют все). false — ловить нечего.
    @discardableResult
    public mutating func capture(_ phrase: [PhraseNote]) -> Bool {
        if phrase.isEmpty { return false }
        let empty: Bool = !pages.contains { page in page.contains { $0.on } }
        if empty {
            let count: Int = NoteCapture.pages(phrase)
            var pg: [[Step]] = Array(pages.prefix(count))
            while pg.count < count { pg.append(Track.emptyPage()) }
            pages = pg
            length = count * Params.stepsPerPage
            playFrom = 0
            playTo = count - 1
        }
        // Сначала ноты, потом длины: запись нот на шаг сбрасывает его длину (аккорд — по самой длинной ноте).
        for p in phrase {
            recordNotes(playIndex(p.step), p.notes, merge: true, overdub: true, velocity: p.velocity)
        }
        for p in phrase { recordLength(playIndex(p.step), p.len) }
        return true
    }
}
