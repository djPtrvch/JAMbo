import SwiftUI

/// Дисплей окна клиппера (clipper.ts веба, вид LEVEL; решение пользователя: один дисплей, без WAVE и кнопки VIEW):
/// TRANSFER (не шире 40 %) | LEVEL | блок CLIP. Шкала обоих — 0…−48 dB (у TRANSFER в вебе −30…0): сетка и линия
/// CEILING на одной высоте, как у компрессора.
struct ClipDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    @Environment(\.theme) private var theme

    private var ceilingParam: ParamDef { return Params.masterColumns[2][1] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w: CGFloat = min(geo.size.width * 0.4, geo.size.height * 1.4)
                HStack(spacing: Layout.gap) {
                    ClipTransfer(model: model, hist: hist, now: now).frame(width: w)
                    LevelPlot(model: model, tele: model.audio.core.master.clipTele, hist: hist, line: ceilingParam,
                              now: now) { ctx, size, c in drawLevel(ctx, size, c, now) }
                    DynBlock(model: model, module: MasterScope.clip, now: now)
                        .frame(width: 96)
                }
            }
        }
    }

    /// LEVEL: вход после INPUT — серая заливка с контуром; выход — оранжевый контур 1,5 px и заливка ~15 %; GR —
    /// оранжевая заливка ~25 % от верхней кромки (без линии), подписи пиков; белая линия CEILING с числом.
    private func drawLevel(_ ctx: GraphicsContext, _ size: CGSize, _ c: TeleHistory.Columns, _ now: Double) {
        let h: CGFloat = size.height
        MasterDraw.grid(ctx, size, theme)
        ctx.fill(MasterDraw.levelPath(c.inDb, h, closed: true), with: .color(theme.dim.opacity(0.35)))
        ctx.stroke(MasterDraw.levelPath(c.inDb, h, closed: false), with: .color(theme.dim), lineWidth: 1)
        ctx.fill(MasterDraw.levelPath(c.outDb, h, closed: true), with: .color(theme.gr.opacity(0.15)))
        ctx.stroke(MasterDraw.levelPath(c.outDb, h, closed: false), with: .color(theme.gr), lineWidth: 1.5)
        if !model.project.clipBypass {
            ctx.fill(MasterDraw.grPath(c.gr, h), with: .color(theme.gr.opacity(0.25)))
            MasterDraw.grPeaks(ctx, c.gr, size, gapMs: 100, theme)
        }
        let hot: Bool = model.masterHotNow(ceilingParam.id, now: now)
        MasterDraw.line(ctx, model.masterValue(ceilingParam), size, theme, hot: hot)
        MasterDraw.title(ctx, "LEVEL", size, theme)
        if hist.frozen { MasterDraw.pauseLabel(ctx, "FREEZE", theme) }
    }
}

/// TRANSFER клиппера: по горизонтали источник до INPUT, по вертикали выход клиппера (обе оси −48…0 dB); сетка через
/// 6 dB по обеим осям, диагональ 1:1, серая полоса колена от x_k = x_c + 20·log10(k) до угла x_c = CEILING − INPUT,
/// кривая (белая, 1,5 px), пунктир CEILING; живая точка — пик последнего кадра после INPUT минус INPUT, на кривой;
/// при срезе участок от колена до точки — оранжевый. Ручка-угол (28 px) в (x_c, CEILING): палец — CEILING = y,
/// INPUT = CEILING − x (шаг 0,1, в пределах диапазонов); SOFTNESS пальцем не меняется — только полем и ручкой 3.3.
struct ClipTransfer: View {
    static let handle: CGFloat = 28
    let model: AppModel
    let hist: TeleHistory
    let now: Double
    @State private var dragging: Int = -1
    @Environment(\.theme) private var theme

    private var inputP: ParamDef { return Params.masterColumns[2][0] }
    private var ceilP: ParamDef { return Params.masterColumns[2][1] }
    private var softP: ParamDef { return Params.masterColumns[2][2] }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx, size) }
                .contentShape(Rectangle())
                .gesture(drag(geo.size))
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private var curve: (input: Double, ceil: Double, soft: Double) {
        return (model.masterValue(inputP), model.masterValue(ceilP), model.masterValue(softP))
    }

    private func out(_ x: Double) -> Double {
        let c = curve
        return MasterClipper.staticOut(x, input: c.input, ceiling: c.ceil, softness: c.soft)
    }

    private func cornerPoint(_ size: CGSize) -> CGPoint {
        let c = curve
        return CGPoint(x: CompTransfer.x(c.ceil - c.input, size.width), y: MasterDraw.y(c.ceil, size.height))
    }

    // MARK: — касания

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragging < 0 {
                    let cp: CGPoint = cornerPoint(size)
                    let d: CGFloat = hypot(g.startLocation.x - cp.x, g.startLocation.y - cp.y)
                    dragging = d <= MasterDraw.lineHit ? 1 : 0
                    if dragging == 1 {
                        model.beginGesture()
                        model.masterHot.hold(inputP.id)
                        model.masterHot.hold(ceilP.id)
                    }
                }
                if dragging != 1 { return }
                let sc: Double = Double(MasterDraw.scale)
                let x: Double = -sc + Double(g.location.x / max(1, size.width)) * sc
                let y: Double = -Double(g.location.y / max(1, size.height)) * sc
                let ceil: Double = MasterInput.clamp(ceilP, y)
                model.setMaster(ceilP, ceil)
                model.setMaster(inputP, ceil - x)
            }
            .onEnded { _ in
                if dragging == 1 {
                    model.masterHot.release(inputP.id)
                    model.masterHot.release(ceilP.id)
                    model.endGesture()
                }
                dragging = -1
            }
    }

    // MARK: — рисование

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let c = curve
        let bypass: Bool = model.project.clipBypass
        MasterDraw.grid(ctx, size, theme)
        var db: Int = -MasterDraw.gridStep
        while CGFloat(-db) < MasterDraw.scale {
            let x: CGFloat = CompTransfer.x(Double(db), w).rounded()
            ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: h)), with: .color(theme.line))
            db -= MasterDraw.gridStep
        }
        // Колено: от x_k до угла x_c.
        let xc: Double = c.ceil - c.input
        let k: Double = 1 - 0.6 * (c.soft / 100)
        let xk: Double = xc + 20 * log10(k)
        let a: CGFloat = CompTransfer.x(xk, w)
        let b: CGFloat = CompTransfer.x(xc, w)
        ctx.fill(Path(CGRect(x: a, y: 0, width: b - a, height: h)), with: .color(theme.dim.opacity(0.35)))
        var diag = Path()
        diag.move(to: CGPoint(x: 0, y: h))
        diag.addLine(to: CGPoint(x: w, y: 0))
        ctx.stroke(diag, with: .color(theme.dim), lineWidth: 1)
        ctx.stroke(curvePath(w, h, from: 0, to: Int(w)), with: .color(bypass ? theme.dim : theme.text), lineWidth: 1.5)
        let ceilHot: Bool = model.masterHotNow(ceilP.id, now: now)
        let ty: CGFloat = MasterDraw.y(c.ceil, h)
        MasterDraw.dashed(ctx, CGPoint(x: 0, y: ty), CGPoint(x: w, y: ty), hot: ceilHot, theme)
        if !bypass { drawLive(ctx, size, xk) }
        let inHot: Bool = model.masterHotNow(inputP.id, now: now)
        drawCorner(ctx, size, hot: ceilHot || inHot)
        MasterDraw.title(ctx, "TRANSFER", size, theme)
    }

    /// Кривая на столбцах a…b.
    private func curvePath(_ w: CGFloat, _ h: CGFloat, from a: Int, to b: Int) -> Path {
        var p = Path()
        var x: Int = a
        while x <= b {
            let l: Double = Double(-MasterDraw.scale + CGFloat(x) / max(1, w) * MasterDraw.scale)
            let pt = CGPoint(x: CGFloat(x), y: MasterDraw.y(out(l), h))
            if x == a { p.move(to: pt) } else { p.addLine(to: pt) }
            x += 1
        }
        return p
    }

    /// Живая точка и оранжевый участок среза — по последнему кадру клиппера.
    private func drawLive(_ ctx: GraphicsContext, _ size: CGSize, _ xk: Double) {
        guard let f = hist.latest(model.audio.core.master.clipTele, now: now), f.inPeak > 0 else { return }
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let x: Double = 20 * log10(Double(f.inPeak)) - curve.input
        if x <= -Double(MasterDraw.scale) { return }
        if f.gr > 0.05 && x > xk {
            let a: Int = max(0, Int(CompTransfer.x(xk, w)))
            let b: Int = min(Int(w), Int(CompTransfer.x(x, w).rounded(.up)))
            if b > a { ctx.stroke(curvePath(w, h, from: a, to: b), with: .color(theme.gr), lineWidth: 2.5) }
        }
        let x0: Double = min(0, x)
        let px: CGFloat = CompTransfer.x(x0, w)
        let py: CGFloat = MasterDraw.y(out(x0), h)
        ctx.fill(Path(ellipseIn: CGRect(x: px - 3, y: py - 3, width: 6, height: 6)), with: .color(theme.text))
    }

    /// Ручка-угол: кружок 28 px с точкой в центре (жёлтый, пока INPUT или CEILING меняют).
    private func drawCorner(_ ctx: GraphicsContext, _ size: CGSize, hot: Bool) {
        let cp: CGPoint = cornerPoint(size)
        let rr: CGFloat = ClipTransfer.handle / 2 - 1
        let circle = Path(ellipseIn: CGRect(x: cp.x - rr, y: cp.y - rr, width: 2 * rr, height: 2 * rr))
        let col: Color = hot ? theme.accent : theme.text
        ctx.fill(circle, with: .color(theme.panel))
        ctx.stroke(circle, with: .color(col), lineWidth: 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: cp.x - 3, y: cp.y - 3, width: 6, height: 6)), with: .color(col))
    }
}
