import Foundation

// Колонки — общий язык превью движков, как превью сэмпла (docs/icons/prototype/engine-previews-prototype.html):
// сигнал считается в 72 · 6 + 1 точках, каждая из 72 колонок — прямоугольник от min до max сигнала внутри неё
// (всегда с осью). Всё здесь — чистые функции, без состояния.

/// Колонка lane прототипа: ось y0, размах amp; mirror — симметрично оси (огибающая), thin — без минимальной толщины,
/// тихие колонки пропускаются (видна серая ось); ext — добавка к размаху по x колонки (всплеск удара).
struct IconLane {
    var y0: Double
    var amp: Double
    var mirror = false
    var thin = false
    var alpha = 1.0
    var ink = IconInk.primary
    var x0 = 4.0
    var x1 = 60.0
    var ext: ((Double) -> Double)? = nil
}

extension EngineIcons {
    static let cols = 72
    static let sub = 6
    /// Точек сигнала на всю ширину без одной (cols · sub).
    static let ns = 432.0
    static let x0 = 4.0
    static let x1 = 60.0
    /// Время прототипа (c.T) для прокрутки волн ANALOG, FM, WTABLE, SUB: иконка — чистая функция ручек, поэтому
    /// фаза постоянная, как в прототипе при reduced motion.
    static let still = 1.3

    // MARK: — шум

    /// hash прототипа: дробная часть sin(n · 127.1 + 311.7) · 43758.5453.
    static func hash(_ n: Double) -> Double {
        let v = sin(n * 127.1 + 311.7) * 43758.5453
        return v - v.rounded(.down)
    }

    /// rnd(i, seed) прототипа: −1…1.
    static func rnd(_ i: Int, _ seed: Double) -> Double {
        return hash(Double(i) * 1.713 + seed * 9.31) * 2 - 1
    }

    /// Таблица шума NZ (512 значений −1…1).
    static let noise: [Double] = (0..<512).map { i in hash(Double(i) * 3.17 + 7) * 2 - 1 }

    static func nz(_ i: Int) -> Double {
        return noise[((i % 512) + 512) % 512]
    }

    /// Шум с линейной интерполяцией между точками таблицы.
    static func nzi(_ x: Double) -> Double {
        let fi = x.rounded(.down)
        let i = Int(fi)
        return lerp(nz(i), nz(i + 1), x - fi)
    }

    // MARK: — формы волн (как в EngineIconsJambo прежде: треугольник с пиком на четверти, падающая пила, квадрат 50 %)

    static func sstep(_ t: Double) -> Double { return t * t * (3 - 2 * t) }

    static func frac(_ p: Double) -> Double { return p - p.rounded(.down) }

    static func shSine(_ p: Double) -> Double { return sin(tau * p) }

    static func shTri(_ p0: Double) -> Double {
        let p = frac(p0)
        return 1 - 4 * abs(p < 0.75 ? p - 0.25 : p - 1.25)
    }

    static func shSaw(_ p0: Double) -> Double { return 1 - 2 * frac(p0) }

    static func shSq(_ p0: Double) -> Double { return frac(p0) < 0.5 ? 1 : -1 }

    /// Форма k: 0 — синус, 1 — треугольник, 2 — пила, 3 — квадрат.
    static func shape(_ k: Int, _ p: Double) -> Double {
        switch k {
        case 0: return shSine(p)
        case 1: return shTri(p)
        case 2: return shSaw(p)
        default: return shSq(p)
        }
    }

    /// morph прототипа: плавный переход между формами kinds по дробному индексу idx.
    static func morph(_ kinds: [Int], _ idx0: Double, _ p: Double) -> Double {
        let n = kinds.count
        let idx = clamp(idx0, 0, Double(n - 1))
        let i = Swift.min(Int(idx.rounded(.down)), n - 2)
        return lerp(shape(kinds[i], p), shape(kinds[i + 1], p), sstep(idx - Double(i)))
    }

    // MARK: — сигнал и колонки

    /// Сигнал gen прототипа: cols · 6 + 1 точек, fn(u, i), u = 0…1. Хранится во Float, как Float32Array.
    static func gen(_ cols: Int = 72, _ fn: (Double, Int) -> Double) -> [Double] {
        let n = cols * sub
        var a = [Double](repeating: 0, count: n + 1)
        let dn = Double(n)
        for i in 0...n {
            let v: Double = fn(Double(i) / dn, i)
            a[i] = Double(Float(v))
        }
        return a
    }

    /// Колонки сигнала a (lane прототипа). hx — подсветка удара: колонки около hx на 16 % выше.
    static func lane(_ a: [Double], _ o: IconLane, _ hx: Double? = nil) -> IconElement {
        let n = (a.count - 1) / sub
        let w = (o.x1 - o.x0) / Double(n)
        let half = o.thin ? 0 : 0.4
        var rects: [IconRect] = []
        rects.reserveCapacity(n)
        for i in 0..<n {
            let xc = o.x0 + (Double(i) + 0.5) * w
            var mn = 0.0, mx = 0.0
            for k in 0...sub {
                let v = a[i * sub + k]
                if o.mirror {
                    mx = Swift.max(mx, abs(v))
                } else {
                    mn = Swift.min(mn, v)
                    mx = Swift.max(mx, v)
                }
            }
            if o.mirror { mn = -mx }
            var gain = 1.0
            if let h = hx {
                let z = (xc - h) / 7
                gain = 1 + 0.16 * exp(-z * z)
            }
            let e: Double = o.ext?(xc) ?? 0
            var top = o.y0 - (mx + e) * o.amp * gain - half
            var bot = o.y0 - (mn - e) * o.amp * gain + half
            if o.thin && bot - top < 0.5 { continue }
            if top < 1.5 { top = 1.5 }
            if bot > 62.5 { bot = 62.5 }
            rects.append(IconRect(o.x0 + Double(i) * w - 0.06, top, w + 0.12, bot - top))
        }
        return IconElement(rects: rects, ink: o.ink, op: o.alpha < 1 ? o.alpha : nil)
    }

    /// Серая ось на высоте y (axisG прототипа).
    static func axis(_ y: Double, _ xa: Double = 4, _ xb: Double = 60) -> IconElement {
        return IconElement(rects: [IconRect(xa, y - 0.4, xb - xa, 0.8)], ink: .secondary)
    }

    /// Всплеск в начале (startSpike прототипа): k · exp(−((x − 4) / w)²).
    static func startSpike(_ k: Double, _ w: Double) -> (Double) -> Double {
        return { x in
            let z = (x - 4) / w
            return k * exp(-z * z)
        }
    }
}
