import Foundation

// Иконки (превью) своих движков: перенос docs/icons/prototype/engine-previews-prototype.html. Поле 64×64;
// elements(engine, v) — чистая функция ручек 1.1–1.4 и Decay 2.2 (0…1). Рисует UI (Canvas) двумя цветами темы:
// основной — сам звук, вторичный (серый) — то, что его формирует. Здесь — типы и общие примитивы контуров,
// колонки — в EngineIconsColumns.swift, ударные — в EngineIconsDrums.swift, синты — в EngineIconsJambo.swift.

/// Значения иконки 0…1: h — ручка 1.1, t — 1.2, m — 1.3, q — 1.4 (S12), d — Decay 2.2; a — флаг a веба (не задаётся).
public struct IconValues: Equatable, Sendable {
    public var h: Double
    public var t: Double
    public var m: Double
    public var q: Double
    public var d: Double
    public var a: Bool

    public init(h: Double = 0.5, t: Double = 0.5, m: Double = 0.5, q: Double = 0.5, d: Double = 0.5, a: Bool = false) {
        self.h = h
        self.t = t
        self.m = m
        self.q = q
        self.d = d
        self.a = a
    }
}

/// Команда контура (подмножество SVG path, как в источнике).
public enum IconCmd: Equatable, Sendable {
    case move(Double, Double)
    case line(Double, Double)
    case hTo(Double)
    case vTo(Double)
    case hBy(Double)
    case vBy(Double)
    /// Дуга окружности радиуса r до (x, y), по часовой (sweep 1); large — больше 180°. Для рисования — центр
    /// и углы (градусы, от a0 к a1 по возрастанию).
    case arc(r: Double, large: Bool, x: Double, y: Double, cx: Double, cy: Double, a0: Double, a1: Double)
    /// Относительная дуга эллипса «a rx ry 0 large sweep dx dy» — в иконках только половина эллипса (dy = 0,
    /// |dx| = 2·rx): sweep false — против часовой на экране.
    case arcBy(rx: Double, ry: Double, large: Bool, sweep: Bool, dx: Double, dy: Double)
    case close
}

/// Прямоугольник колонки на поле 64×64 (x, y — левый верхний угол).
public struct IconRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// Цвет элемента: основной (--icon: сам звук) или вторичный (--icon2, серый: ось, хвост Decay, фильтр, модулятор).
public enum IconInk: Sendable {
    case primary
    case secondary
}

/// Элемент иконки: контур, окружность (cx, cy, r), текст или колонки (прямоугольники одним путём, заливка);
/// цвет, заливка, прозрачность, пунктир.
public struct IconElement: Sendable {
    public var cmds: [IconCmd] = []
    public var rects: [IconRect] = []
    public var ink: IconInk = .primary
    public var circle: (Double, Double, Double)? = nil
    public var text: String? = nil
    public var textX: Double = 0
    public var textY: Double = 0
    public var textSize: Double = 10
    public var fill = false
    public var opacity: Double? = nil
    public var dash = false
    /// Плавное рисование (решение пользователя, вместо столбиков): волна генератора — сплошная фигура по всем
    /// точкам сигнала (wave — верхний край, waveBot — нижний, y на поле 64 от waveX0 до waveX1), contour —
    /// столбики огибающей ударных сглаженным контуром. rects остаются для сверки с прототипом.
    public var wave: [Double] = []
    public var waveBot: [Double] = []
    public var waveX0: Double = 4
    public var waveX1: Double = 60
    public var contour = false

    init(_ cmds: [IconCmd], op: Double? = nil, fill: Bool = false, dash: Bool = false, ink: IconInk = .primary) {
        self.cmds = cmds
        opacity = op
        self.fill = fill
        self.dash = dash
        self.ink = ink
    }

    /// Колонки: прямоугольники одним путём (перекрытия не темнеют), заливка цветом ink с прозрачностью op.
    init(rects: [IconRect], ink: IconInk = .primary, op: Double? = nil) {
        self.rects = rects
        self.ink = ink
        opacity = op
        fill = true
    }

    init(circle c: (Double, Double, Double), op: Double? = nil, fill: Bool = false) {
        circle = c
        opacity = op
        self.fill = fill
    }

    init(text: String, x: Double, y: Double, size: Double) {
        self.text = text
        textX = x
        textY = y
        textSize = size
        fill = true
    }
}

public enum EngineIcons {
    public static let stroke: Double = 1.4
    public static let size: Double = 64
    static let tau = Double.pi * 2

    static func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { return Swift.max(a, Swift.min(b, v)) }

    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

    /// Элементы иконки своего движка (16–26); у других — пусто. hx — центр подсветки удара (x на поле 64,
    /// только у ударных; nil — без подсветки). WTABLE здесь — по встроенной BASIC (в окне — wtableIcon с tableFrame таблицы дорожки).
    public static func elements(_ engine: Int, _ v: IconValues, hx: Double? = nil) -> [IconElement] {
        switch engine {
        case 16: return kickIcon(v, hx)
        case 17: return analogIcon(v)
        case 18: return fmIcon(v)
        case 19: return wtableIcon(v, basicFrame)
        case 20: return snareIcon(v, hx)
        case 21: return hatIcon(v, hx)
        case 22: return clapIcon(v, hx)
        case 23: return percIcon(v, hx)
        case 24: return subIcon(v)
        case 25: return textureIcon(v)
        case 26: return granularIcon(v)
        default: return []
        }
    }
}
