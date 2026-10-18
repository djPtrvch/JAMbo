import SwiftUI

/// Миниатюры страниц (паттерны дорожки) строками, под ними «+». Белая обводка — играющие страницы,
/// светлее — открытая в секвенсоре. Тап (через 0,3 с, если не было второго) — эта страница играет и открыта;
/// протягивание — несколько играющих; удержание (0,45 с) — открыть страницу, не меняя играющих;
/// двойной тап — меню страницы.
struct PagesColumn: View {
    let model: AppModel
    @State private var press: PagePress? = nil
    /// Отпущенная перенесённая страница: уже на новом месте, плавно встаёт из-под пальца (сдвиг dy → 0).
    @State private var landing: (row: Int, dy: CGFloat)? = nil
    @State private var tapTask: Task<Void, Never>? = nil
    @State private var lastTap: (row: Int, at: Date)? = nil
    @State private var rowStep: CGFloat = 50
    @State private var columnHeight: CGFloat = 400
    @Environment(\.theme) private var theme

    static let rows = 8

    var body: some View {
        GeometryReader { geo in
            let rowH: CGFloat = (geo.size.height - 4 * CGFloat(PagesColumn.rows - 1)) / CGFloat(PagesColumn.rows)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    ForEach(0..<PagesColumn.rows, id: \.self) { r in
                        let dragged: Bool = press?.lifting == true && press?.row == r
                        let lifted: Bool = dragged || landing?.row == r
                        // Поднятая идёт за пальцем без анимации (иначе отстаёт и прыгает на смене места);
                        // плавно сдвигаются только соседи.
                        row(r).frame(height: rowH)
                            .offset(y: pageOffset(r, step: rowH + 4))
                            .scaleEffect(lifted ? 1.06 : 1)
                            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 8)
                            .zIndex(lifted ? 1 : 0)
                            .animation(dragged ? nil : .easeOut(duration: 0.15), value: press?.liftTo)
                    }
                }
                outline(rowH: rowH)
            }
            .contentShape(Rectangle())
            .gesture(drag(rowH: rowH + 4))
            .onAppear {
                rowStep = rowH + 4
                columnHeight = geo.size.height
            }
            .onChange(of: geo.size.height) { _, h in
                columnHeight = h
                rowStep = (h - 4 * CGFloat(PagesColumn.rows - 1)) / CGFloat(PagesColumn.rows) + 4
            }
        }
    }

    @ViewBuilder
    private func row(_ r: Int) -> some View {
        let n: Int = model.channel == .track ? model.track.pages.count : 0
        if r < n {
            PageThumb(model: model, page: r)
        } else if r == n && n < Params.maxPages && model.channel == .track {
            PlusThumb()
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func outline(rowH: CGFloat) -> some View {
        if model.channel == .track {
            let t: Track = model.track
            let top: CGFloat = CGFloat(t.playFrom) * (rowH + 4) - 3
            let h: CGFloat = CGFloat(t.playTo - t.playFrom + 1) * (rowH + 4) - 4 + 6
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.text, lineWidth: 1)
                .frame(height: h)
                .padding(.horizontal, -3)
                .offset(y: top)
                .allowsHitTesting(false)
        }
    }

    /// Перенос страницы: поднятая — за пальцем, страницы между старым и новым местом — на соседнее.
    private func pageOffset(_ r: Int, step: CGFloat) -> CGFloat {
        if let l = landing, l.row == r { return l.dy }
        guard let p = press, p.lifting else { return 0 }
        if r == p.row { return p.liftY - p.y0 }
        if p.row < p.liftTo && r > p.row && r <= p.liftTo { return -step }
        if p.liftTo < p.row && r >= p.liftTo && r < p.row { return step }
        return 0
    }

    private func rowAt(_ y: CGFloat, step: CGFloat) -> Int {
        return max(0, Int(y / step))
    }

    /// Касание у границы обводки (0,4 высоты страницы по обе стороны) берёт этот край; в середине обводки —
    /// перенос её целиком; снаружи — новые страницы от и до. Сдвиг больше 8 px — уже не тап.
    private func drag(rowH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if press == nil { begin(g.startLocation.y, step: rowH) }
                guard var p = press else { return }
                // Удержание страницы (она поднята) и протягивание — перенос: миниатюра идёт за пальцем, соседи сдвигаются.
                if p.lifting {
                    p.liftY = g.location.y
                    let n: Int = model.track.pages.count
                    p.liftTo = min(n - 1, max(0, Int(g.location.y / rowH)))
                    if abs(g.translation.height) > 8 { p.moved = true }
                    press = p
                    return
                }
                if !p.moved && abs(g.translation.height) > 8 {
                    p.moved = true
                    press = p
                    model.beginGesture()
                }
                if p.moved && !p.plus && !p.held { follow(&p, y: g.location.y, step: rowH) }
            }
            .onEnded { _ in end() }
    }

    private func begin(_ y: CGFloat, step: CGFloat) {
        model.ensureAudio()
        guard model.channel == .track else { return }
        let n: Int = model.track.pages.count
        let r: Int = rowAt(y, step: step)
        let mode: PageDragMode = dragMode(y, step: step)
        if r > n && mode == .range { return }
        var p = PagePress(row: min(r, n), plus: r == n && mode == .range)
        p.mode = mode
        p.y0 = y
        p.from0 = model.track.playFrom
        p.to0 = model.track.playTo
        press = p
        let started: Date = p.t0
        let nearEdge: Bool = edgeDistance(y, step: step) < 0.25 * (step - 4)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard var cur = press, cur.t0 == started, !cur.moved, !cur.plus, !nearEdge else { return }
            cur.held = true
            // Страница открыта в секвенсоре и поднята: протягивание переносит её.
            cur.lifting = cur.row < model.track.pages.count
            cur.liftTo = cur.row
            cur.liftY = cur.y0
            withAnimation(.easeOut(duration: 0.12)) { press = cur }
            model.viewPage = cur.row
            model.spanView = false
        }
    }

    /// Расстояние до ближайшей границы обводки.
    private func edgeDistance(_ y: CGFloat, step: CGFloat) -> CGFloat {
        let t: Track = model.track
        let top: CGFloat = CGFloat(t.playFrom) * step
        let bottom: CGFloat = CGFloat(t.playTo + 1) * step - 4
        return min(abs(y - top), abs(y - bottom))
    }

    private func dragMode(_ y: CGFloat, step: CGFloat) -> PageDragMode {
        let t: Track = model.track
        let rowH: CGFloat = step - 4
        let top: CGFloat = CGFloat(t.playFrom) * step
        let bottom: CGFloat = CGFloat(t.playTo + 1) * step - 4
        let grab: CGFloat = 0.4 * rowH
        if abs(y - bottom) < grab && abs(y - bottom) <= abs(y - top) { return .bottom }
        if abs(y - top) < grab { return .top }
        if y > top && y < bottom { return .move }
        return .range
    }

    /// Протягивание: край идёт за пальцем (страница берётся или отпускается, когда край зашёл в неё на треть),
    /// обводка целиком — сдвигом на целые страницы, снаружи — диапазон от первой страницы до пальца.
    private func follow(_ p: inout PagePress, y: CGFloat, step: CGFloat) {
        let n: Int = model.track.pages.count
        let rowH: CGFloat = step - 4
        var from: Int = model.track.playFrom
        var to: Int = model.track.playTo
        switch p.mode {
        case .top:
            while from < to && y > CGFloat(from) * step + rowH / 3 { from += 1 }
            while from > 0 && y < CGFloat(from - 1) * step + rowH * 2 / 3 { from -= 1 }
        case .bottom:
            while to > from && y < CGFloat(to) * step + rowH * 2 / 3 { to -= 1 }
            while to < n - 1 && y > CGFloat(to + 1) * step + rowH / 3 { to += 1 }
        case .move:
            let len: Int = p.to0 - p.from0
            let d: Int = Int(((y - p.y0) / step).rounded())
            from = min(max(0, p.from0 + d), n - 1 - len)
            to = from + len
        case .range:
            let r: Int = min(rowAt(y, step: step), n - 1)
            let a: Int = min(p.row, n - 1)
            from = min(a, r)
            to = max(a, r)
        }
        if from != model.track.playFrom || to != model.track.playTo { model.playPages(from, to) }
    }

    private func end() {
        guard let p = press else { return }
        if p.lifting {
            land(p)
            return
        }
        press = nil
        if p.moved {
            model.endGesture()
            return
        }
        if p.held { return }
        if p.plus {
            model.addPage()
            return
        }
        if p.row < model.track.pages.count { tap(p.row) }
    }

    /// Отпустили перенесённую страницу: страницы встают на новые места без анимации (соседи уже там), а сама
    /// страница — из-под пальца на своё место за 0,18 с (через кадр, чтобы сдвиг успел отрисоваться).
    private func land(_ p: PagePress) {
        let dy: CGFloat = p.liftY - p.y0 - CGFloat(p.liftTo - p.row) * rowStep
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            press = nil
            landing = (p.liftTo, dy)
            if p.liftTo != p.row { model.movePage(p.row, p.liftTo) }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            withAnimation(.easeOut(duration: 0.18)) { landing = nil }
        }
    }

    /// Тап: второй за 0,3 с — меню страницы; иначе через 0,3 с — эта страница играет.
    private func tap(_ r: Int) {
        if let last = lastTap, last.row == r, Date().timeIntervalSince(last.at) < 0.3 {
            tapTask?.cancel()
            lastTap = nil
            model.pageMenu = PageMenuState(page: r, y: CGFloat(r + 1) * rowStep, maxY: columnHeight)
            return
        }
        lastTap = (r, Date())
        tapTask?.cancel()
        tapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            model.playPages(r, r)
        }
    }
}

struct PagePress {
    let row: Int
    let plus: Bool
    let t0: Date = Date()
    var moved: Bool = false
    var held: Bool = false
    /// Перенос страницы (удержание и протягивание): идёт ли, куда встанет, где палец.
    var lifting: Bool = false
    var liftTo: Int = 0
    var liftY: CGFloat = 0
    var mode: PageDragMode = .range
    var y0: CGFloat = 0
    var from0: Int = 0
    var to0: Int = 0
}

/// Что тянет палец по миниатюрам: верхний или нижний край обводки, обводку целиком или новый диапазон.
enum PageDragMode {
    case top
    case bottom
    case move
    case range
}

/// Миниатюра страницы: 16 ячеек (пустые серые, триги белые, хвосты полупрозрачные, p-lock не отмечаются;
/// играющий шаг — жёлтый контур, за длиной — бледные).
struct PageThumb: View {
    let model: AppModel
    let page: Int
    @Environment(\.theme) private var theme

    var body: some View {
        // Данные читаются здесь (в теле), а не в Canvas: так правки и ход игры перерисовывают миниатюру.
        let cells: [ThumbCell] = ThumbCell.page(model.track, page: page)
        let played: Int = model.openPlayPos
        let pos: Int = model.playing && played >= 0 ? played - page * Params.stepsPerPage : -1
        let current: Bool = model.viewPages.contains(page)
        let colors: ThumbColors = ThumbColors(theme: theme)
        return Canvas { ctx, size in PageThumb.draw(ctx, size, cells, pos, colors) }
            .padding(4)
            .background(current ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: 6))
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ cells: [ThumbCell], _ pos: Int, _ c: ThumbColors) {
        let n: Int = cells.count
        let w: CGFloat = (size.width - 2 * CGFloat(n - 1)) / CGFloat(n)
        for (s, cell) in cells.enumerated() {
            let rect = CGRect(x: CGFloat(s) * (w + 2), y: 0, width: w, height: size.height)
            let path = Path(roundedRect: rect, cornerRadius: 2)
            var color: Color = c.off
            if cell.on {
                color = c.text
            } else if cell.tail {
                color = c.text.opacity(0.45)
            }
            ctx.fill(path, with: .color(cell.outside ? color.opacity(0.12) : color))
            if s == pos {
                // Контур внутри ячейки: снаружи его срезал бы край холста.
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 2), with: .color(c.accent), lineWidth: 1.5)
            }
        }
    }
}

/// Ячейка миниатюры.
struct ThumbCell {
    let on: Bool
    let tail: Bool
    let outside: Bool

    static func page(_ t: Track, page: Int) -> [ThumbCell] {
        let n: Int = Params.stepsPerPage
        // Страницу могли только что удалить, а миниатюра ещё не убрана — пустые ячейки вместо падения.
        if page >= t.pages.count { return [ThumbCell](repeating: ThumbCell(on: false, tail: false, outside: false), count: n) }
        let len: Int = t.pageLen(page)
        return (0..<n).map { s in
            let st: Step = t.pages[page][s]
            return ThumbCell(on: st.on, tail: !st.on && t.isTail(page * n + s), outside: s >= len)
        }
    }
}

/// Цвета темы для рисования в Canvas.
struct ThumbColors {
    let off: Color
    let text: Color
    let accent: Color

    init(theme: Theme) {
        off = theme.off
        text = theme.text
        accent = theme.accent
    }
}

struct PlusThumb: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("+")
            .font(.system(size: 20))
            .foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.line, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
    }
}

/// Меню страницы: ◀ ▶ ▲ ▼ (окно не закрывается), duplicate, copy, paste, clear, delete.
/// Действуют на все играющие страницы, если страница в белой обводке, иначе только на неё.
struct PageMenu: View {
    static let width: CGFloat = 184
    static let rowHeight: CGFloat = 36
    /// Высота всего меню: 6 строк по 36 и зазоры по 6, поля 8.
    static let height: CGFloat = 6 * rowHeight + 5 * 6 + 16
    let model: AppModel
    let page: Int
    let close: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                arrow("◀", .left)
                arrow("▶", .right)
                arrow("▲", .up)
                arrow("▼", .down)
            }
            item("duplicate", .duplicate, enabled: model.canDuplicate(page))
            item("copy", .copy, enabled: true)
            item("paste", .paste, enabled: model.pageClipboard != nil)
            item("clear", .clear, enabled: true)
            item("delete", .delete, enabled: model.canDelete(page), red: true)
        }
        .padding(8)
        .frame(width: PageMenu.width)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    private func arrow(_ title: String, _ action: AppModel.PageAction) -> some View {
        InkButton(title: title, height: PageMenu.rowHeight) { model.pageAction(action, page: page) }
    }

    private func item(_ title: String, _ action: AppModel.PageAction, enabled: Bool, red: Bool = false) -> some View {
        let color: Color = !enabled ? theme.off : (red ? theme.rec : theme.text)
        return Button {
            model.pageAction(action, page: page)
            close()
        } label: {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: PageMenu.rowHeight)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Открытое меню страницы: номер страницы и низ её миниатюры в колонке (меню встаёт под ней, как в вебе).
struct PageMenuState: Equatable {
    let page: Int
    let y: CGFloat
    /// Низ колонки миниатюр (верх кнопок MORPH и FX): меню ниже не опускается.
    let maxY: CGFloat
}
