import SwiftUI

/// Размеры раскладки (как в вебе, style.css): зазоры, скругления, ширина шага секвенсора.
struct Layout {
    static let gap: CGFloat = 6
    static let radius: CGFloat = 10
    /// Кнопки у низа экрана — не ниже этой высоты над низом (решение пользователя): ниже — скругление экрана iPad,
    /// касания там ненадёжны.
    static let bottomGuard: CGFloat = 30
    static let stepGap: CGFloat = 4
    static let topHeight: CGFloat = 44
    static let trackHeight: CGFloat = 50
    static let seqHeight: CGFloat = 60
    /// Пара кнопок боковых колонок (LFO1 · LFO2, MOD · FX…).
    static let pairHeight: CGFloat = 56
    /// Ширина кнопок верхней панели (SCALE, UNDO, REDO, EQ, PATTERNS, ARRANGE).
    static let topButton: CGFloat = 107
    static let leftColumn: CGFloat = 220
    static let meterWidth: CGFloat = 30
    /// Зазор под строкой кнопок (barH) — основной (решение пользователя): столбец над парами кнопок — строка кнопок и
    /// 8 миниатюр одной высоты, окна под строкой кнопок начинаются на одной высоте.
    static let barGap: CGFloat = 6

    /// Ширина рабочей области (без полей).
    let width: CGFloat
    /// Высота клавиатуры (низ экрана — ровно 3 строки дорожек аранжировщика, RootView); 0 — по квадратной клавише.
    var piano: CGFloat = 0

    /// Ширина шага секвенсора (16 шагов с зазором 4) — и столбцов MIX и MST.
    var step: CGFloat { return max(1, (width - 15 * Layout.stepGap) / 16) }
    /// Сторона квадратной клавиши: ширина клавиши при двух октавах гаммы (зависит от числа нот гаммы).
    func keySide(_ scale: Int) -> CGFloat {
        let count = CGFloat(Scales.keyCount(scale: scale, octaves: 2))
        let keys: CGFloat = width - 2 * step - 2 * Layout.stepGap
        return max(20, (keys - 3 * (count - 1)) / count)
    }

    /// Высота клавиатуры: квадратная клавиша + 50 px (место нижнего бутерброда) — от CHORD не меняется.
    func pianoHeight(_ scale: Int) -> CGFloat {
        return piano > 0 ? piano : keySide(scale) + 50
    }

    /// Высота CHORD (квадратная, шириной в шаг); нижний бутерброд — на остаток клавиатуры.
    func keyHeight(_ scale: Int) -> CGFloat {
        return max(20, min(step, pianoHeight(scale) - 50))
    }
}
