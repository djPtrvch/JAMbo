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
