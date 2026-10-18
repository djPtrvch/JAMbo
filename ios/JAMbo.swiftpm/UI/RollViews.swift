import SwiftUI

/// Клавиши пианоролла: ноты гаммы с подписями, корневая выделена, диезы чуть другим тоном.
struct RollKeys: View {
    let model: AppModel
    let port: RollPort
    @Environment(\.theme) private var theme

    var body: some View {
        let rows: [Int] = model.rollRows
        let cols: Int = model.rollClip.playLen
        let root: Int = model.project.root
        return Canvas { ctx, size in
            let m = RollMetrics(size: size, port: port, rows: rows, cols: cols, root: root)
            draw(ctx, m, root)
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func draw(_ ctx: GraphicsContext, _ m: RollMetrics, _ root: Int) {
        for r in m.visibleRows {
            let n: Int = m.rows[r]
            let y: CGFloat = m.rowY(r)
            let rect = CGRect(x: 0, y: y, width: m.size.width, height: m.rowH - 1)
            ctx.fill(Path(rect), with: .color(RollColors.row(n, root: root, theme)))
            let isRoot: Bool = Roll.isRoot(n, root: root)
            let label = SwiftUI.Text(Params.noteName(n))
                .font(.system(size: 13, weight: isRoot ? .bold : .regular))
                .foregroundColor(theme.text)
            ctx.draw(label, at: CGPoint(x: m.size.width / 2, y: y + (m.rowH - 1) / 2), anchor: .center)
        }
    }
}

/// Сетка пианоролла: строки нот гаммы, линии по GRID (доли и такты — сильнее), подписи долей, ход, ноты.
struct RollGrid: View {
    let model: AppModel
    let port: RollPort
    @Environment(\.theme) private var theme

    var body: some View {
        let rows: [Int] = model.rollRows
        let clip: Clip = model.rollClip
        let notes: [RollNote] = Roll.notes(clip)
        let root: Int = model.project.root
        let grid: Int = model.settings.rollGrid
        let play: Int = model.rollPlayPos
        return Canvas { ctx, size in
            let m = RollMetrics(size: size, port: port, rows: rows, cols: clip.playLen, root: root)
            drawRows(ctx, m, root)
            drawColumns(ctx, m, grid, play)
            drawNotes(ctx, m, notes)
        }
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func drawRows(_ ctx: GraphicsContext, _ m: RollMetrics, _ root: Int) {
        for r in m.visibleRows {
            let rect = CGRect(x: 0, y: m.rowY(r), width: m.size.width, height: m.rowH - 1)
            ctx.fill(Path(rect), with: .color(RollColors.row(m.rows[r], root: root, theme)))
        }
    }

    /// Линии сетки: каждые GRID шагов тонкая, на долях — толще, на тактах — толще всего; за концом прохода — тень.
    private func drawColumns(_ ctx: GraphicsContext, _ m: RollMetrics, _ grid: Int, _ play: Int) {
        let h: CGFloat = m.size.height
        if play >= 0 {
            ctx.fill(Path(CGRect(x: m.colX(play), y: 0, width: m.colW, height: h)), with: .color(theme.text.opacity(0.12)))
        }
        for n in m.visibleCols where n % grid == 0 || n % 4 == 0 {
            let x: CGFloat = m.colX(n)
            let w: CGFloat = n % 16 == 0 ? 3 : (n % 4 == 0 ? 2 : 1)
            ctx.fill(Path(CGRect(x: x - w / 2, y: 0, width: w, height: h)), with: .color(theme.bg))
            if n % 4 == 0 && n < m.cols {
                let label = SwiftUI.Text(Roll.beatLabel(n)).font(.system(size: 11)).foregroundColor(theme.dim)
                ctx.draw(label, at: CGPoint(x: x + 5, y: 3), anchor: .topLeading)
            }
        }
        let end: CGFloat = m.colX(m.cols)
        if end < m.size.width {
            ctx.fill(Path(CGRect(x: end, y: 0, width: m.size.width - end, height: h)), with: .color(theme.bg.opacity(0.6)))
        }
    }

    /// Ноты: белые (в светлой теме — чёрные), ноты играющего шага — с обводкой; нота длиннее прохода — до его конца.
    private func drawNotes(_ ctx: GraphicsContext, _ m: RollMetrics, _ notes: [RollNote]) {
        let span: ClosedRange<Int> = m.visibleCols
        for note in notes where note.pos <= span.upperBound && note.pos + note.len >= span.lowerBound {
            guard let r = m.rows.firstIndex(of: note.pitch) else { continue }
            let end: Int = min(note.pos + note.len, m.cols)
            let x0: CGFloat = m.colX(note.pos) + 1
            let w: CGFloat = max(2, CGFloat(end - note.pos) * m.colW - 2)
            let rect = CGRect(x: x0, y: m.rowY(r) + 1, width: w, height: max(2, m.rowH - 3))
            let shape = Path(roundedRect: rect, cornerRadius: 3)
            ctx.fill(shape, with: .color(theme.text))
            ctx.stroke(shape, with: .color(theme.bg), lineWidth: 1)
        }
    }
}

/// Колонка справа (над MST): бутерброд и VEL — высотой со строку сетки паттернов.
struct RollSide: View {
    let model: AppModel
    let buttonH: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: PatternGrid.rowGap) {
            BurgerButton { model.rollMenuOpen = true }.frame(height: buttonH)
            velButton.frame(height: buttonH)
            Spacer(minLength: 0)
        }
    }

    private var velButton: some View {
        let on: Bool = model.rollVel
        return Text("VEL")
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(on ? theme.onAccent : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.accent : theme.panel2, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { model.rollVel.toggle() }
    }
}

/// Бутерброд пианоролла: GRID и звук ноты при нажатии (настройки, общие для проектов).
struct RollMenu: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let grid: Int = model.settings.rollGrid
        return MenuScroll {
            VStack(alignment: .leading, spacing: 6) {
                MenuHead(title: "GRID").padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(0..<Roll.grids.count, id: \.self) { k in
                        MenuItem(title: Roll.gridNames[k], current: Roll.grids[k] == grid) {
                            model.setRollGrid(Roll.grids[k])
                        }
                    }
                }
                ToggleRow(title: "NOTE PREVIEW", isOn: model.settings.rollSound) { model.setRollSound($0) }
                Text("Plays a note when you place it or touch it in the piano roll.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.dim)
            }
            .padding(.trailing, 6)
        }
        .modifier(MenuPanel())
    }
}

/// Кнопка пианоролла в верхней панели (на месте AUTO): значок пианино, горит, пока окно открыто.
struct RollButton: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.rollView
        return Image(systemName: "pianokeys")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(on ? theme.bg : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.text : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleRoll() }
    }
}
