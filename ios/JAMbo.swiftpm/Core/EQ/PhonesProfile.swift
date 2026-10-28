import Foundation

// Профили коррекции наушников в файле (IMPORT и EXPORT в CORRECT PRESETS): текст в формате AutoEQ ParametricEQ.txt
// и Equalizer APO — строки «Preamp: −6.1 dB» и «Filter 1: ON PK Fc 105 Hz Gain −4.2 dB Q 0.70». Типы: PK — bell,
// LSC/LS — low shelf, HSC/HS — high shelf, HP/HPQ — low cut, LP/LPQ — high cut, NO — notch (Q у shelf не
// учитывается: у наших S = 1, Q ≈ 0,71). Preamp из файла не берётся — у коррекции он свой (EqSpec.preamp).
// Фильтров больше 10 — 10 полос подгоняются под кривую всех фильтров (PhonesFit). Формат AutoEQ GraphicEQ.txt
// (одна строка «GraphicEQ: 20 -7.2; 21 -7.3; …» — точки кривой, без фильтров) — 10 полос подгоняются под кривую
// точек; общий сдвиг кривой (в GraphicEQ в неё входит предусиление) убирается — у коррекции предусиление своё.

public enum PhonesProfile {
    /// Фильтр из файла.
    public struct Filter: Equatable, Sendable {
        public var type: Int
        public var freq: Double
        public var gain: Double
        public var q: Double

        public var band: EqBand {
            let q1: Double = EqSpec.hasGain(type) && type != EqSpec.bell ? 0.71 : q
            return EqBand(type: type, freq: freq, gain: EqSpec.hasGain(type) ? gain : 0, q: q1)
        }
    }

    static let codes: [String: Int] = [
        "PK": EqSpec.bell, "PEQ": EqSpec.bell, "LSC": EqSpec.lowShelf, "LS": EqSpec.lowShelf,
        "HSC": EqSpec.highShelf, "HS": EqSpec.highShelf, "HP": EqSpec.lowCut, "HPQ": EqSpec.lowCut,
        "LP": EqSpec.highCut, "LPQ": EqSpec.highCut, "NO": EqSpec.notch,
    ]

    /// Включённые фильтры текста (неизвестные строки и выключенные фильтры пропускаются).
    public static func parse(_ text: String) -> [Filter] {
        var out: [Filter] = []
        for raw in text.components(separatedBy: .newlines) {
            let line: String = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("filter") else { continue }
            let words: [String] = line.replacingOccurrences(of: ":", with: " ")
                .split(whereSeparator: { $0 == " " || $0 == "\t" }).map { String($0) }
            guard let on = words.firstIndex(where: { $0.uppercased() == "ON" }), on + 1 < words.count,
                  let type = codes[words[on + 1].uppercased()] else { continue }
            func value(_ key: String) -> Double? {
                guard let i = words.firstIndex(where: { $0.lowercased() == key }), i + 1 < words.count else { return nil }
                return Double(words[i + 1].replacingOccurrences(of: ",", with: "."))
            }
            guard let fc = value("fc"), fc > 0 else { continue }
            let q: Double = value("q") ?? (EqSpec.isCut(type) ? 0.71 : EqSpec.qDef)
            out.append(Filter(type: type, freq: fc, gain: value("gain") ?? 0, q: q))
        }
        return out
    }

    /// EQ из фильтров: до EqSpec.bands (10) — как есть, больше — подгонка под число полос (fitted true).
    public static func eq(_ filters: [Filter]) -> (eq: Eq, fitted: Bool) {
        var e = Eq()
        let fitted: Bool = filters.count > EqSpec.bands
        let bands: [EqBand] = fitted ? PhonesFit.fit(filters.map { $0.band }) : filters.map { $0.band }
        for (k, b) in bands.prefix(EqSpec.bands).enumerated() {
            var c = b
            c.freq = Swift.max(EqSpec.freqMin, Swift.min(EqSpec.freqMax, c.freq))
            c.gain = (Swift.max(-EqSpec.gainMax, Swift.min(EqSpec.gainMax, c.gain)) * 10).rounded() / 10
            c.q = Swift.max(EqSpec.qMin, Swift.min(EqSpec.qMax, c.q))
            e.bands[k] = c
        }
        return (e, fitted)
    }

    /// Текст профиля (включённые полосы по частоте; low cut и high cut 24 и 48 dB/окт — 2 и 4 одинаковых фильтра).
    public static func text(_ eq: Eq) -> String {
        var lines: [String] = [String(format: "Preamp: %.1f dB", EqSpec.preamp(eq))]
        let bands: [EqBand] = eq.bands.compactMap { $0 }.filter { $0.on }.sorted { $0.freq < $1.freq }
        var n = 1
        for b in bands {
            let code: String
            switch b.type {
            case EqSpec.lowShelf: code = "LSC"
            case EqSpec.highShelf: code = "HSC"
            case EqSpec.lowCut: code = "HPQ"
            case EqSpec.highCut: code = "LPQ"
            case EqSpec.notch: code = "NO"
            default: code = "PK"
            }
            let q: Double = EqSpec.hasGain(b.type) && b.type != EqSpec.bell ? 0.71 : b.q
            for _ in 0..<EqSpec.stages(b) {
                var line: String = "Filter \(n): ON \(code) " + String(format: "Fc %.0f Hz", b.freq)
                if EqSpec.hasGain(b.type) { line += String(format: " Gain %.1f dB", b.gain) }
                line += String(format: " Q %.2f", q)
                lines.append(line)
                n += 1
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Точки кривой GraphicEQ (частота, dB) по возрастанию частоты; нет строки «GraphicEQ:» — пусто.
    public static func graphic(_ text: String) -> [(hz: Double, db: Double)] {
        var out: [(hz: Double, db: Double)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line: String = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("graphiceq") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            for item in line[line.index(after: colon)...].split(separator: ";") {
                let w: [Substring] = item.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard w.count >= 2, let f = Double(w[0].replacingOccurrences(of: ",", with: ".")),
                      let g = Double(w[1].replacingOccurrences(of: ",", with: ".")), f > 0 else { continue }
                out.append((f, g))
            }
        }
        return out.sorted { $0.hz < $1.hz }
    }

    /// EQ из точек GraphicEQ: 10 полос, подогнанных под кривую (сдвинутую так, что её середина — 0 dB).
    public static func eq(graphic points: [(hz: Double, db: Double)]) -> Eq {
        let bands: [EqBand] = PhonesFit.fitCurve(points)
        let filters: [Filter] = bands.map { Filter(type: $0.type, freq: $0.freq, gain: $0.gain, q: $0.q) }
        return eq(filters).eq
    }

    /// Имя пресета из имени файла: без расширения и хвоста « ParametricEQ» или « GraphicEQ».
    public static func name(fromFile file: String) -> String {
        var s: String = (file as NSString).deletingPathExtension
        for tail in [" ParametricEQ", "_ParametricEQ", " ParametricEq", " GraphicEQ", "_GraphicEQ"] where s.hasSuffix(tail) {
            s = String(s.dropLast(tail.count))
        }
        let t: String = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Phones" : t
    }
}

/// Подгонка 10 полос под кривую большего числа фильтров (Левенберг — Марквардт по 128 частотам 20 Гц…20 кГц, dB):
/// начало — 10 фильтров с наибольшим вкладом (срезы — всегда, их параметры не двигаются), у bell — частота, усиление
/// и Q, у shelf — частота и усиление.
enum PhonesFit {
    static let points = 128

    static func fit(_ all: [EqBand]) -> [EqBand] {
        let hz: [Double] = (0..<points).map { i in
            EqSpec.freqMin * pow(EqSpec.freqMax / EqSpec.freqMin, Double(i) / Double(points - 1))
        }
        let target: [Double] = curve(all, hz)
        var start: [EqBand] = all.sorted { impact($0) > impact($1) }
        start = Array(start.prefix(EqSpec.bands))
        return refine(start, hz, target, iterations: 60).sorted { $0.freq < $1.freq }
    }

    /// Подгонка полос под кривую точек GraphicEQ: кривая — на 128 частотах (линейно по log f), сдвинута на медиану;
    /// начало — жадно: полоса за полосой на месте наибольшего остатка (по краям — shelf, иначе bell), после каждой
    /// новой — короткое уточнение всех, в конце — полное.
    static func fitCurve(_ pts: [(hz: Double, db: Double)]) -> [EqBand] {
        if pts.isEmpty { return [] }
        let hz: [Double] = (0..<points).map { i in
            EqSpec.freqMin * pow(EqSpec.freqMax / EqSpec.freqMin, Double(i) / Double(points - 1))
        }
        var target: [Double] = hz.map { interp(pts, $0) }
        let mid: Double = target.sorted()[points / 2]
        target = target.map { $0 - mid }
        var bands: [EqBand] = []
        while bands.count < EqSpec.bands {
            let have: [Double] = curve(bands, hz)
            var best = 0
            var bestV: Double = 0
            for i in 0..<points {
                let v: Double = abs(target[i] - have[i])
                if v > bestV {
                    bestV = v
                    best = i
                }
            }
            if bestV < 0.1 { break }
            let gain: Double = target[best] - have[best]
            let f: Double = hz[best]
            let b: EqBand
            if best < 4 {
                b = EqBand(type: EqSpec.lowShelf, freq: Swift.max(f, 40), gain: gain, q: 0.71)
            } else if best > points - 5 {
                b = EqBand(type: EqSpec.highShelf, freq: Swift.min(f, 12000), gain: gain, q: 0.71)
            } else {
                b = EqBand(type: EqSpec.bell, freq: f, gain: gain, q: 1.4)
            }
            bands.append(b)
            bands = refine(bands, hz, target, iterations: 8)
        }
        return refine(bands, hz, target, iterations: 60).sorted { $0.freq < $1.freq }
    }

    /// Кривая точек на частоте f (линейно по log f; за краями — крайние значения).
    static func interp(_ pts: [(hz: Double, db: Double)], _ f: Double) -> Double {
        if f <= pts[0].hz { return pts[0].db }
        for i in 1..<pts.count where f <= pts[i].hz {
            let a = pts[i - 1], b = pts[i]
            if b.hz <= a.hz { return b.db }
            let t: Double = log(f / a.hz) / log(b.hz / a.hz)
            return a.db + (b.db - a.db) * t
        }
        return pts[pts.count - 1].db
    }

    /// Левенберг — Марквардт: параметры полос start (форма — типы) под кривую target на частотах hz.
    static func refine(_ start: [EqBand], _ hz: [Double], _ target: [Double], iterations: Int) -> [EqBand] {
        var x: [Double] = pack(start)
        var r: [Double] = residual(x, start, hz, target)
        var cost: Double = r.reduce(0) { $0 + $1 * $1 }
        var lambda: Double = 1e-2
        let m: Int = x.count
        var iter = 0
        while iter < iterations && m > 0 {
            iter += 1
            // Якобиан численно.
            var jac: [[Double]] = []
            for j in 0..<m {
                var xp: [Double] = x
                let h: Double = 1e-4
                xp[j] += h
                let rp: [Double] = residual(xp, start, hz, target)
                jac.append((0..<points).map { (rp[$0] - r[$0]) / h })
            }
            var a = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
            var g = [Double](repeating: 0, count: m)
            for i in 0..<m {
                for j in i..<m {
                    var s: Double = 0
                    for p in 0..<points { s += jac[i][p] * jac[j][p] }
                    a[i][j] = s
                    a[j][i] = s
                }
                var s: Double = 0
                for p in 0..<points { s += jac[i][p] * r[p] }
                g[i] = -s
            }
            var better = false
            while lambda < 1e8 {
                var aa = a
                for i in 0..<m { aa[i][i] += lambda * Swift.max(aa[i][i], 1e-9) }
                guard let d = solve(aa, g) else { break }
                let xn: [Double] = clamp(zip(x, d).map { $0 + $1 }, start)
                let rn: [Double] = residual(xn, start, hz, target)
                let cn: Double = rn.reduce(0) { $0 + $1 * $1 }
                if cn < cost {
                    better = cost - cn > 1e-9 * cost
                    x = xn
                    r = rn
                    cost = cn
                    lambda = Swift.max(1e-7, lambda / 3)
                    break
                }
                lambda *= 4
            }
            if !better { break }
        }
        return unpack(x, start)
    }

    /// Вклад фильтра: срезы — всегда; у bell — |усиление| на ширину (1/Q), у shelf — |усиление| вдвое.
    static func impact(_ b: EqBand) -> Double {
        if !EqSpec.hasGain(b.type) { return 1e9 }
        if b.type == EqSpec.bell { return abs(b.gain) / Swift.max(0.1, b.q) }
        return abs(b.gain) * 2
    }

    static func curve(_ bands: [EqBand], _ hz: [Double]) -> [Double] {
        var sum = [Double](repeating: 0, count: hz.count)
        for b in bands {
            let r: [Double] = EqCoeffs.response(b, hz: hz)
            for i in 0..<hz.count { sum[i] += r[i] }
        }
        return sum
    }

    /// Параметры: bell — ln f, усиление, ln Q; shelf — ln f, усиление; срезы и notch — без параметров.
    static func pack(_ bands: [EqBand]) -> [Double] {
        var x: [Double] = []
        for b in bands where EqSpec.hasGain(b.type) {
            x.append(log(b.freq))
            x.append(b.gain)
            if b.type == EqSpec.bell { x.append(log(b.q)) }
        }
        return x
    }

    static func unpack(_ x: [Double], _ shape: [EqBand]) -> [EqBand] {
        var out: [EqBand] = []
        var i = 0
        for b in shape {
            var c = b
            if EqSpec.hasGain(b.type) {
                c.freq = exp(x[i])
                c.gain = x[i + 1]
                i += 2
                if b.type == EqSpec.bell {
                    c.q = exp(x[i])
                    i += 1
                }
            }
            out.append(c)
        }
        return out
    }

    static func clamp(_ x: [Double], _ shape: [EqBand]) -> [Double] {
        var y: [Double] = x
        var i = 0
        let lf: Double = log(EqSpec.freqMin), hf: Double = log(EqSpec.freqMax)
        let lq: Double = log(EqSpec.qMin), hq: Double = log(EqSpec.qMax)
        for b in shape where EqSpec.hasGain(b.type) {
            y[i] = Swift.max(lf, Swift.min(hf, y[i]))
            y[i + 1] = Swift.max(-EqSpec.gainMax, Swift.min(EqSpec.gainMax, y[i + 1]))
            i += 2
            if b.type == EqSpec.bell {
                y[i] = Swift.max(lq, Swift.min(hq, y[i]))
                i += 1
            }
        }
        return y
    }

    static func residual(_ x: [Double], _ shape: [EqBand], _ hz: [Double], _ target: [Double]) -> [Double] {
        let c: [Double] = curve(unpack(x, shape), hz)
        return (0..<hz.count).map { c[$0] - target[$0] }
    }

    /// Решение a·x = b (Гаусс с выбором главного элемента); вырожденная — nil.
    static func solve(_ a0: [[Double]], _ b0: [Double]) -> [Double]? {
        var a = a0, b = b0
        let n: Int = b.count
        for c in 0..<n {
            var p = c
            for r in (c + 1)..<Swift.max(c + 1, n) where abs(a[r][c]) > abs(a[p][c]) { p = r }
            if abs(a[p][c]) < 1e-12 { return nil }
            a.swapAt(c, p)
            b.swapAt(c, p)
            for r in (c + 1)..<Swift.max(c + 1, n) {
                let f: Double = a[r][c] / a[c][c]
                if f == 0 { continue }
                for k in c..<n { a[r][k] -= f * a[c][k] }
                b[r] -= f * b[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for c in stride(from: n - 1, through: 0, by: -1) {
            var s: Double = b[c]
            for k in (c + 1)..<Swift.max(c + 1, n) { s -= a[c][k] * x[k] }
            x[c] = s / a[c][c]
        }
        return x
    }
}
