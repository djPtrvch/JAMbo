import SwiftUI

/// Клавиши пианоролла: ноты гаммы с подписями, корневая выделена, диезы чуть другим тоном; палец — прокрутка
/// вверх-вниз.
struct RollKeys: View {
    let model: AppModel
    @Binding var port: RollPort
    @State private var startY: CGFloat? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let rows: [Int] = model.rollRows
        let cols: Int = model.rollClip.playLen
        let root: Int = model.project.root
        return GeometryReader { geo in
            Canvas { ctx, size in
                let m = RollMetrics(size: size, port: port, rows: rows, cols: cols, root: root)
                draw(ctx, m, root)
            }
            .contentShape(Rectangle())
            .gesture(drag(RollMetrics(size: geo.size, port: port, rows: rows, cols: cols, root: root)))
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func drag(_ m: RollMetrics) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                let y0: CGFloat = startY ?? m.y
                if startY == nil { startY = y0 }
                port.y = y0 - g.translation.height
                port.y = RollMetrics(size: m.size, port: port, rows: m.rows, cols: m.cols, root: model.project.root).y
            }
            .onEnded { _ in startY = nil }
    }

    private func draw(_ ctx: GraphicsContext, _ m: RollMetrics, _ root: Int) {
        for r in m.visibleRows {
            let n: Int = m.rows[r]
            let y: CGFloat = m.rowY(r)
            let rect = CGRect(x: 0, y: y, width: m.size.width, height: m.rowH)
            ctx.fill(Path(rect), with: .color(RollColors.row(n, root: root, theme)))
            ctx.fill(Path(CGRect(x: 0, y: y + m.rowH - 1, width: m.size.width, height: 1)), with: .color(theme.grid))
            let isRoot: Bool = Roll.isRoot(n, root: root)
            let label = SwiftUI.Text(Params.noteName(n))
                .font(.system(size: 13, weight: isRoot ? .bold : .regular))
                .foregroundColor(isRoot ? theme.text : theme.dim)
            ctx.draw(label, at: CGPoint(x: m.size.width / 2, y: y + (m.rowH - 1) / 2), anchor: .center)
        }
    }
}

/// Сетка пианоролла: строки нот гаммы, линии по GRID (доли и такты — сильнее), подписи долей, ход, ноты.
struct RollGrid: View {
    let model: AppModel
    @Binding var port: RollPort
    @State private var touches = RollTouches()
    @Environment(\.theme) private var theme

    var body: some View {
        let rows: [Int] = model.rollRows
        let clip: Clip = model.rollClip
        let notes: [RollNote] = Roll.notes(clip)
        let root: Int = model.project.root
        let grid: Int = model.settings.rollGrid
        let play: Int = model.rollPlayPos
        let t: Track = model.track
        let levels: [Double] = notes.map { t.rollNoteLevel($0) }
        let pct: Bool = model.rollVel
        return GeometryReader { geo in
            Canvas { ctx, size in
                let m = RollMetrics(size: size, port: port, rows: rows, cols: clip.playLen, root: root)
                drawRows(ctx, m, root)
                drawColumns(ctx, m, grid, play)
                drawNotes(ctx, m, notes, levels, pct)
            }
            .contentShape(Rectangle())
            .gesture(touch(geo.size, rows, clip.playLen, root))
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    /// Все касания сетки — одним жестом (мультитач): прокрутка и масштаб — RollTouches; вид — в пределах поля.
    private func touch(_ size: CGSize, _ rows: [Int], _ cols: Int, _ root: Int) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in apply(events, size, rows, cols, root) }
            .onEnded { events in apply(events, size, rows, cols, root) }
    }

    /// Ноты берутся на момент касания (после правки — уже новые).
    private func apply(_ events: SpatialEventCollection, _ size: CGSize, _ rows: [Int], _ cols: Int, _ root: Int) {
        let m = RollMetrics(size: size, port: port, rows: rows, cols: cols, root: root)
        var p: RollPort = port
        touches.handle(events, port: &p, m, Roll.notes(model.rollClip), model)
        let c = RollMetrics(size: size, port: p, rows: rows, cols: cols, root: root)
        let next = RollPort(colW: p.colW, rowH: c.rowH, x: c.x, y: p.y == nil ? nil : c.y)
        if next.colW != port.colW || next.rowH != port.rowH || next.x != port.x || next.y != port.y { port = next }
    }

    private func drawRows(_ ctx: GraphicsContext, _ m: RollMetrics, _ root: Int) {
        for r in m.visibleRows {
            let y: CGFloat = m.rowY(r)
            ctx.fill(Path(CGRect(x: 0, y: y, width: m.size.width, height: m.rowH)), with: .color(RollColors.row(m.rows[r], root: root, theme)))
            ctx.fill(Path(CGRect(x: 0, y: y + m.rowH - 1, width: m.size.width, height: 1)), with: .color(theme.grid))
        }
    }

    /// Линии сетки (как у EQ): каждые GRID шагов — тонкая, доли — сильнее, такты — сильнее и толще; за концом прохода — тень.
    private func drawColumns(_ ctx: GraphicsContext, _ m: RollMetrics, _ grid: Int, _ play: Int) {
        let h: CGFloat = m.size.height
        if play >= 0 {
            ctx.fill(Path(CGRect(x: m.colX(play), y: 0, width: m.colW, height: h)), with: .color(theme.text.opacity(0.12)))
        }
        for n in m.visibleCols where n % grid == 0 || n % 4 == 0 {
            let x: CGFloat = m.colX(n)
            let w: CGFloat = n % 16 == 0 ? 2 : 1
            let c: Color = n % 4 == 0 ? theme.gridStrong : theme.grid
            ctx.fill(Path(CGRect(x: x - w / 2, y: 0, width: w, height: h)), with: .color(c))
            if n % 4 == 0 && n < m.cols {
                let label = SwiftUI.Text(Roll.beatLabel(n)).font(.system(size: 11)).foregroundColor(theme.dim)
                ctx.draw(label, at: CGPoint(x: x + 5, y: 3), anchor: .topLeading)
            }
        }
        let end: CGFloat = m.colX(m.cols)
        if end < m.size.width {
            ctx.fill(Path(CGRect(x: end, y: 0, width: m.size.width - end, height: h)), with: .color(Color.black.opacity(0.35)))
        }
    }

    /// Ноты: полупрозрачные белые (в светлой теме — чёрные), velocity — заливка снизу; нота длиннее прохода — до его
    /// конца. С VEL — ещё и число в процентах.
    private func drawNotes(_ ctx: GraphicsContext, _ m: RollMetrics, _ notes: [RollNote], _ levels: [Double],
                           _ pct: Bool) {
        let span: ClosedRange<Int> = m.visibleCols
        for (i, note) in notes.enumerated() where note.pos <= span.upperBound && note.pos + note.len >= span.lowerBound {
            guard let r = m.rows.firstIndex(of: note.pitch) else { continue }
            let end: Int = min(note.pos + note.len, m.cols)
            let x0: CGFloat = m.colX(note.pos) + 1
            let w: CGFloat = max(2, CGFloat(end - note.pos) * m.colW - 2)
            let rect = CGRect(x: x0, y: m.rowY(r) + 1, width: w, height: max(2, m.rowH - 3))
            let shape = Path(roundedRect: rect, cornerRadius: 3)
            drawLevel(ctx, rect, i < levels.count ? levels[i] : 127, pct)
            ctx.stroke(shape, with: .color(theme.panel), lineWidth: 1)
        }
    }

    private func drawLevel(_ ctx: GraphicsContext, _ rect: CGRect, _ level: Double, _ pct: Bool) {
        let k: CGFloat = CGFloat(max(0, min(127, level)) / 127)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(theme.text.opacity(0.3)))
        let h: CGFloat = rect.height * k
        let bar = CGRect(x: rect.minX, y: rect.maxY - h, width: rect.width, height: h)
        ctx.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(theme.text))
        if !pct || rect.width < 34 || rect.height < 16 { return }
        let pct: Int = Int((Double(k) * 100).rounded())
        // Число velocity — всегда чёрное.
        let label = SwiftUI.Text("\(pct)%").font(.system(size: 11, weight: .bold))
            .foregroundColor(Color.black)
        ctx.draw(label, at: CGPoint(x: rect.minX + 4, y: rect.midY), anchor: .leading)
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
