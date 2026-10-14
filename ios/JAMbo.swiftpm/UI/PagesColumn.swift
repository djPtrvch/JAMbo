import SwiftUI

/// Миниатюры страниц (паттерны дорожки) строками, под ними «+». Белая обводка — играющие страницы,
/// светлее — открытая в секвенсоре. Тап (через 0,3 с, если не было второго) — эта страница играет и открыта;
/// протягивание — несколько играющих; удержание (0,45 с) — открыть страницу, не меняя играющих;
/// двойной тап — меню страницы.
struct PagesColumn: View {
    let model: AppModel
    @State private var press: PagePress? = nil
    @State private var tapTask: Task<Void, Never>? = nil
    @State private var lastTap: (row: Int, at: Date)? = nil
    @State private var menuPage: Int? = nil
    @Environment(\.theme) private var theme

    static let rows = 8

    var body: some View {
        GeometryReader { geo in
            let rowH: CGFloat = (geo.size.height - 4 * CGFloat(PagesColumn.rows - 1)) / CGFloat(PagesColumn.rows)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    ForEach(0..<PagesColumn.rows, id: \.self) { r in
                        row(r).frame(height: rowH)
                    }
                }
                outline(rowH: rowH)
            }
            .contentShape(Rectangle())
            .gesture(drag(rowH: rowH + 4))
            .popover(isPresented: menuShown, arrowEdge: .leading) {
                PageMenu(model: model, page: menuPage ?? 0) { menuPage = nil }
            }
        }
    }

    private var menuShown: Binding<Bool> {
        Binding(get: { menuPage != nil }, set: { if !$0 { menuPage = nil } })
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

    private func rowAt(_ y: CGFloat, step: CGFloat) -> Int {
        return max(0, Int(y / step))
    }

    private func drag(rowH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let r: Int = rowAt(g.location.y, step: rowH)
                if press == nil { begin(r) }
                guard var p = press else { return }
                if !p.moved && abs(g.translation.height) > 8 {
                    p.moved = true
                    press = p
                    model.beginGesture()
                }
                if p.moved && !p.plus && !p.held { selectRange(from: p.row, to: r) }
            }
            .onEnded { _ in end() }
    }

    private func begin(_ r: Int) {
        model.ensureAudio()
        guard model.channel == .track else { return }
        let n: Int = model.track.pages.count
        if r > n { return }
        press = PagePress(row: r, plus: r == n)
        let started: Date = Date()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard var p = press, p.row == r, !p.moved, !p.plus, p.t0 <= started.addingTimeInterval(0.01) else { return }
            p.held = true
            press = p
            model.viewPage = r
        }
    }

    private func selectRange(from a: Int, to b0: Int) {
        let b: Int = min(b0, model.track.pages.count - 1)
        model.playPages(min(a, b), max(a, b))
    }

    private func end() {
        guard let p = press else { return }
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
        tap(p.row)
    }

    /// Тап: второй за 0,3 с — меню страницы; иначе через 0,3 с — эта страница играет.
    private func tap(_ r: Int) {
        if let last = lastTap, last.row == r, Date().timeIntervalSince(last.at) < 0.3 {
            tapTask?.cancel()
            lastTap = nil
            menuPage = r
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
}

/// Миниатюра страницы: 16 ячеек (пустые серые, триги белые, хвосты полупрозрачные, p-lock жёлтые,
/// играющий шаг — жёлтый контур, за длиной — бледные).
struct PageThumb: View {
    let model: AppModel
    let page: Int
    @Environment(\.theme) private var theme

    var body: some View {
        // Данные читаются здесь (в теле), а не в Canvas: так правки и ход игры перерисовывают миниатюру.
        let cells: [ThumbCell] = ThumbCell.page(model.track, page: page)
        let pos: Int = model.playing ? model.live.playPos[model.selectedTrack] - page * Params.stepsPerPage : -1
        let current: Bool = model.viewPage == page
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
                color = cell.lock ? c.accent : c.text
            } else if cell.tail {
                color = c.text.opacity(0.45)
            }
            ctx.fill(path, with: .color(cell.outside ? color.opacity(0.12) : color))
            if !cell.on && cell.lock {
                ctx.stroke(path, with: .color(c.accent), lineWidth: 1)
            }
            if s == pos {
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 2), with: .color(c.accent), lineWidth: 1)
            }
        }
    }
}

/// Ячейка миниатюры.
struct ThumbCell {
    let on: Bool
    let tail: Bool
    let lock: Bool
    let outside: Bool

    static func page(_ t: Track, page: Int) -> [ThumbCell] {
        let n: Int = Params.stepsPerPage
        let len: Int = t.pageLen(page)
        return (0..<n).map { s in
            let st: Step = t.pages[page][s]
            let lock: Bool = st.on ? Track.hasManualLocks(st) : !st.locks.isEmpty
            return ThumbCell(on: st.on, tail: !st.on && t.isTail(page * n + s), lock: lock, outside: s >= len)
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
        .padding(10)
        .frame(width: 240)
        .background(theme.bg)
        .presentationCompactAdaptation(.popover)
    }

    private func arrow(_ title: String, _ action: AppModel.PageAction) -> some View {
        InkButton(title: title, height: 44) { model.pageAction(action, page: page) }
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
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
