import Foundation

// Автоматизация на таймлайне аранжировки (S15f, docs/ai/arranger.md): у дорожки — строки ручек (Track.autos), точки
// кривых — в блоках (ArrBlock.autos, x от начала блока; решение пользователя 1.11). Точка — шаг (дробный) и положение
// ручки 0…1; между точками — прямая. Кривая блока действует от его первой точки до последней, пока дорожка идёт по
// таймлайну; вне — значение ручки. Блоки между собой не соединяются (решение пользователя 1.11).

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
    /// Номер строки ручки id (nil — нет). Track.autos — строки окна AUTO (ручки); точки — в блоках (ArrBlock.autos).
    public func autoLane(_ id: String) -> Int? {
        return autos.firstIndex { $0.param == id }
    }

    /// Группы кривой ручки id на таймлайне (абсолютные шаги): у каждого блока — своя. Между группами кривой нет;
    /// точки блока — в пределах [начало, конец] блока.
    public func autoGroups(_ id: String) -> [[ArrAutoPoint]] {
        var out: [[ArrAutoPoint]] = []
        for b in blocks {
            guard let l = b.autos.first(where: { $0.param == id }) else { continue }
            let s: Double = Double(b.start)
            let len: Double = Double(b.length)
            var cur: [ArrAutoPoint] = []
            for pt in l.points where pt.x >= 0 && pt.x <= len { cur.append(ArrAutoPoint(x: s + pt.x, y: pt.y)) }
            if !cur.isEmpty { out.append(cur) }
        }
        return out
    }

    /// Все точки кривой ручки id (абсолютные шаги, по порядку блоков).
    public func autoPoints(_ id: String) -> [ArrAutoPoint] {
        return autoGroups(id).flatMap { $0 }
    }

    /// Значение кривой ручки id на шаге x (nil — вне кривых групп).
    public func autoValue(_ id: String, at x: Double) -> Double? {
        for g in autoGroups(id) {
            if let v = ArrAutoLane.value(g, at: x) { return v }
        }
        return nil
    }

    /// Точки кривой ручки id (абсолютные шаги): каждая — в свой блок (под ней; на стыке двух — в блок прошлой точки);
    /// точки вне блоков не ставятся. Строки нет — появляется (пустые точки строку не удаляют).
    public mutating func setAuto(_ id: String, _ points: [ArrAutoPoint]) {
        guard ArrAutoTarget.index(id) != nil else { return }
        var p: [ArrAutoPoint] = points.map { ArrAutoPoint(x: Swift.max(0, $0.x), y: Swift.min(1, Swift.max(0, $0.y))) }
        p.sort { $0.x < $1.x }
        if p.count > ArrAutoLane.maxPoints { p = Array(p.prefix(ArrAutoLane.maxPoints)) }
        if autoLane(id) == nil { autos.append(ArrAutoLane(param: id)) }
        var per: [[ArrAutoPoint]] = [[ArrAutoPoint]](repeating: [], count: blocks.count)
        var last: Int = -1
        for pt in p {
            var k: Int = -1
            if last >= 0 && pt.x >= Double(blocks[last].start) && pt.x <= Double(blocks[last].end) {
                k = last
            } else if let j = blocks.lastIndex(where: { pt.x >= Double($0.start) && pt.x <= Double($0.end) }) {
                k = j
            }
            if k < 0 { continue }
            last = k
            per[k].append(ArrAutoPoint(x: pt.x - Double(blocks[k].start), y: pt.y))
        }
        for k in blocks.indices {
            // Точки за краями блока (после TRIM) — не видны и не звучат; правка кривой их убирает.
            blocks[k].autos.removeAll { $0.param == id }
            if !per[k].isEmpty { blocks[k].autos.append(ArrAutoLane(param: id, points: per[k])) }
        }
    }

    public mutating func deleteAuto(_ id: String) {
        autos.removeAll { $0.param == id }
        for k in blocks.indices { blocks[k].autos.removeAll { $0.param == id } }
    }

    /// Корзина: вся автоматизация дорожки (строки и точки блоков).
    public mutating func clearAllAutos() {
        autos = []
        for k in blocks.indices { blocks[k].autos = [] }
    }

    /// Проект прежнего формата: точки кривых дорожки — в блоки под ними; на краях блоков, через которые кривая
    /// проходила, — точки (внутри блоков звучит как раньше; в промежутках — значение ручки). У строк точек не остаётся.
    mutating func migrateAutos() {
        let old: [ArrAutoLane] = autos.filter { !$0.points.isEmpty }
        if old.isEmpty { return }
        for l in old {
            setAuto(l.param, l.points)
            for k in blocks.indices {
                for e in [blocks[k].start, blocks[k].end] {
                    if let v = l.value(at: Double(e)) { blocks[k].pinAuto(l.param, x: Double(e - blocks[k].start), y: v) }
                }
            }
        }
        for k in autos.indices { autos[k].points = [] }
    }

    /// LINK прежних проектов (1.11): у блоков вплотную — точки на стыке по прямой LINK (звучит как раньше); через
    /// промежуток не соединяется (там — значение ручки).
    mutating func dropLegacyLinks() {
        for i in blocks.indices where blocks[i].legacyLink {
            blocks[i].legacyLink = false
            guard i + 1 < blocks.count, blocks[i].end == blocks[i + 1].start else { continue }
            let e: Double = Double(blocks[i].end)
            for l in blocks[i].autos {
                guard let a = l.points.last(where: { $0.x <= Double(blocks[i].length) }),
                      let nl = blocks[i + 1].autos.first(where: { $0.param == l.param }),
                      let b = nl.points.first(where: { $0.x >= 0 }) else { continue }
                let ax: Double = Double(blocks[i].start) + a.x
                let bx: Double = e + b.x
                let y: Double = bx > ax ? a.y + (b.y - a.y) * (e - ax) / (bx - ax) : b.y
                blocks[i].pinAuto(l.param, x: e - Double(blocks[i].start), y: y)
                blocks[i + 1].pinAuto(l.param, x: 0, y: y)
            }
        }
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
        var pts: [ArrAutoPoint] = autoPoints(id)
        pts.removeAll { $0.x >= a.x && $0.x <= b.x }
        pts.append(contentsOf: piece)
        setAuto(id, pts)
    }
}
