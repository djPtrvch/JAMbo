import SwiftUI

/// Размеры раскладки (как в вебе, style.css): зазоры, скругления, ширина шага секвенсора.
struct Layout {
    static let gap: CGFloat = 6
    static let radius: CGFloat = 10
    static let stepGap: CGFloat = 4
    static let topHeight: CGFloat = 44
    static let trackHeight: CGFloat = 50
    static let seqHeight: CGFloat = 60
    /// Ширина кнопок верхней панели (SCALE, UNDO, REDO, EQ, PATTERNS, ARRANGE).
    static let topButton: CGFloat = 107
    static let leftColumn: CGFloat = 220
    static let meterWidth: CGFloat = 30

    /// Ширина рабочей области (без полей).
    let width: CGFloat

    /// Ширина шага секвенсора (16 шагов с зазором 4) — и столбцов MIX и MST.
    var step: CGFloat { return max(1, (width - 15 * Layout.stepGap) / 16) }
    /// Высота пианоролла: квадратная клавиша + строка аккордов 44 px (S1c).
    var pianoHeight: CGFloat { return step + 50 }
}
