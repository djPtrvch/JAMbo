import Foundation

// Иконки движков (стиль Ink): перенос src/engineIcons.ts веба. Поле 64×64; elements(engine, v) — элементы иконки
// по ручкам 1.1, 1.2, 1.3 и Decay (0…1). Рисует UI (Canvas): один цвет темы, линия 1,4, скруглённые концы.
// Здесь — общие примитивы, формы своих движков — в EngineIconsJambo.swift.

/// Значения иконки 0…1: h — ручка 1.1, t — 1.2, m — 1.3, d — Decay 2.2; a — флаг a веба (у нас не задаётся).
public struct IconValues: Equatable, Sendable {
    public var h: Double
    public var t: Double
    public var m: Double
    public var d: Double
    public var a: Bool

    public init(h: Double = 0.5, t: Double = 0.5, m: Double = 0.5, d: Double = 0.5, a: Bool = false) {
        self.h = h
        self.t = t
        self.m = m
        self.d = d
        self.a = a
    }
}

/// Генератор rnd(seed) веба (mulberry32): та же последовательность, что в JS (арифметика по модулю 2^32).
struct IconRandom {
    private var s: UInt32

    init(_ seed: UInt32) { s = seed }

    mutating func next() -> Double {
        s &+= 0x6D2B79F5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296
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

/// Элемент иконки: контур, окружность (cx, cy, r) или текст; заливка, прозрачность, пунктир.
public struct IconElement: Sendable {
    public var cmds: [IconCmd] = []
    public var circle: (Double, Double, Double)? = nil
    public var text: String? = nil
    public var textX: Double = 0
    public var textY: Double = 0
    public var textSize: Double = 10
    public var fill = false
    public var opacity: Double? = nil
    public var dash = false

    init(_ cmds: [IconCmd], op: Double? = nil, fill: Bool = false, dash: Bool = false) {
        self.cmds = cmds
        opacity = op
        self.fill = fill
        self.dash = dash
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

    /// Ломаная: M p0 L p1 …
    static func pts(_ a: [(Double, Double)]) -> [IconCmd] {
        var c: [IconCmd] = []
        for (i, p) in a.enumerated() { c.append(i == 0 ? .move(p.0, p.1) : .line(p.0, p.1)) }
        return c
    }

    /// Точки x от x0 до x1 (n отрезков): y = f(x, u), u = 0…1.
    static func fx(_ x0: Double, _ x1: Double, _ n: Int, _ f: (Double, Double) -> Double) -> [(Double, Double)] {
        var a: [(Double, Double)] = []
        for i in 0...n {
            let u = Double(i) / Double(n)
            let x = x0 + (x1 - x0) * u
            a.append((x, f(x, u)))
        }
        return a
    }

    static func ring(_ cx: Double, _ cy: Double, _ r: Double, _ op: Double? = nil) -> IconElement {
        return IconElement(circle: (cx, cy, r), op: op)
    }

    static func dot(_ cx: Double, _ cy: Double, _ r: Double) -> IconElement {
        return IconElement(circle: (cx, cy, r), fill: true)
    }

    static func pol(_ cx: Double, _ cy: Double, _ r: Double, _ a: Double) -> (Double, Double) {
        return (cx + r * cos(a * Double.pi / 180), cy + r * sin(a * Double.pi / 180))
    }

    static func arc(_ cx: Double, _ cy: Double, _ r: Double, _ a0: Double, _ a1: Double) -> [IconCmd] {
        let p0 = pol(cx, cy, r, a0)
        let p1 = pol(cx, cy, r, a1)
        return [.move(p0.0, p0.1), .arc(r: r, large: abs(a1 - a0) > 180, x: p1.0, y: p1.1, cx: cx, cy: cy, a0: a0, a1: a1)]
    }

    static func fold(_ z: Double) -> Double { return (2 / Double.pi) * asin(sin(Double.pi / 2 * z)) }

    /// Остаток от деления, как % в JS (знак делимого).
    static func mod(_ a: Double, _ b: Double) -> Double { return a.truncatingRemainder(dividingBy: b) }

    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

    /// Math.round веба (половина — вверх).
    static func round(_ x: Double) -> Int { return Int((x + 0.5).rounded(.down)) }

    /// Элементы иконки своего движка (DRUM, ANALOG, FM); у других — пусто (у WTABLE — кадр таблицы).
    public static func elements(_ engine: Int, _ v: IconValues) -> [IconElement] {
        switch engine {
        case 16: return drumIcon(v)
        case 17: return analogIcon(v)
        case 18: return fmIcon(v)
        default: return []
        }
    }
}
