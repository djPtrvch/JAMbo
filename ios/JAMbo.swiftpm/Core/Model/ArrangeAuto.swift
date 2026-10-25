import Foundation

// Автоматизация на таймлайне аранжировки (S15f, docs/ai/arranger.md): у дорожки по кривой на ручку сетки. Точка — шаг
// таймлайна (дробный) и положение ручки 0…1; между точками — прямая. Кривая действует от первой точки до последней,
// пока дорожка идёт по таймлайну (вне — значение ручки).

/// Точка кривой: x — шаг таймлайна, y — положение ручки 0…1.
public struct ArrAutoPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Кривая ручки param (id ручки сетки) — точки по x.
public struct ArrAutoLane: Codable, Equatable, Sendable {
    public static let maxPoints = 2048
    public var param: String
    public var points: [ArrAutoPoint]

    public init(param: String, points: [ArrAutoPoint] = []) {
        self.param = param
        self.points = points
    }

    /// Значение 0…1 на шаге x; nil — до первой точки, после последней или точек нет.
    public func value(at x: Double) -> Double? {
        return ArrAutoLane.value(points, at: x)
    }

    public static func value(_ p: [ArrAutoPoint], at x: Double) -> Double? {
        guard let first = p.first, let last = p.last, x >= first.x, x <= last.x else { return nil }
        var lo: Int = 0
        var hi: Int = p.count - 1
        while hi - lo > 1 {
            let mid: Int = (lo + hi) / 2
            if p[mid].x <= x { lo = mid } else { hi = mid }
        }
        let a: ArrAutoPoint = p[lo]
        let b: ArrAutoPoint = p[hi]
        if b.x <= a.x { return b.y }
        let f: Double = (x - a.x) / (b.x - a.x)
        return a.y + (b.y - a.y) * Swift.min(1, Swift.max(0, f))
    }
}

/// Ручки сетки, которые можно автоматизировать (все 16): параметры голоса (VoiceParam), затем Duck, Chance, Ratchet.
public enum ArrAutoTarget {
    public static let ids: [String] = VoiceParam.ids + ["sidechain", "prob", "ratchet"]
    public static let count = VoiceParam.count + 3
    public static let sidechain = VoiceParam.count
    public static let prob = VoiceParam.count + 1
    public static let ratchet = VoiceParam.count + 2

    public static func index(_ id: String) -> Int? {
        return ids.firstIndex(of: id)
    }
}

extension Track {
    /// Номер кривой ручки id (nil — нет).
    public func autoLane(_ id: String) -> Int? {
        return autos.firstIndex { $0.param == id }
    }

    /// Точки кривой ручки id (по x, не больше maxPoints, y в 0…1); пустые точки кривую не удаляют.
    public mutating func setAuto(_ id: String, _ points: [ArrAutoPoint]) {
        guard ArrAutoTarget.index(id) != nil else { return }
        var p: [ArrAutoPoint] = points.map { ArrAutoPoint(x: Swift.max(0, $0.x), y: Swift.min(1, Swift.max(0, $0.y))) }
        p.sort { $0.x < $1.x }
        if p.count > ArrAutoLane.maxPoints { p = Array(p.prefix(ArrAutoLane.maxPoints)) }
        if let k = autoLane(id) {
            autos[k].points = p
        } else {
            autos.append(ArrAutoLane(param: id, points: p))
        }
    }

    public mutating func deleteAuto(_ id: String) {
        autos.removeAll { $0.param == id }
    }
}

extension ArrAutoLane {
    /// Упрощение записи (Рамер — Дуглас — Пекер по значению): точка уходит, если кривая без неё отклоняется не больше
    /// tol (доля хода ручки); концы остаются.
    public static func simplify(_ p: [ArrAutoPoint], tol: Double) -> [ArrAutoPoint] {
        if p.count <= 2 { return p }
        var keep: [Bool] = [Bool](repeating: false, count: p.count)
        keep[0] = true
        keep[p.count - 1] = true
        var stack: [(Int, Int)] = [(0, p.count - 1)]
        while let (a, b) = stack.popLast() {
            if b - a < 2 { continue }
            var worst: Double = -1
            var at: Int = -1
            let dx: Double = p[b].x - p[a].x
            var i: Int = a + 1
            while i < b {
                let f: Double = dx > 0 ? (p[i].x - p[a].x) / dx : 0
                let y: Double = p[a].y + (p[b].y - p[a].y) * f
                let d: Double = abs(p[i].y - y)
                if d > worst {
                    worst = d
                    at = i
                }
                i += 1
            }
            if worst > tol && at > 0 {
                keep[at] = true
                stack.append((a, at))
                stack.append((at, b))
            }
        }
        var out: [ArrAutoPoint] = []
        for (i, pt) in p.enumerated() where keep[i] { out.append(pt) }
        return out
    }
}

extension Track {
    /// Записанный кусок кривой ручки id (S15f3): точки на участке [первая, последняя] заменяются куском (упрощённым);
    /// вне участка — не трогаются. Кривой нет — появляется.
    public mutating func recordAuto(_ id: String, _ take: [ArrAutoPoint], tol: Double = 0.01) {
        guard let a = take.first, let b = take.last, ArrAutoTarget.index(id) != nil else { return }
        let piece: [ArrAutoPoint] = ArrAutoLane.simplify(take, tol: tol)
        var pts: [ArrAutoPoint] = autoLane(id).map { autos[$0].points } ?? []
        pts.removeAll { $0.x >= a.x && $0.x <= b.x }
        pts.append(contentsOf: piece)
        setAuto(id, pts)
    }
}
