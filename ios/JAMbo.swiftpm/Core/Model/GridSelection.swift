import Foundation

// Выделение рамкой в сетке паттернов и перенос выделенного в аранжировку (TO ARRANGE).

/// Ячейка сетки: дорожка и строка.
public struct CellRef: Hashable {
    public let track: Int
    public let row: Int

    public init(track: Int, row: Int) {
        self.track = track
        self.row = row
    }
}

/// Выделение рамкой: строки целиком (рамка задела колонку строк) и клипы (только заполненные ячейки).
public struct GridSelection: Equatable {
    public var rows: Set<Int> = []
    public var cells: Set<CellRef> = []

    public init(rows: Set<Int> = [], cells: Set<CellRef> = []) {
        self.rows = rows
        self.cells = cells
    }

    public var isEmpty: Bool { return rows.isEmpty && cells.isEmpty }

    public func contains(_ c: CellRef) -> Bool { return rows.contains(c.row) || cells.contains(c) }

    /// В строке k что-то выделено (строка целиком или её клипы).
    public func touches(row k: Int) -> Bool { return rows.contains(k) || cells.contains { $0.row == k } }

    /// Строки выделения сверху вниз.
    public var orderedRows: [Int] {
        var all: Set<Int> = rows
        for c in cells { all.insert(c.row) }
        return all.sorted()
    }
}

extension Project {
    /// TO ARRANGE выделения: строки сверху вниз, одна за другой с позиции at (nil — в конец аранжировки). Строка
    /// целиком — как rowToArrange (все дорожки, повторы, секция); иначе — только выделенные клипы строки: один проход
    /// самого длинного из них, короткие повторяются, без секции. Конец участка; nil — нечего переносить.
    @discardableResult
    public mutating func selectionToArrange(_ sel: GridSelection, at: Int?) -> Int? {
        var pos: Int? = at
        var last: Int? = nil
        for k in sel.orderedRows {
            var end: Int? = nil
            if sel.rows.contains(k) {
                end = rowToArrange(k, at: pos)
            } else {
                let only: [Int] = sel.cells.filter { $0.row == k }.map { $0.track }.sorted()
                end = placeRow(k, tracks: only, repeats: 1, at: pos)?.end
            }
            if let e = end {
                pos = e
                last = e
            }
        }
        return last
    }
}

extension Project {
    /// INSERT места (решение пользователя: выделение кладут на занятый участок — «раздвинуть»): с шага x всё сдвигается
    /// вправо на length — блоки всех дорожек (блок через x делится), точки автоматизации, секции (секция через x
    /// длиннее на length).
    public mutating func insertSpace(at x: Int, length: Int) {
        if length <= 0 { return }
        let at: Int = Swift.max(0, x)
        let d: Double = Double(length)
        for t in tracks.indices {
            tracks[t].shiftArrange(after: at, by: length)
            for l in tracks[t].autos.indices {
                for i in tracks[t].autos[l].points.indices where tracks[t].autos[l].points[i].x >= Double(at) {
                    tracks[t].autos[l].points[i].x += d
                }
            }
        }
        for k in arrange.markers.indices {
            let m: ArrMarker = arrange.markers[k]
            if m.at >= at {
                arrange.markers[k].at += length
                if let e = m.end { arrange.markers[k].end = e + length }
            } else if let e = m.end, e > at {
                arrange.markers[k].end = e + length
            }
        }
    }

    /// Выделение на участке с шага at кладётся поверх блоков (перекроет их)? Проба на копии: блоки тех же дорожек на
    /// участке [at, конец).
    public func selectionOverlaps(_ sel: GridSelection, at: Int) -> Bool {
        var probe: Project = self
        guard let end = probe.selectionToArrange(sel, at: at) else { return false }
        for t in tracks.indices where t < probe.tracks.count && probe.tracks[t].blocks != tracks[t].blocks {
            if tracks[t].blocks.contains(where: { $0.start < end && $0.end > at }) { return true }
        }
        return false
    }
}
