import Foundation

// MIDI-маппинг (S13b, как MidiMapping в settings.ts веба): источник (CC или нота на канале) → цель (ручка сетки по
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

    /// KNOB столбец.ряд, как в описании сетки; у нажатия — KNOB 2.1 PRESS.
    public var label: String {
        switch self {
        case .knob(let s): return MidiTarget.knobName(s)
        case .press(let s): return MidiTarget.knobName(s) + " PRESS"
        case .button(let n): return n
        }
    }

    static func knobName(_ s: Int) -> String {
        return "KNOB \(s % 4 + 1).\(s / 4 + 1)"
    }

    /// Ячейки, строки и стрелки сетки паттернов — их маппинги всегда в условии Clip launcher.
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

/// Тип управления: кнопка (MOMENTARY — пока нажата, TOGGLE — нажатие включает, следующее выключает),
/// ABSOLUTE — значение 0–127, RELATIVE — энкодер шлёт шаги.
public enum MidiControl: String, Codable, CaseIterable, Sendable {
    case momentary
    case toggle
    case abs
    case rel

    public var title: String {
        switch self {
        case .momentary: return "Button momentary"
        case .toggle: return "Button toggle"
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

/// Порт обратной связи: по умолчанию (DEVICES → FEEDBACK OUTPUT), нет или выход по uniqueID.
public enum MidiPort: Codable, Equatable, Sendable {
    case standard
    case none
    case device(Int32)
}

/// Что делает нажатие ручки (цель PRESS; строка Action окна MIDI MAP): сброс к значению по умолчанию (как двойной
/// тап, по умолчанию), параметр этой позиции — Max при нажатии, Min при отпускании, или кнопка интерфейса.
public enum MidiPressAction: Codable, Equatable, Sendable {
    case reset
    case param
    case button(String)
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

    private enum Keys: String, CodingKey { case src, target, control, enc, min, max, input, cond, page, port, press, place }

    /// Недостающие поля — по умолчанию; без источника или цели — ошибка (маппинг пропускается).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        src = try c.decode(MidiSource.self, forKey: .src)
        target = try c.decode(MidiTarget.self, forKey: .target)
        control = (try? c.decode(MidiControl.self, forKey: .control)) ?? .momentary
        enc = (try? c.decode(MidiEncoder.self, forKey: .enc)) ?? .offset
        min = (try? c.decode(Double.self, forKey: .min)) ?? 0
        max = (try? c.decode(Double.self, forKey: .max)) ?? 1
        input = try? c.decode(Int32.self, forKey: .input)
        cond = (try? c.decode(MidiCond.self, forKey: .cond)) ?? .global
        page = (try? c.decode(MidiPage.self, forKey: .page)) ?? .track
        port = (try? c.decode(MidiPort.self, forKey: .port)) ?? .standard
        press = (try? c.decode(MidiPressAction.self, forKey: .press)) ?? .reset
        place = try? c.decode(MidiPlace.self, forKey: .place)
        if target.isClip { cond = .clip }
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
