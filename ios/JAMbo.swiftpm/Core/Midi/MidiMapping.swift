import Foundation

// MIDI-маппинг (S13b): источник (CC или нота на канале) → цель (ручка сетки по
// позиции, нажатие ручки — PRESS, кнопка интерфейса по имени). Хранится в настройках (MidiSettings.mappings).

public enum MidiSourceType: String, Codable, Sendable {
    case cc
    case note
}

/// Источник: CC или нота, канал 0–15, номер 0–127.
public struct MidiSource: Codable, Equatable, Hashable, Sendable {
    public var type: MidiSourceType
    public var ch: Int
    public var num: Int

    public init(type: MidiSourceType, ch: Int, num: Int) {
        self.type = type
        self.ch = ch
        self.num = num
    }

    /// Метка у цели на экране: «CC 20», «N 36».
    public var short: String { return (type == .cc ? "CC " : "N ") + String(num) }
    /// В списке маппингов: «CC 20 · CH 1».
    public var label: String { return (type == .cc ? "CC " : "NOTE ") + "\(num) · CH \(ch + 1)" }
}

/// Цель: ручка сетки 4×4 (позиция 0–15, ряд за рядом), нажатие ручки (S13b, решение пользователя) или кнопка по имени.
public enum MidiTarget: Codable, Equatable, Hashable, Sendable {
    case knob(Int)
    case press(Int)
    case button(String)

    // Запись — как у синтезированной (имя случая и "_0"), но одной общей функцией CaseCoding: объём сборки (18.11).
    public init(from decoder: Decoder) throws {
        let (name, p) = try CaseCoding.decode(decoder)
        switch name {
        case "knob": self = .knob(try p.decode(Int.self, forKey: CaseKey.payload))
        case "press": self = .press(try p.decode(Int.self, forKey: CaseKey.payload))
        case "button": self = .button(try p.decode(String.self, forKey: CaseKey.payload))
        default: throw CaseCoding.bad(decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .knob(let s): try CaseCoding.encode(encoder, "knob", int: s)
        case .press(let s): try CaseCoding.encode(encoder, "press", int: s)
        case .button(let n): try CaseCoding.encode(encoder, "button", string: n)
        }
    }

    /// KNOB строка.место (группа.ручка, как в описании сетки; 8.11 — группы в строках, прежде в столбцах); у нажатия — KNOB 2.1 PRESS.
    public var label: String {
        switch self {
        case .knob(let s): return MidiTarget.knobName(s)
        case .press(let s): return MidiTarget.knobName(s) + " PRESS"
        case .button(let n): return n
        }
    }

    static func knobName(_ s: Int) -> String {
        return "KNOB \(s / 4 + 1).\(s % 4 + 1)"
    }

    /// Кроссфейдер перехода MIX (S13, решение пользователя): строка, закреплённая в списке маппингов; по умолчанию GLOBAL.
    public static let crossfader = MidiTarget.button("XFADER")

    /// Ячейки, строки и стрелки сетки паттернов — их маппинги в условии Clip launcher (по умолчанию) или GLOBAL
    /// (запуск паттернов и при закрытой сетке; решение пользователя), без Current page.
    public var isClip: Bool {
        guard case .button(let n) = self else { return false }
        return n.hasPrefix("CLIP ") || n.hasPrefix("ROW ") || n.hasPrefix("GRID ")
    }

    /// Ключ для словарей и хранения состояния toggle.
    public var key: String {
        switch self {
        case .knob(let s): return "knob:\(s)"
        case .press(let s): return "press:\(s)"
        case .button(let n): return "btn:" + n
        }
    }
}

/// Тип управления: кнопка (MOMENTARY — пока нажата, TOGGLE — нажатие включает, следующее выключает, LATCH —
/// переключатель на контроллере: 127 — включено, 0 — выключено, кнопка приложения принимает это состояние),
/// ABSOLUTE — значение 0–127, RELATIVE — энкодер шлёт шаги.
public enum MidiControl: String, Codable, CaseIterable, Sendable {
    case momentary
    case toggle
    case latch
    case abs
    case rel

    public var title: String {
        switch self {
        case .momentary: return "Button momentary"
        case .toggle: return "Button toggle"
        case .latch: return "Button latch"
        case .abs: return "Continuous absolute"
        case .rel: return "Continuous relative"
        }
    }
}

/// Как энкодер кодирует шаг: Offset 64 (65 вверх, 63 вниз), 2’s complement (1 вверх, 127 вниз), Signed bit (1 вверх, 65 вниз).
public enum MidiEncoder: String, Codable, CaseIterable, Sendable {
    case offset
    case twos
    case signed

    public func step(_ v: Int) -> Int {
        switch self {
        case .offset: return v - 64
        case .twos: return v < 64 ? v : v - 128
        case .signed: return (v & 64) != 0 ? -(v & 63) : (v & 63)
        }
    }
}

public enum MidiCond: String, Codable, Sendable {
    case global
    case page
    case clip
}

/// Страница сетки ручек условия Current page.
public enum MidiPage: String, Codable, CaseIterable, Sendable {
    case track
    case fx
    case mod
    case mix
    case master

    public var title: String { return self == .master ? "MST" : rawValue.uppercased() }
}

/// Место параметра глобального маппинга ручки (решение пользователя, S13): страница и дорожка, где назначили. GLOBAL —
/// всегда этот параметр (громкость T3 в MIX — только она, что бы ни было на экране); у MIX и MST дорожка не важна.
public struct MidiPlace: Codable, Equatable, Hashable, Sendable {
    public var page: MidiPage
    public var track: Int

    public init(page: MidiPage, track: Int) {
        self.page = page
        self.track = track
    }

    /// Сетка ручек показывает этот параметр сейчас.
    public func matches(_ ctx: MidiContext) -> Bool {
        if page != ctx.page { return false }
        return page == .mix || page == .master || track == ctx.track
    }
}

/// Порт обратной связи: по умолчанию (DEVICES → FEEDBACK OUTPUT), нет, выход по uniqueID или все выходы контроллера
/// по его имени (Controllers; встроенные пресеты: два пэда JAMboPAD — два выхода).
public enum MidiPort: Codable, Equatable, Sendable {
    case standard
    case none
    case device(Int32)
    case controller(String)

    public init(from decoder: Decoder) throws {
        let (name, p) = try CaseCoding.decode(decoder)
        switch name {
        case "standard": self = .standard
        case "none": self = .none
        case "device": self = .device(try p.decode(Int32.self, forKey: CaseKey.payload))
        case "controller": self = .controller(try p.decode(String.self, forKey: CaseKey.payload))
        default: throw CaseCoding.bad(decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .standard: try CaseCoding.encode(encoder, "standard")
        case .none: try CaseCoding.encode(encoder, "none")
        case .device(let id): try CaseCoding.encode(encoder, "device", int: Int(id))
        case .controller(let n): try CaseCoding.encode(encoder, "controller", string: n)
        }
    }
}

/// Что делает нажатие ручки (цель PRESS; строка Action окна MIDI MAP): сброс к значению по умолчанию (как двойной
/// тап, по умолчанию), параметр этой позиции — Max при нажатии, Min при отпускании, или кнопка интерфейса.
public enum MidiPressAction: Codable, Equatable, Sendable {
    case reset
    case param
    case button(String)

    public init(from decoder: Decoder) throws {
        let (name, p) = try CaseCoding.decode(decoder)
        switch name {
        case "reset": self = .reset
        case "param": self = .param
        case "button": self = .button(try p.decode(String.self, forKey: CaseKey.payload))
        default: throw CaseCoding.bad(decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .reset: try CaseCoding.encode(encoder, "reset")
        case .param: try CaseCoding.encode(encoder, "param")
        case .button(let n): try CaseCoding.encode(encoder, "button", string: n)
        }
    }
}

public struct MidiMapping: Codable, Equatable, Sendable {
    public var src: MidiSource
    public var target: MidiTarget
    public var control: MidiControl = .momentary
    public var enc: MidiEncoder = .offset
    /// Диапазон 0–1: min — при 0, max — при 127 (min > max — инвертировано).
    public var min: Double = 0
    public var max: Double = 1
    /// Вход, с которого слушать: nil — любой.
    public var input: Int32? = nil
    public var cond: MidiCond = .global
    public var page: MidiPage = .track
    public var port: MidiPort = .standard
    /// Только у цели PRESS.
    public var press: MidiPressAction = .reset
    /// Ручка в условии GLOBAL — параметр этого места (nil — у остальных).
    public var place: MidiPlace? = nil

    public init(src: MidiSource, target: MidiTarget, continuous: Bool) {
        self.src = src
        self.target = target
        self.control = continuous ? .abs : .momentary
    }


    /// Недостающие поля — по умолчанию; без источника или цели — ошибка (маппинг пропускается).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        src = try c.decode(MidiSource.self, forKey: CaseKey("src"))
        target = try c.decode(MidiTarget.self, forKey: CaseKey("target"))
        control = c.value(CaseKey("control"), .momentary)
        enc = c.value(CaseKey("enc"), .offset)
        min = c.value(CaseKey("min"), 0)
        max = c.value(CaseKey("max"), 1)
        input = c.optional(CaseKey("input"))
        cond = c.value(CaseKey("cond"), .global)
        page = c.value(CaseKey("page"), .track)
        port = c.value(CaseKey("port"), .standard)
        press = c.value(CaseKey("press"), .reset)
        place = c.optional(CaseKey("place"))
        if target.isClip && cond == .page { cond = .clip }
    }

    /// Ключ условия: global, clip или page:<страница>.
    public var condKey: String { return cond == .page ? "page:" + page.rawValue : cond.rawValue }

    /// Маппинг относится к цели в этом контексте: у глобальной ручки — только на своём месте.
    public func fits(_ ctx: MidiContext) -> Bool {
        guard let p = place else { return true }
        return p.matches(ctx)
    }

    /// Ручка GLOBAL — параметр места ctx; другие условия места не хранят.
    mutating func fixPlace(_ ctx: MidiContext, force: Bool) {
        guard case .knob = target, cond == .global else {
            place = nil
            return
        }
        if force || place == nil { place = MidiPlace(page: ctx.page, track: ctx.track) }
    }

    /// Маппинги делят источник: тот же источник, то же условие и пересекающиеся входы.
    public func clashes(_ o: MidiMapping) -> Bool {
        guard src == o.src && condKey == o.condKey else { return false }
        guard let a = input, let b = o.input else { return true }
        return a == b
    }

    /// Шаг энкодера (RELATIVE) в долях хода ручки: 1/128 на щелчок, с учётом Invert.
    public func relStep(_ v: Int) -> Double {
        let dir: Double = max >= min ? 1 : -1
        return dir * Double(enc.step(v)) / 128
    }

    /// Значение после шага энкодера — в пределах диапазона.
    public func clamp(_ v: Double) -> Double {
        let lo: Double = Swift.min(min, max)
        let hi: Double = Swift.max(min, max)
        return Swift.min(hi, Swift.max(lo, v))
    }

    /// Положение 0–1 входа (ABSOLUTE и кнопки) → значение в диапазоне.
    public func value(at: Double) -> Double {
        return min + at * (max - min)
    }
}

/// Для массива маппингов: ошибочные элементы пропускаются, остальные читаются.
struct LossyMapping: Decodable {
    let value: MidiMapping?

    init(from decoder: Decoder) throws {
        value = try? MidiMapping(from: decoder)
    }
}

/// Ключ записи случаев перечислений: имя случая и "_0" (значение), как у синтезированной Codable.
struct CaseKey: CodingKey {
    let stringValue: String
    var intValue: Int? { return nil }

    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }

    static let payload = CaseKey("_0")
}

/// Запись перечислений со значениями одной функцией вместо синтезированной (у той — свои CodingKeys на каждый
/// случай со всеми соответствиями: объём сборки). Формат прежний: {"knob":{"_0":3}}, {"standard":{}}.
enum CaseCoding {
    static func encode(_ encoder: Encoder, _ name: String, int: Int? = nil, string: String? = nil) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        var n = c.nestedContainer(keyedBy: CaseKey.self, forKey: CaseKey(name))
        if let i = int { try n.encode(i, forKey: CaseKey.payload) }
        if let t = string { try n.encode(t, forKey: CaseKey.payload) }
    }

    /// Имя случая и его значения; ключ должен быть ровно один.
    static func decode(_ decoder: Decoder) throws -> (String, KeyedDecodingContainer<CaseKey>) {
        let c = try decoder.container(keyedBy: CaseKey.self)
        guard c.allKeys.count == 1, let k = c.allKeys.first else { throw bad(decoder) }
        return (k.stringValue, try c.nestedContainer(keyedBy: CaseKey.self, forKey: k))
    }

    static func bad(_ decoder: Decoder) -> Error {
        return DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                                                                 debugDescription: "unknown case"))
    }
}

// Запись — как у синтезированной, но без своего перечисления CodingKeys (общий CaseKey; объём сборки, 18.11).
extension MidiSource {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        type = try c.decode(MidiSourceType.self, forKey: CaseKey("type"))
        ch = try c.decode(Int.self, forKey: CaseKey("ch"))
        num = try c.decode(Int.self, forKey: CaseKey("num"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(type, forKey: CaseKey("type"))
        try c.encode(ch, forKey: CaseKey("ch"))
        try c.encode(num, forKey: CaseKey("num"))
    }
}

// Запись — как у синтезированной, но без своего перечисления CodingKeys (общий CaseKey; объём сборки, 18.11).
extension MidiPlace {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        page = try c.decode(MidiPage.self, forKey: CaseKey("page"))
        track = try c.decode(Int.self, forKey: CaseKey("track"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(page, forKey: CaseKey("page"))
        try c.encode(track, forKey: CaseKey("track"))
    }
}

extension MidiMapping {
    /// Запись — как прежняя синтезированная, по тем же ключам (общий CaseKey; объём сборки, 18.11).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(src, forKey: CaseKey("src"))
        try c.encode(target, forKey: CaseKey("target"))
        try c.encode(control, forKey: CaseKey("control"))
        try c.encode(enc, forKey: CaseKey("enc"))
        try c.encode(min, forKey: CaseKey("min"))
        try c.encode(max, forKey: CaseKey("max"))
        try c.encodeIfPresent(input, forKey: CaseKey("input"))
        try c.encode(cond, forKey: CaseKey("cond"))
        try c.encode(page, forKey: CaseKey("page"))
        try c.encode(port, forKey: CaseKey("port"))
        try c.encode(press, forKey: CaseKey("press"))
        try c.encodeIfPresent(place, forKey: CaseKey("place"))
    }
}
