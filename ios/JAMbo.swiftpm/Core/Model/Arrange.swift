import Foundation

// Аранжировщик (S15, docs/ai/arranger.md): данные таймлайна. Блоки — у дорожек (Track.blocks: переезжают,
// удаляются и копируются вместе с дорожкой), остальное — Project.arrange. Позиции и длины — в шагах транспорта
// (шестнадцатых, 16 на такт) от начала аранжировки.

/// Блок на дорожке: клип (ячейка столбца сетки паттернов, откуда он взят), начало и длина в шагах; offset — с какого
/// шага прохода клипа начинается блок (0 — с первого; правая часть блока, у которого заменили середину, — дальше).
/// pattern — своя копия клипа (решение пользователя: блок не зависит от сетки — правка клипа в сетке блок не меняет,
/// правка блока в STEPS аранжировщика не меняет сетку); nil — блок играет клип сетки (прежние проекты, тесты).
public struct ArrBlock: Codable, Equatable, Sendable {
    public var clip: Int
    public var start: Int
    public var length: Int
    public var offset: Int = 0
    /// Своя копия клипа блока — «в коробке» (массив из 0 или 1 элемента, копия при записи): копии и сравнения блока
    /// не тянут весь клип по значению (объём сборки: функции копирования вложенных структур, 8.11).
    var patternBox: [Clip] = []
    public var pattern: Clip? {
        get { return patternBox.first }
        set { patternBox = newValue.map { [$0] } ?? [] }
    }
    /// Автоматизация блока (решение пользователя, 1.11): кривые ручек, x — шаг от начала блока; едут, копируются и
    /// удаляются вместе с блоком.
    public var autos: [ArrAutoLane] = []
    /// LINK прежних проектов (1.11, убран — решение пользователя: блоки не соединяются): только при чтении, потом —
    /// точки на стыке (Track.dropLegacyLinks); не пишется.
    var legacyLink: Bool = false

    public init(clip: Int, start: Int, length: Int, offset: Int = 0, pattern: Clip? = nil) {
        self.clip = clip
        self.start = start
        self.length = length
        self.offset = offset
        self.pattern = pattern
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
/// от начала таймлайна (секунды; файл играет в своём темпе), громкость (dB, регулятор измерителя в положении B), темп
/// файла (TempoDetect при загрузке; nil — ещё не определён, 0 — не нашёлся).
public struct ArrRef: Codable, Equatable, Sendable {
    public var key: String
    public var name: String = ""
    public var offset: Double = 0
    public var gain: Double = 0
    public var bpm: Double? = nil

    public init(key: String, name: String = "", offset: Double = 0, gain: Double = 0, bpm: Double? = nil) {
        self.key = key
        self.name = name
        self.offset = offset
        self.gain = gain
        self.bpm = bpm
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        clip = c.value(CaseKey("clip"), 0)
        start = c.value(CaseKey("start"), 0)
        length = c.value(CaseKey("length"), ArrGrid.stepsPerBar)
        offset = c.value(CaseKey("offset"), 0)
        pattern = c.optional(CaseKey("pattern"))
        autos = c.value(CaseKey("autos"), [ArrAutoLane]())
        legacyLink = (try? c.decodeIfPresent(Bool.self, forKey: CaseKey("autoLink"))) ?? false
    }

    /// Запись — как прежняя синтезированная (pattern — только если есть; legacyLink не пишется).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(clip, forKey: CaseKey("clip"))
        try c.encode(start, forKey: CaseKey("start"))
        try c.encode(length, forKey: CaseKey("length"))
        try c.encode(offset, forKey: CaseKey("offset"))
        try c.encodeIfPresent(pattern, forKey: CaseKey("pattern"))
        try c.encode(autos, forKey: CaseKey("autos"))
    }

    /// Начало блока сдвинулось на d шагов вправо (TRIM слева, правая часть разреза): точки — на прежних местах таймлайна.
    mutating func shiftAutos(_ d: Int) {
        if d == 0 || autos.isEmpty { return }
        let dx: Double = Double(d)
        for l in autos.indices {
            for i in autos[l].points.indices { autos[l].points[i].x -= dx }
        }
    }

    /// Точка на шаге x блока (y) у кривой ручки param, если там точки ещё нет (строки нет — появляется).
    mutating func pinAuto(_ param: String, x: Double, y: Double) {
        if let l = autos.firstIndex(where: { $0.param == param }) {
            if autos[l].points.contains(where: { $0.x == x }) { return }
            let k: Int = autos[l].points.firstIndex { $0.x > x } ?? autos[l].points.count
            autos[l].points.insert(ArrAutoPoint(x: x, y: y), at: k)
        } else {
            autos.append(ArrAutoLane(param: param, points: [ArrAutoPoint(x: x, y: y)]))
        }
    }

    /// Разрез на шаге x блока (TRIM, INSERT, замена середины): у кривых, которые через x проходят, — точка на x, чтобы
    /// обе части звучали как до разреза (блоки не соединяются — решение пользователя).
    mutating func pinCut(_ x: Int) {
        let cx: Double = Double(x)
        for l in autos {
            if let v = ArrAutoLane.value(l.points, at: cx) { pinAuto(l.param, x: cx, y: v) }
        }
    }
}

extension ArrMarker {

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        at = c.value(CaseKey("at"), 0)
        name = c.value(CaseKey("name"), "")
        color = c.value(CaseKey("color"), ArrPalette.defaultColor)
        end = c.optional(CaseKey("end"))
    }
}

extension Arrangement {

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        markers = c.value(CaseKey("markers"), [ArrMarker]())
        loopFrom = c.value(CaseKey("loopFrom"), 0)
        loopTo = c.value(CaseKey("loopTo"), 0)
        loop = c.value(CaseKey("loop"), false)
        grid = c.value(CaseKey("grid"), 2)
        snap = c.value(CaseKey("snap"), true)
        hideSteps = c.value(CaseKey("hideSteps"), false)
        ref = c.optional(CaseKey("ref"))
        showRef = c.value(CaseKey("showRef"), false)
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
                if let b = r.bpm, !b.isFinite || b < 0 { ref?.bpm = nil }
            }
        }
    }
}

extension Track {
    /// Клип, который играет блок: своя копия, иначе клип сетки (nil — ячейка пуста).
    public func blockClip(_ b: ArrBlock) -> Clip? {
        if let c = b.pattern { return c }
        return b.clip >= 0 && b.clip < clips.count ? clips[b.clip] : nil
    }

    /// У каждого блока — своя копия клипа (решение пользователя): блоки без копии получают копию клипа сетки на этот
    /// момент. true — что-то поменялось.
    @discardableResult
    public mutating func ownArrPatterns() -> Bool {
        var changed: Bool = false
        for i in blocks.indices where blocks[i].pattern == nil {
            let k: Int = blocks[i].clip
            guard k >= 0 && k < clips.count, let c = clips[k] else { continue }
            var copy: Clip = c
            // Звук перехода MIX (PREV) — у клипа сетки, не у блока.
            copy.src = nil
            blocks[i].pattern = copy
            changed = true
        }
        return changed
    }
}

extension Project {
    /// Все блоки — со своей копией клипа (после правки и при открытии проекта).
    @discardableResult
    public mutating func ownArrPatterns() -> Bool {
        var changed: Bool = false
        for t in tracks.indices where !tracks[t].blocks.isEmpty {
            if tracks[t].blocks.contains(where: { $0.pattern == nil }) && tracks[t].ownArrPatterns() { changed = true }
        }
        return changed
    }
}

// Запись — как у синтезированной, но без своего перечисления CodingKeys (общий CaseKey; объём сборки, 18.11).
extension ArrRef {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        key = try c.decode(String.self, forKey: CaseKey("key"))
        name = try c.decode(String.self, forKey: CaseKey("name"))
        offset = try c.decode(Double.self, forKey: CaseKey("offset"))
        gain = try c.decode(Double.self, forKey: CaseKey("gain"))
        bpm = try c.decodeIfPresent(Double.self, forKey: CaseKey("bpm"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(key, forKey: CaseKey("key"))
        try c.encode(name, forKey: CaseKey("name"))
        try c.encode(offset, forKey: CaseKey("offset"))
        try c.encode(gain, forKey: CaseKey("gain"))
        try c.encodeIfPresent(bpm, forKey: CaseKey("bpm"))
    }
}

extension ArrMarker {
    /// Запись — как прежняя синтезированная, по тем же ключам (общий CaseKey; объём сборки, 18.11).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(at, forKey: CaseKey("at"))
        try c.encode(name, forKey: CaseKey("name"))
        try c.encode(color, forKey: CaseKey("color"))
        try c.encodeIfPresent(end, forKey: CaseKey("end"))
    }
}

extension Arrangement {
    /// Запись — как прежняя синтезированная, по тем же ключам (общий CaseKey; объём сборки, 18.11).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(markers, forKey: CaseKey("markers"))
        try c.encode(loopFrom, forKey: CaseKey("loopFrom"))
        try c.encode(loopTo, forKey: CaseKey("loopTo"))
        try c.encode(loop, forKey: CaseKey("loop"))
        try c.encode(grid, forKey: CaseKey("grid"))
        try c.encode(snap, forKey: CaseKey("snap"))
        try c.encode(hideSteps, forKey: CaseKey("hideSteps"))
        try c.encodeIfPresent(ref, forKey: CaseKey("ref"))
        try c.encode(showRef, forKey: CaseKey("showRef"))
    }
}
