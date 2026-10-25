import SwiftUI

/// Окно аранжировщика (S15c, docs/ai/arranger.md): на месте центра. Слева заголовки дорожек, справа таймлайн:
/// линейка (номера тактов, планка петли), строка маркеров секций, строки дорожек с блоками, жёлтый курсор.
struct ArrangeWindow: View {
    let model: AppModel
    /// Поднятый блок (удержание и перетаскивание) — рисуется поверх таймлайна.
    @State private var lift: ArrLift? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                HStack(spacing: Layout.gap) {
                    ArrHeaders(model: model).frame(width: ArrMetrics.headerW)
                    ArrTimeline(model: model, lift: $lift)
                }
                ArrMenus(model: model, size: geo.size)
            }
        }
    }
}

/// Поднятый блок: дорожка, номер, блок, где он сейчас (начало в шагах, дробное — за пальцем) и куда встанет.
struct ArrLift: Equatable {
    let track: Int
    let index: Int
    let block: ArrBlock
    var at: Double
    var target: Int
}

/// Размеры и прокрутка таймлайна (общие у рисования и касаний).
struct ArrMetrics {
    static let headerW: CGFloat = 236
    static let rulerH: CGFloat = 20
    static let markerH: CGFloat = 18
    static let top: CGFloat = rulerH + markerH
    static let stepsPerBar: Int = ArrGrid.stepsPerBar

    let size: CGSize
    let stepW: CGFloat
    let x: CGFloat
    let y: CGFloat
    let rowH: CGFloat
    let tracks: Int
    /// Шагов, до которых можно прокрутить.
    let steps: Int

    init(size: CGSize, port: ArrPort, tracks: Int, end: Int) {
        self.size = size
        self.tracks = tracks
        let w: CGFloat = max(1, size.width)
        let fit: CGFloat = w / 256
        let want: CGFloat = port.stepW ?? fit
        stepW = ArrMetrics.clampStep(want, width: w)
        rowH = ArrMetrics.clampRow(port.rowH)
        steps = max(end, 0) + 32 * ArrMetrics.stepsPerBar
        let maxX: CGFloat = max(0, CGFloat(steps) * stepW - w)
        x = min(maxX, max(0, port.x))
        let lanes: CGFloat = max(0, size.height - ArrMetrics.top)
        let maxY: CGFloat = max(0, CGFloat(tracks) * rowH - lanes)
        y = min(maxY, max(0, port.y))
    }

    /// Масштаб по времени: от 64 до 4 тактов на ширину окна.
    static func clampStep(_ s: CGFloat, width: CGFloat) -> CGFloat {
        let lo: CGFloat = width / CGFloat(64 * stepsPerBar)
        let hi: CGFloat = width / CGFloat(4 * stepsPerBar)
        return min(hi, max(lo, s))
    }

    static func clampRow(_ h: CGFloat) -> CGFloat {
        return min(96, max(28, h))
    }

    func stepX(_ s: Double) -> CGFloat {
        return CGFloat(s) * stepW - x
    }

    func rowY(_ t: Int) -> CGFloat {
        return ArrMetrics.top + CGFloat(t) * rowH - y
    }

    /// Шаг под точкой (дробный).
    func step(at px: CGFloat) -> Double {
        return Double((px + x) / stepW)
    }

    /// Дорожка под точкой (−1 — не дорожка: линейка или ниже последней).
    func track(at py: CGFloat) -> Int {
        if py < ArrMetrics.top { return -1 }
        let t: Int = Int(((py - ArrMetrics.top + y) / rowH).rounded(.down))
        return t >= 0 && t < tracks ? t : -1
    }

    func rect(_ t: Int, _ b: ArrBlock) -> CGRect {
        return CGRect(x: stepX(Double(b.start)), y: rowY(t) + 2, width: max(2, CGFloat(b.length) * stepW), height: rowH - 4)
    }

    /// Шаг подписей тактов: не теснее ~36 pt.
    var barLabelEvery: Int {
        let barW: CGFloat = stepW * CGFloat(ArrMetrics.stepsPerBar)
        var n: Int = 1
        while CGFloat(n) * barW < 36 { n *= 2 }
        return n
    }
}

/// Таймлайн: Canvas и все касания одним жестом (ArrTouches).
struct ArrTimeline: View {
    let model: AppModel
    @Binding var lift: ArrLift?
    @State private var touches = ArrTouches()
    @Environment(\.theme) private var theme

    var body: some View {
        let p: Project = model.project
        let port: ArrPort = model.arrPort
        let now: Int = model.arrNow
        let sel: ArrSel? = model.arrSel
        let following: [Bool] = (0..<p.tracks.count).map { model.arrFollowing($0) }
        return GeometryReader { geo in
            let m = ArrMetrics(size: geo.size, port: port, tracks: p.tracks.count, end: p.arrangeEnd)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    ArrDraw(ctx: ctx, m: m, theme: theme).draw(p, cursor: now, sel: sel, lift: lift, following: following,
                                                            names: { model.arrClipName($0) })
                }
                if let l = lift { liftedView(l, m, p) }
            }
            .contentShape(Rectangle())
            .gesture(touch(geo.size))
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    /// Поднятый блок — над дорожкой, с тенью; при отпускании плавно встаёт на место (анимация позиции).
    private func liftedView(_ l: ArrLift, _ m: ArrMetrics, _ p: Project) -> some View {
        let w: CGFloat = max(2, CGFloat(l.block.length) * m.stepW)
        let h: CGFloat = m.rowH - 4
        let color: Color = l.track < p.tracks.count ? ArrColors.color(p.tracks[l.track].color) : ArrColors.color(0)
        let cx: CGFloat = m.stepX(l.at) + w / 2
        let cy: CGFloat = m.rowY(l.track) + 2 + h / 2
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.text, lineWidth: 1))
            .overlay(alignment: .leading) {
                Text(model.arrClipName(l.block.clip)).font(.system(size: 11, weight: .bold)).foregroundStyle(ArrColors.text)
                    .lineLimit(1).padding(.leading, 6)
            }
            .frame(width: w, height: h)
            .shadow(color: Color.black.opacity(0.5), radius: 8, y: 4)
            .position(x: cx, y: cy)
            .allowsHitTesting(false)
    }

    private func touch(_ size: CGSize) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { e in apply(e, size) }
            .onEnded { e in apply(e, size) }
    }

    private func apply(_ events: SpatialEventCollection, _ size: CGSize) {
        let p: Project = model.project
        let m = ArrMetrics(size: size, port: model.arrPort, tracks: p.tracks.count, end: p.arrangeEnd)
        var port: ArrPort = model.arrPort
        touches.handle(events, port: &port, m, model, lift: $lift)
        let c = ArrMetrics(size: size, port: port, tracks: p.tracks.count, end: p.arrangeEnd)
        let next = ArrPort(stepW: port.stepW == nil ? nil : c.stepW, x: c.x, rowH: c.rowH, y: c.y)
        if next != model.arrPort { model.arrPort = next }
    }
}

/// Рисование таймлайна.
struct ArrDraw {
    let ctx: GraphicsContext
    let m: ArrMetrics
    let theme: Theme

    func draw(_ p: Project, cursor: Int, sel: ArrSel?, lift: ArrLift?, following: [Bool], names: (Int) -> String) {
        lanes(p)
        gridLines(p)
        for t in 0..<p.tracks.count {
            let on: Bool = t < following.count ? following[t] : true
            let heard: Bool = p.audible(t)
            let dim: Bool = !on || !heard
            blocks(p, t, sel: sel, lift: lift, dim: dim, names: names)
        }
        if let l = lift { target(l) }
        ruler(p)
        markers(p)
        cursorLine(cursor)
    }

    private func lanes(_ p: Project) {
        for t in 0..<p.tracks.count {
            let y: CGFloat = m.rowY(t)
            if y > m.size.height || y + m.rowH < ArrMetrics.top { continue }
            let r = CGRect(x: 0, y: y + m.rowH - 1, width: m.size.width, height: 1)
            ctx.fill(Path(r), with: .color(theme.line))
        }
    }

    /// Линии тактов (ярче) и сетки (с выбранным шагом сетки, если не слишком тесно).
    private func gridLines(_ p: Project) {
        let first: Int = max(0, Int(m.step(at: 0)))
        let last: Int = Int(m.step(at: m.size.width)) + 1
        let g: Int = p.arrange.gridSteps
        let fine: Bool = CGFloat(g) * m.stepW >= 8
        var s: Int = first - first % max(1, g)
        let h: CGFloat = m.size.height - ArrMetrics.top
        while s <= last {
            let bar: Bool = s % ArrMetrics.stepsPerBar == 0
            if bar || fine {
                let x: CGFloat = m.stepX(Double(s))
                let c: Color = bar ? theme.gridStrong : theme.grid
                ctx.fill(Path(CGRect(x: x, y: ArrMetrics.top, width: 1, height: h)), with: .color(c))
            }
            s += max(1, g)
        }
    }

    private func blocks(_ p: Project, _ t: Int, sel: ArrSel?, lift: ArrLift?, dim: Bool, names: (Int) -> String) {
        let tr: Track = p.tracks[t]
        let y: CGFloat = m.rowY(t)
        if y > m.size.height || y + m.rowH < ArrMetrics.top { return }
        let color: Color = ArrColors.color(tr.color)
        for (i, b) in tr.blocks.enumerated() {
            if let l = lift, l.track == t, l.index == i { continue }
            let r: CGRect = m.rect(t, b)
            if r.maxX < 0 || r.minX > m.size.width { continue }
            let shape = Path(roundedRect: r, cornerRadius: 4)
            ctx.fill(shape, with: .color(color.opacity(dim ? 0.35 : 1)))
            if sel == ArrSel(track: t, block: i) { ctx.stroke(shape, with: .color(theme.text), lineWidth: 1) }
            label(names(b.clip), r)
        }
    }

    private func label(_ s: String, _ r: CGRect) {
        if r.width < 18 { return }
        var c = ctx
        c.clip(to: Path(r.insetBy(dx: 4, dy: 0)))
        let text = Text(s).font(.system(size: 11, weight: .bold)).foregroundStyle(ArrColors.text)
        let x: CGFloat = max(r.minX, 0) + 6
        let y: CGFloat = r.minY + 4
        c.draw(text, at: CGPoint(x: x, y: y), anchor: .topLeading)
    }

    /// Куда встанет поднятый блок — контур.
    private func target(_ l: ArrLift) {
        let b = ArrBlock(clip: l.block.clip, start: l.target, length: l.block.length)
        ctx.stroke(Path(roundedRect: m.rect(l.track, b), cornerRadius: 4), with: .color(theme.text.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    /// Линейка: номера тактов, планка петли (жёлтая; выключенная петля — бледная).
    private func ruler(_ p: Project) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: m.size.width, height: ArrMetrics.top)), with: .color(theme.panel2))
        let every: Int = m.barLabelEvery
        let firstBar: Int = max(0, Int(m.step(at: 0)) / ArrMetrics.stepsPerBar)
        let lastBar: Int = Int(m.step(at: m.size.width)) / ArrMetrics.stepsPerBar + 1
        var bar: Int = firstBar - firstBar % every
        while bar <= lastBar {
            let x: CGFloat = m.stepX(Double(bar * ArrMetrics.stepsPerBar))
            ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: ArrMetrics.rulerH)), with: .color(theme.gridStrong))
            let text = Text("\(bar + 1)").font(.system(size: 9)).monospacedDigit().foregroundStyle(theme.dim)
            ctx.draw(text, at: CGPoint(x: x + 3, y: 3), anchor: .topLeading)
            bar += every
        }
        let a = p.arrange
        if a.hasLoop {
            let x0: CGFloat = m.stepX(Double(a.loopFrom))
            let x1: CGFloat = m.stepX(Double(a.loopTo))
            let r = CGRect(x: x0, y: ArrMetrics.rulerH - 5, width: max(2, x1 - x0), height: 4)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(theme.accent.opacity(a.loop ? 1 : 0.35)))
        }
        ctx.fill(Path(CGRect(x: 0, y: ArrMetrics.top - 1, width: m.size.width, height: 1)), with: .color(theme.line))
    }

    /// Строка маркеров: секция — от маркера до следующего, имя на цвете маркера.
    private func markers(_ p: Project) {
        let list: [ArrMarker] = p.arrange.markers
        for (k, mk) in list.enumerated() {
            let x0: CGFloat = m.stepX(Double(mk.at))
            var next: CGFloat = m.size.width
            if k + 1 < list.count { next = m.stepX(Double(list[k + 1].at)) }
            if next < 0 || x0 > m.size.width { continue }
            let r = CGRect(x: x0, y: ArrMetrics.rulerH + 2, width: max(2, next - x0 - 2), height: ArrMetrics.markerH - 4)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(ArrColors.color(mk.color)))
            var c = ctx
            c.clip(to: Path(r))
            let name: String = mk.name.isEmpty ? " " : mk.name
            let tx: CGFloat = max(r.minX, 0) + 4
            let text: Text = Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(ArrColors.text)
            c.draw(text, at: CGPoint(x: tx, y: r.midY), anchor: .leading)
        }
    }

    private func cursorLine(_ pos: Int) {
        let x: CGFloat = m.stepX(Double(pos))
        if x < -2 || x > m.size.width + 2 { return }
        ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: m.size.height)), with: .color(theme.accent))
    }
}
