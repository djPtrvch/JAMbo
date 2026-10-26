import Foundation

// Аранжировщик (S15, docs/ai/arranger.md): данные таймлайна. Блоки — у дорожек (Track.blocks: переезжают,
// удаляются и копируются вместе с дорожкой), остальное — Project.arrange. Позиции и длины — в шагах транспорта
// (шестнадцатых, 16 на такт) от начала аранжировки.

/// Блок на дорожке: ссылка на клип (ячейку столбца сетки паттернов), начало и длина в шагах; offset — с какого шага
/// прохода клипа начинается блок (0 — с первого; правая часть блока, у которого заменили середину, — дальше).
public struct ArrBlock: Codable, Equatable, Sendable {
    public var clip: Int
    public var start: Int
    public var length: Int
    public var offset: Int = 0

    public init(clip: Int, start: Int, length: Int, offset: Int = 0) {
        self.clip = clip
        self.start = start
        self.length = length
        self.offset = offset
    }

    public var end: Int { return start + length }
}

/// Маркер секции: позиция в шагах, имя (до 12 знаков) и цвет (номер в палитре).
public struct ArrMarker: Codable, Equatable, Sendable {
    public var at: Int
    public var name: String = ""
    public var color: Int = ArrPalette.defaultColor
    /// Конец секции (шаги; S15d, решение пользователя: секция из выделенного диапазона — ровно этот диапазон);
    /// nil — до следующего маркера.
    public var end: Int? = nil

    public init(at: Int, name: String = "", color: Int = ArrPalette.defaultColor, end: Int? = nil) {
        self.at = at
        self.name = name
        self.color = color
        self.end = end
    }
}

/// Палитра дорожек и маркеров: 20 цветов (сами цвета — в UI), по умолчанию Light grey; в меню выбора — без белого
/// (Off-white) и без цвета по умолчанию (он — пункт DEFAULT).
public enum ArrPalette {
    public static let count = 20
    public static let defaultColor = 17
    public static let white = 16
    /// Убран из выбора (решение пользователя); дорожки с ним прежние так и рисуются.
    public static let removed = 3
    public static var choices: [Int] {
        return (0..<count).filter { $0 != white && $0 != defaultColor && $0 != removed }
    }
}

/// Шаг сетки таймлайна: 1 BAR, 1/2, 1/4, 1 STEP.
public enum ArrGrid {
    public static let names: [String] = ["1 BAR", "1/2", "1/4", "1 STEP"]
    public static let steps: [Int] = [16, 8, 4, 1]
    public static let stepsPerBar = 16
}

/// Референс-трек (S15g): сэмпл в хранилище по ключу (в библиотеке не показывается), имя файла, сдвиг начала файла
/// от начала таймлайна (секунды; файл играет в своём темпе), громкость (dB, регулятор измерителя в положении B).
public struct ArrRef: Codable, Equatable, Sendable {
    public var key: String
    public var name: String = ""
    public var offset: Double = 0
    public var gain: Double = 0

    public init(key: String, name: String = "", offset: Double = 0, gain: Double = 0) {
        self.key = key
        self.name = name
        self.offset = offset
        self.gain = gain
    }
}

/// Общие данные аранжировки (кроме блоков): маркеры, петля, сетка и магнит, STEPS, референс.
public struct Arrangement: Codable, Equatable, Sendable {
    public var markers: [ArrMarker] = []
    /// Петля: диапазон [loopFrom, loopTo) в шагах (запоминается и при выключенной), loop — зацикливание.
    public var loopFrom: Int = 0
    public var loopTo: Int = 0
    public var loop: Bool = false
    /// Номер шага сетки (ArrGrid), магнит (привязка к линиям сетки).
    public var grid: Int = 2
    public var snap: Bool = true
    /// STEPS: секвенсор и клавиатура скрыты, окно аранжировщика выше.
    public var hideSteps: Bool = false
    /// Референс (nil — нет файла) и строка REF над дорожками (кнопка REF).
    public var ref: ArrRef? = nil
    public var showRef: Bool = false

    public init() {}

    /// Шаг сетки в шагах транспорта.
    public var gridSteps: Int { return ArrGrid.steps[Swift.max(0, Swift.min(grid, ArrGrid.steps.count - 1))] }

    /// Позиция с учётом магнита: ближайшая линия сетки (без магнита — как есть, точность — шаг).
    public func snapped(_ x: Int) -> Int {
        if !snap { return Swift.max(0, x) }
        let g: Int = gridSteps
        let r: Int = (Swift.max(0, x) + g / 2) / g
        return r * g
    }

    public var hasLoop: Bool { return loopTo > loopFrom }
}

extension ArrBlock {
    enum CodingKeys: String, CodingKey, CaseIterable { case clip, start, length, offset }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = c.value(.clip, 0)
        start = c.value(.start, 0)
        length = c.value(.length, ArrGrid.stepsPerBar)
        offset = c.value(.offset, 0)
    }
}

extension ArrMarker {
    enum CodingKeys: String, CodingKey, CaseIterable { case at, name, color, end }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = c.value(.at, 0)
        name = c.value(.name, "")
        color = c.value(.color, ArrPalette.defaultColor)
        end = c.optional(.end)
    }
}

extension Arrangement {
    enum CodingKeys: String, CodingKey, CaseIterable { case markers, loopFrom, loopTo, loop, grid, snap, hideSteps, ref, showRef }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        markers = c.value(.markers, [ArrMarker]())
        loopFrom = c.value(.loopFrom, 0)
        loopTo = c.value(.loopTo, 0)
        loop = c.value(.loop, false)
        grid = c.value(.grid, 2)
        snap = c.value(.snap, true)
        hideSteps = c.value(.hideSteps, false)
        ref = c.optional(.ref)
        showRef = c.value(.showRef, false)
    }

    /// После чтения: маркеры по порядку, в пределах; петля и сетка — в пределах.
    public mutating func repair() {
        for k in markers.indices {
            markers[k].at = Swift.max(0, markers[k].at)
            markers[k].name = String(markers[k].name.prefix(12))
            if markers[k].color < 0 || markers[k].color >= ArrPalette.count { markers[k].color = ArrPalette.defaultColor }
            if let e = markers[k].end, e <= markers[k].at { markers[k].end = nil }
        }
        markers.sort { $0.at < $1.at }
        loopFrom = Swift.max(0, loopFrom)
        if loopTo <= loopFrom {
            loopTo = loopFrom
            loop = false
        }
        grid = Swift.max(0, Swift.min(grid, ArrGrid.steps.count - 1))
        if let r = ref {
            if r.key.isEmpty {
                ref = nil
            } else {
                ref?.offset = r.offset.isFinite ? r.offset : 0
                ref?.gain = r.gain.isFinite ? Swift.max(Params.volMin, Swift.min(0, r.gain)) : 0
            }
        }
    }
}
