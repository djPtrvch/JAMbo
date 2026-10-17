import Foundation

// Иконки MI DRUMS (движки 8–15): перенос src/engineIcons.ts — итоговые формы (11–14 — с Decay и OUT→AUX,
// перерисованные Particle и Hi-hat). У 11–15 m — ручка OUT→AUX, d — Decay.

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

extension EngineIcons {
    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

    /// SWARM: облако колец — число по плотности (1.2), разброс по высоте (1.1), размер по длине зерна (1.3).
    static func swarm(_ v: IconValues) -> [IconElement] {
        var r = IconRandom(7)
        let n = 6 + round(v.t * 28)
        var rx: [Double] = [], ry: [Double] = []
        for _ in 0..<40 {
            rx.append(r.next())
            ry.append(r.next())
        }
        return (0..<n).map { i in
            ring(8 + rx[i] * 48, 32 + (ry[i] - 0.5) * 2 * (3 + v.h * 26), 1.5 + v.m * 5.5, 0.9)
        }
    }

    /// NOISE: ступеньки шума с тактом (1.2) и АЧХ фильтра ФНЧ → полосовой → ФВЧ (1.1) с резонансом (1.3).
    static func noise(_ v: IconValues) -> [IconElement] {
        var r = IconRandom(3)
        let sw = 1.2 + (1 - v.t) * 7
        var ns: [(Double, Double)] = []
        var x = 6.0
        while x < 58 {
            let y = 49 + (r.next() - 0.5) * 18
            ns.append((x, y))
            ns.append((Swift.min(58, x + sw), y))
            x += sw
        }
        let lp: (Double) -> Double = { u in 1 / (1 + pow(u / 0.45, 6)) }
        let hp: (Double) -> Double = { u in 1 / (1 + pow(0.45 / (u + 0.01), 6)) }
        let bp: (Double) -> Double = { u in exp(-pow((u - 0.5) / 0.16, 2)) }
        let cv = fx(6, 58, 120) { _, u in
            var c: Double
            if v.h < 0.5 {
                let a = v.h / 0.5
                c = (1 - a) * lp(u) + a * bp(u)
            } else {
                let a = (v.h - 0.5) / 0.5
                c = (1 - a) * bp(u) + a * hp(u)
            }
            c += v.m * 0.9 * exp(-pow((u - 0.5) / 0.05, 2))
            return Swift.max(4, 34 - 24 * clamp(c, 0, 1.3))
        }
        return [IconElement(pts(ns), op: 0.9), IconElement(pts(cv))]
    }

    /// PARTICLE (перерисованная): частицы сеткой (число — 1.2, разброс — 1.1); 1.3 < 0,5 — кольца диффузии,
    /// > 0,5 — затухающий звон резонанса.
    static func particle(_ v: IconValues) -> [IconElement] {
        var r = IconRandom(17)
        let n = 3 + round(v.t * 9)
        var rx: [Double] = [], ry: [Double] = []
        for _ in 0..<14 {
            rx.append(r.next())
            ry.append(r.next())
        }
        var els: [IconElement] = []
        for j in 0..<n {
            let c = Double(j % 4), row = Double(j / 4)
            let x = clamp(11 + c * 14 + (rx[j] - 0.5) * v.h * 22, 5, 59)
            let y = clamp(16 + row * 14 + (ry[j] - 0.5) * v.h * 16, 5, 59)
            els.append(dot(x, y, 1.8))
            if v.m < 0.5 {
                let k = (0.5 - v.m) * 2
                if k > 0.05 {
                    els.append(ring(x, y, 2.8 + k * 2.2))
                    els.append(ring(x, y, 4.5 + k * 3.5, 0.5))
                }
            } else {
                let k = (v.m - 0.5) * 2
                if k > 0.05 {
                    let len = 4 + k * 10
                    els.append(IconElement(pts(fx(x + 3, x + 3 + len, 24) { _, u in
                        y + 2.4 * sin(tau * 2.5 * u) * (1 - u)
                    })))
                }
            }
        }
        return els
    }

    /// STRING: колебание струны с негармоничностью (1.1) и яркостью (1.2), затухание по Decay; к AUX (1.3) —
    /// шумовой импульс возбуждения.
    static func string(_ v: IconValues) -> [IconElement] {
        let d = v.d, x = v.m, b = 0.02 + v.h * 0.25, p = 2.2 - 1.8 * v.t, dc = 7 - 5.5 * d
        var r = IconRandom(31)
        let n = 240
        var raw: [Double] = []
        var nm = 0.0
        for k in 1...6 { nm += 1 / pow(Double(k), p) }
        for _ in 0...n { raw.append(r.next() * 2 - 1) }
        let sm = round(1 + (1 - v.t) * 6)
        let sn: (Int) -> Double = { i in
            var s = 0.0, c = 0.0
            for j in -sm...sm {
                let k = i + j
                if k >= 0 && k <= n {
                    s += raw[k]
                    c += 1
                }
            }
            return s / c * (1 + Double(sm) * 0.5)
        }
        let c = fx(12, 58, n) { _, u in
            var so = 0.0
            for k in 1...6 {
                let kk = Double(k)
                so += sin(tau * kk * 3 * (1 + b * kk * kk).squareRoot() * u) / pow(kk, p)
            }
            let out = exp(-u * dc) * so / nm
            let ex = exp(-u * 26) * clamp(sn(round(u * Double(n))) * 1.2, -1, 1)
            return 32 - 22 * ((1 - x) * out + x * ex)
        }
        return [IconElement([.move(8, 22), .vTo(42), .move(8, 32), .hTo(12)]), IconElement(pts(c))]
    }

    /// MODAL: кольца мод (растяжение — 1.1, затухание — Decay), лучи удара (1.2); к AUX (1.3) — длиннее лучи и пыль.
    static func modal(_ v: IconValues) -> [IconElement] {
        let d = v.d, x = v.m, p = 0.5 + 1.7 * v.h
        let rt: [Double] = (1...5).map { pow(Double($0), p) }
        var r = IconRandom(2)
        var els: [IconElement] = []
        for i in 0..<5 {
            els.append(ring(32, 32, 8 + 18 * (rt[i] - rt[0]) / (rt[4] - rt[0]),
                            exp(-Double(i) * (1.4 - 1.3 * d) * 0.55) * (1 - x)))
        }
        let n = 3 + round(v.t * 9), l = lerp(5.5, 24, x)
        var s: [IconCmd] = []
        for i in 0..<n {
            let a = tau * Double(i) / Double(n), c = cos(a), sn = sin(a)
            s.append(.move(32 + c * 1.8, 32 + sn * 1.8))
            s.append(.line(32 + c * l, 32 + sn * l))
        }
        els.append(IconElement(s))
        let nd = round(v.t * 14 * x)
        for _ in 0..<nd {
            let a = r.next() * tau
            let rr = 12 + r.next() * 16
            els.append(dot(32 + rr * cos(a), 32 + rr * sin(a), 1.1))
        }
        return els
    }

    /// KICK: бочка с подъёмом частоты в атаке, перегруз (1.1), яркость (1.2), затухание — Decay; к AUX (1.3) —
    /// синтетическая (треугольник с насыщением).
    static func kick(_ v: IconValues) -> [IconElement] {
        let d = v.d, x = v.m, dr = 1 + 3 * v.h, dc = 7 - 5.5 * d, tn = tanh(dr), g = 1 + 2.5 * v.t, dr2 = 1 + v.h * 1.2
        let c = fx(6, 58, 260) { _, u in
            let ph = tau * (6.5 * u + 2.2 * (1 - exp(-u * 10)))
            let y = sin(ph) + v.t * 0.5 * sin(3 * ph)
            let out = tanh(dr * exp(-u * dc) * y) / tn
            let q = mod(6.5 * u + 3.4 * (1 - exp(-u * 7)), 1)
            let tri = 4 * abs(q - 0.5) - 1
            let au = tanh(g * tri) / tanh(g)
            let aux = tanh(dr2 * exp(-u * dc * 0.8) * au) / tanh(dr2)
            return 32 - 22 * ((1 - x) * out + x * aux)
        }
        return [IconElement([.move(6, 32), .hTo(58)], op: 0.35), IconElement(pts(c))]
    }

    /// SNARE: шум (уровень — 1.1) и моды корпуса (баланс — 1.2), затухание — Decay; к AUX (1.3) — 909-подобный.
    static func snare(_ v: IconValues) -> [IconElement] {
        let d = v.d, x = v.m, dc = 7 - 5.5 * d
        var r = IconRandom(5)
        let n = 130
        var raw: [Double] = []
        for _ in 0...n { raw.append(r.next() * 2 - 1) }
        let at: (Int) -> Double = { i in raw[Swift.max(0, Swift.min(n, i))] }
        let sm: (Int) -> Double = { i in (at(i) + at(i - 1) + at(i + 1) + at(i - 2)) / 4 * 1.7 }
        let hp: (Int) -> Double = { i in (at(i) - at(i - 1)) / 1.3 }
        let nz = fx(6, 58, n) { _, u in
            let i = round(u * Double(n))
            return 32 - 22 * v.h * exp(-u * dc) * ((1 - x) * sm(i) + x * hp(i))
        }
        let tn = fx(6, 58, 260) { _, u in
            let e = exp(-u * dc)
            let m1 = sin(tau * 5 * u) * e
            let m2 = sin(tau * 8.3 * u + 0.5) * exp(-u * dc * 1.5)
            let m3 = sin(tau * 12.1 * u) * exp(-u * dc * 2.2)
            let out = (1 - v.t) * m1 + v.t * (0.7 * m2 + 0.5 * m3)
            let a1 = (1 - v.t) * sin(tau * 5 * u + 2.2 * sin(tau * 7.3 * u))
            let a2 = v.t * sin(tau * 8.3 * u + 1.6 * sin(tau * 3.1 * u))
            let aux = (a1 + a2) * e
            return 32 - 22 * (1 - v.h * 0.8) * ((1 - x) * out + x * aux)
        }
        return [IconElement([.move(6, 32), .hTo(58)], op: 0.35), IconElement(pts(nz), op: 0.85), IconElement(pts(tn))]
    }

    /// HI-HAT (перерисованная): две тарелки (раскрытие — Decay), лучи звона (число и длина — 1.2, рваность — 1.1);
    /// к AUX (1.3) — лучи парами.
    static func hiHat(_ v: IconValues) -> [IconElement] {
        let d = v.d, x = v.m
        var r = IconRandom(13)
        let g = 1 + d * 11, rx = 22.0, ry = 4.2, cyT = 33 - g / 2, cyB = 39 + g / 2
        let ell: (Double) -> [IconCmd] = { cy in
            [.move(32 - rx, cy),
             .arcBy(rx: rx, ry: ry, large: true, sweep: false, dx: 2 * rx, dy: 0),
             .arcBy(rx: rx, ry: ry, large: true, sweep: false, dx: -2 * rx, dy: 0)]
        }
        var els: [IconElement] = [
            IconElement(ell(cyB)), IconElement(ell(cyT)),
            IconElement([.move(32, cyB + ry), .vTo(61)]),
            IconElement([.move(32, cyT - ry), .vTo(cyT - ry - 3)]),
        ]
        let n = 3 + round(v.t * 6), len = lerp(14, 7, v.t)
        let pa: [Double] = [-140, -90, -40]
        var rd: [IconCmd] = []
        for i in 0..<n {
            let uni = -160 + 140 * (Double(i) + 0.5) / Double(n)
            let pair = pa[Swift.min(2, i * 3 / n)] + (i % 2 != 0 ? 6 : -6)
            let th = lerp(uni, pair, x) * Double.pi / 180
            let ox = 32 + rx * 0.8 * cos(th)
            let oy = cyT - ry - 0.5 + ry * sin(th) * 0.6
            let ang = -Double.pi / 2 + (th + Double.pi / 2) * 0.45
            let jx = (r.next() - 0.5) * v.h * 3
            for j in 0..<4 {
                if j > 0 && r.next() < v.h * 0.6 { continue }
                let a0 = Double(j) / 4 * len, a1 = (Double(j) + 1 - 0.7 * v.h) / 4 * len
                rd.append(.move(ox + jx + cos(ang) * a0, oy + sin(ang) * a0))
                rd.append(.line(ox + jx + cos(ang) * a1, oy + sin(ang) * a1))
            }
        }
        els.append(IconElement(rd))
        return els
    }
}
