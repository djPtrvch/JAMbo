import Foundation

// Иконки движков (стиль Ink): перенос src/engineIcons.ts веба (формы — как в вебе, включая перерисованные VA и
// Chords). Поле 64×64; elements(engine, v) — элементы иконки по ручкам 1.1, 1.2, 1.3 и Decay (0…1).
// Рисует UI (Canvas): один цвет темы, линия 1,4, скруглённые концы. Пока движки 0–7 (MI SYNTH).

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

/// Команда контура (подмножество SVG path, как в источнике).
public enum IconCmd: Equatable, Sendable {
    case move(Double, Double)
    case line(Double, Double)
    case hTo(Double)
    case vTo(Double)
    case hBy(Double)
    case vBy(Double)
    /// Дуга окружности радиуса r до (x, y), по часовой (sweep 1); large — больше 180°.
    case arc(r: Double, large: Bool, x: Double, y: Double)
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
        return [.move(p0.0, p0.1), .arc(r: r, large: abs(a1 - a0) > 180, x: p1.0, y: p1.1)]
    }

    static func fold(_ z: Double) -> Double { return (2 / Double.pi) * asin(sin(Double.pi / 2 * z)) }

    /// Остаток от деления, как % в JS (знак делимого).
    static func mod(_ a: Double, _ b: Double) -> Double { return a.truncatingRemainder(dividingBy: b) }

    /// Math.round веба (половина — вверх).
    static func round(_ x: Double) -> Int { return Int((x + 0.5).rounded(.down)) }

    static let chords: [[Double]] = [
        [0, 12, 24, 36], [0, 7, 12, 19], [0, 5, 7, 12], [0, 3, 7, 12], [0, 3, 7, 10], [0, 3, 7, 14],
        [0, 3, 7, 17], [0, 4, 9, 14], [0, 4, 7, 14], [0, 4, 7, 11], [0, 4, 7, 12],
    ]
    static let chordLabels = ["oct", "5", "sus4", "m", "m7", "m9", "m11", "6/9", "M9", "M7", "M"]

    /// Элементы иконки движка (0–7); у других — пусто.
    public static func elements(_ engine: Int, _ v: IconValues) -> [IconElement] {
        switch engine {
        case 0: return va(v)
        case 1: return waveshape(v)
        case 2: return fm(v)
        case 3: return grain(v)
        case 4: return additive(v)
        case 5: return wavetable(v)
        case 6: return chordIcon(v)
        case 7: return speech(v)
        default: return []
        }
    }

    // MARK: — движки

    /// VA (перерисованная): пунктир периодов, квадрат с ШИМ (1.2), треугольник→пила (1.3), расстроенный (1.1).
    static func va(_ v: IconValues) -> [IconElement] {
        let L = 26.0, w = 0.1 + 0.4 * v.t, r = 0.5 + 0.45 * v.m, L2 = L * (1 - 0.4 * v.h)
        var els: [IconElement] = []
        for k in 0..<3 { els.append(IconElement([.move(6 + Double(k) * L, 4), .vTo(60)], op: 0.3, dash: true)) }
        els.append(IconElement(pts(fx(6, 58, 200) { x, _ in
            let p = mod((x - 6) / L, 1)
            return p < w ? 8 : 26
        })))
        els.append(IconElement(pts(fx(6, 58, 200) { x, _ in
            let p = mod((x - 6) / L2, 1)
            let val = p < r ? p / r : (1 - p) / (1 - r)
            return 56 - 18 * val
        })))
        return els
    }

    static func waveshape(_ v: IconValues) -> [IconElement] {
        let b = (v.m - 0.5) * 1.0
        let c = fx(6, 58, 160) { _, u in
            let a = sin(tau * 1.5 * u) + b
            let sh = (1 - v.h) * a + v.h * tanh(3 * a)
            let o = fold(sh * (0.8 + 2.4 * v.t))
            return 32 - 20 * clamp(o, -1, 1)
        }
        return [IconElement([.move(6, 32), .hTo(58)], op: 0.35), IconElement(pts(c))]
    }

    static func fm(_ v: IconValues) -> [IconElement] {
        let r = 1 + v.h * 3, I = v.t * 5
        let c = fx(24, 60, 160) { _, u in
            let th = tau * 2 * u
            let t2 = th + I * sin(r * th)
            return 32 - 20 * sin(t2 + v.m * 1.5 * sin(t2))
        }
        return [
            ring(11, 16, 5), ring(11, 48, 5), IconElement([.move(11, 21), .vTo(43)], op: 0.6),
            IconElement(arc(11, 16, 8.5, -90, -90 + Swift.max(20, v.m * 300))), IconElement(pts(c)),
        ]
    }

    static func grain(_ v: IconValues) -> [IconElement] {
        let s = 0.07 + 0.2 * v.m
        let env: (Double) -> Double = { u in exp(-pow((u - 0.5) / s, 2)) }
        let fr = 3 + v.t * 12, t2 = 14 + 8 + v.h * 34
        return [
            IconElement(pts(fx(6, 58, 120) { _, u in 24 - 18 * env(u) })),
            IconElement(pts(fx(6, 58, 120) { _, u in 24 + 18 * env(u) })),
            IconElement(pts(fx(6, 58, 200) { _, u in 24 - 18 * env(u) * sin(tau * fr * u) })),
            IconElement([.move(6, 58), .hTo(58)], op: 0.4),
            IconElement([.move(14, 58), .vTo(49)]),
            IconElement([.move(t2, 58), .vTo(49)]),
        ]
    }

    static func additive(_ v: IconValues) -> [IconElement] {
        let nb = 1 + round(v.h * 3), sg = 2.6 - v.m * 2.0, c0 = v.t * 11
        var cs: [Double] = []
        for k in 0..<nb { cs.append(mod(c0 + Double(k) * 12 / Double(nb), 12)) }
        var cmds: [IconCmd] = []
        for i in 0..<12 {
            let x = 6 + Double(i) * 4.73
            let hh = cs.map { c in exp(-pow(Double(i) - c, 2) / (2 * sg * sg)) }.max() ?? 0
            cmds.append(.move(x, 58))
            cmds.append(.vTo(58 - 2 - 44 * hh))
        }
        return [IconElement(cmds)]
    }

    static func wavetable(_ v: IconValues) -> [IconElement] {
        let sel = Swift.min(4, round(v.t * 4)), bank = Swift.min(3, Int((v.h * 4).rounded(.down))), cx = 10 + v.m * 40
        var els: [IconElement] = []
        var cy = 32.0
        for r in 0..<5 {
            let rr = Double(r)
            let by = 46 - rr * 8, x0 = 8 + rr * 3
            let fw: (Double) -> Double = { u in
                by - 6 * (sin(tau * u) + sin(2 * tau * u + rr * 1.3 + 0.6) / 2 + sin(3 * tau * u + rr * 0.7 + 1.2) / 3) / 1.5
            }
            let line = fx(x0, x0 + 34, 80) { _, u in
                if !v.a { return fw(u) }
                let y = fw((u * 14).rounded(.down) / 14)
                return by + (((y - by) / 1.6) + 0.5).rounded(.down) * 1.6
            }
            els.append(IconElement(pts(line), op: r == sel ? 1 : 0.55))
            if r == sel { cy = fw(clamp((cx - x0) / 34)) }
        }
        els.append(IconElement([.move(cx, 6), .vTo(50)], op: 0.9))
        els.append(IconElement(circle: (cx, cy, 2.2), fill: true))
        for i in 0..<4 {
            let x = 18 + Double(i) * 10
            let rect: [IconCmd] = [.move(x, 55), .hBy(6), .vBy(5), .hBy(-6), .close]
            els.append(i == bank ? IconElement(rect, fill: true) : IconElement(rect, op: 0.6))
        }
        return els
    }

    /// CHORDS (перерисованная): ноты аккорда (1.1) с обращением (1.2) точками в два столбца, метка аккорда,
    /// волна (1.3).
    static func chordIcon(_ v: IconValues) -> [IconElement] {
        let idx = Swift.min(10, Int((v.h * 11).rounded(.down))), k = Swift.min(3, Int((v.t * 4).rounded(.down)))
        var n = chords[idx]
        for _ in 0..<k {
            n.sort()
            n.append(n.removeFirst() + 12)
        }
        n.sort()
        var els: [IconElement] = n.enumerated().map { i, nn in dot(9 + Double(i % 2) * 13, clamp(57 - nn * 1.3, 6, 57), 2) }
        els.append(IconElement(text: chordLabels[idx], x: 47, y: 26, size: 12))
        els.append(IconElement(pts(fx(34, 60, 70) { _, u in
            var s = 0.0, nm = 0.0
            let p = 2 - 1.6 * v.m
            for q in 1...6 {
                s += sin(tau * Double(q) * u) / pow(Double(q), p)
                nm += 1 / pow(Double(q), p)
            }
            return 47 - 9 * s / nm * 1.3
        })))
        els.append(IconElement([.move(34, 47), .hTo(60)], op: 0.3))
        return els
    }

    static func speech(_ v: IconValues) -> [IconElement] {
        let m = v.m
        let w = m < 0.5 ? 6 + m / 0.5 * 7 : 13 + (m - 0.5) / 0.5 * 9
        let hh = m < 0.5 ? 8 + m / 0.5 * 4 : 12 - (m - 0.5) / 0.5 * 8
        let mode = Swift.min(2, Int((v.h * 3).rounded(.down)))
        var mouth: [(Double, Double)] = []
        for i in 0...40 {
            let a = tau * Double(i) / 40
            mouth.append((32 + w * cos(a), 38 + hh * sin(a)))
        }
        var els: [IconElement] = [
            ring(32, 32, 27, 0.5), dot(32 - (5 + v.t * 9), 20, 2.2), dot(32 + (5 + v.t * 9), 20, 2.2),
            IconElement(pts(mouth) + [.close]),
        ]
        for i in 0..<3 {
            let x = 27 + Double(i) * 5
            els.append(i == mode ? dot(x, 55.5, 1.5) : ring(x, 55.5, 1.5, 0.6))
        }
        return els
    }
}
