import SwiftUI

/// Пианоролл (S8): на месте центра, размером с сетку паттернов. Слева клавиши — ноты гаммы (шириной с колонку строк
/// сетки паттернов), в середине сетка с нотами открытого клипа выбранной дорожки (выбранные страницы подряд),
/// справа (над MST) — бутерброд (GRID, звук ноты при нажатии) и под ним VEL, как LOOP ROW у сетки паттернов.
struct RollWindow: View {
    let model: AppModel
    let layout: Layout
    @State private var port = RollPort()

    var body: some View {
        GeometryReader { geo in
            let h: CGFloat = (geo.size.height - 7 * PatternGrid.rowGap) / 8
            ZStack(alignment: .topLeading) {
                HStack(spacing: Layout.gap) {
                    RollKeys(model: model, port: $port).frame(width: layout.step)
                    RollGrid(model: model, port: $port)
                    RollSide(model: model, buttonH: h).frame(width: layout.step)
                }
                if model.rollMenuOpen {
                    menu(geo.size)
                }
            }
        }
    }

    /// Меню бутерброда — у правого края сетки, шириной в три шага; тап мимо — закрыть.
    @ViewBuilder
    private func menu(_ size: CGSize) -> some View {
        let w: CGFloat = min(size.width, 3 * layout.step + 2 * Layout.gap)
        Color.black.opacity(0.001)
            .frame(width: size.width, height: size.height)
            .onTapGesture { model.rollMenuOpen = false }
        RollMenu(model: model)
            .frame(width: w)
            .frame(maxHeight: size.height, alignment: .top)
            .offset(x: size.width - layout.step - Layout.gap - w, y: 0)
    }
}

/// Вид пианоролла: ширина шага и высота строки (масштаб), прокрутка (S8c). nil — по умолчанию: 16 шагов на ширину,
/// снизу видна октава C2 гаммы.
struct RollPort {
    var colW: CGFloat? = nil
    var rowH: CGFloat = 40
    var x: CGFloat = 0
    var y: CGFloat? = nil
}

/// Размеры и прокрутка для рисования и касаний (общие у клавиш и сетки — по высоте поля).
struct RollMetrics {
    let size: CGSize
    let rows: [Int]
    let cols: Int
    let colW: CGFloat
    let rowH: CGFloat
    let x: CGFloat
    let y: CGFloat

    init(size: CGSize, port: RollPort, rows: [Int], cols: Int, root: Int) {
        self.size = size
        self.rows = rows
        self.cols = cols
        let cw: CGFloat = port.colW ?? size.width / 16
        colW = max(4, cw)
        rowH = port.rowH
        let maxX: CGFloat = max(0, CGFloat(cols) * colW - size.width)
        x = min(maxX, max(0, port.x))
        let contentH: CGFloat = CGFloat(rows.count) * rowH
        let maxY: CGFloat = max(0, contentH - size.height)
        if let py = port.y {
            y = min(maxY, max(0, py))
        } else {
            // Нижняя строка поля — корневая нота октавы 2 (C2 при ROOT C), как на клавиатуре.
            let base: Int = Scales.baseNote(root: root, octave: Scales.octaveDef)
            let r: Int = rows.firstIndex(where: { $0 >= base }) ?? 0
            let bottom: CGFloat = CGFloat(rows.count - r) * rowH
            y = min(maxY, max(0, bottom - size.height))
        }
    }

    /// Верх строки r (r — индекс в rows, снизу вверх).
    func rowY(_ r: Int) -> CGFloat {
        return CGFloat(rows.count - 1 - r) * rowH - y
    }

    func colX(_ n: Int) -> CGFloat {
        return CGFloat(n) * colW - x
    }

    /// Видимые строки (индексы в rows).
    var visibleRows: ClosedRange<Int> {
        let n: Int = rows.count
        if n == 0 { return 0...0 }
        let top: Int = Int((y / rowH).rounded(.down))
        let bottom: Int = Int(((y + size.height) / rowH).rounded(.up))
        let hi: Int = max(0, min(n - 1, n - 1 - top))
        let lo: Int = max(0, min(hi, n - 1 - bottom))
        return lo...hi
    }

    /// Видимые столбцы (позиции прохода, и за его концом — до края поля).
    var visibleCols: ClosedRange<Int> {
        let a: Int = max(0, Int((x / colW).rounded(.down)))
        let b: Int = max(a, Int(((x + size.width) / colW).rounded(.up)))
        return a...b
    }
}

/// Цвет строки: корневая — выделена, диезы — чуть другим тоном.
enum RollColors {
    static func row(_ n: Int, root: Int, _ theme: Theme) -> Color {
        if Roll.isRoot(n, root: root) { return theme.root }
        return Roll.isSharp(n) ? theme.panel : theme.panel2
    }
}
