import SwiftUI

/// Дисплей окна компрессора (comp.ts веба): TRANSFER (не шире 40 %) | LEVEL | блок COMP. У TRANSFER и LEVEL одна
/// шкала по высоте (0…−48 dB), линии сетки и пунктир порога — на одной высоте.
struct CompDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    @Environment(\.theme) private var theme

    private var thrParam: ParamDef { return Params.masterColumns[1][0] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w: CGFloat = min(geo.size.width * 0.4, geo.size.height * 1.4)
                HStack(spacing: Layout.gap) {
                    CompTransfer(model: model, hist: hist, now: now).frame(width: w)
                    LevelPlot(model: model, tele: model.audio.core.master.compTele, hist: hist, line: thrParam,
                              now: now) { ctx, size, c in drawLevel(ctx, size, c, now) }
                    DynBlock(model: model, module: MasterScope.comp, now: now)
                        .frame(width: 96)
                }
            }
        }
    }

    /// LEVEL: вход до компрессора — серая заливка с контуром; выход после MAKEUP — жёлтый контур 1,5 px и заливка
    /// ~15 %; GR — оранжевая линия с лёгкой заливкой от верхней кромки, подписи пиков; пунктир THRESHOLD с числом.
    private func drawLevel(_ ctx: GraphicsContext, _ size: CGSize, _ c: TeleHistory.Columns, _ now: Double) {
        let h: CGFloat = size.height
        MasterDraw.grid(ctx, size, theme)
        ctx.fill(MasterDraw.levelPath(c.inDb, h, closed: true), with: .color(theme.dim.opacity(0.35)))
        ctx.stroke(MasterDraw.levelPath(c.inDb, h, closed: false), with: .color(theme.dim), lineWidth: 1)
        ctx.fill(MasterDraw.levelPath(c.outDb, h, closed: true), with: .color(theme.accent.opacity(0.15)))
        ctx.stroke(MasterDraw.levelPath(c.outDb, h, closed: false), with: .color(theme.accent), lineWidth: 1.5)
        if !model.project.cmpBypass {
            ctx.fill(MasterDraw.grPath(c.gr, h), with: .color(theme.gr.opacity(0.18)))
            ctx.stroke(CompDisplay.grLine(c.gr, h), with: .color(theme.gr), lineWidth: 1.5)
            MasterDraw.grPeaks(ctx, c.gr, size, gapMs: 100, theme)
        }
        let thr: Double = model.masterValue(thrParam)
        let ty: CGFloat = MasterDraw.y(thr, h)
        MasterDraw.dashed(ctx, CGPoint(x: 0, y: ty), CGPoint(x: size.width, y: ty), theme)
        let col: Color = theme.meterThr
        let t = ctx.resolve(Text(String(format: "%.1f", thr)).font(.system(size: 11)).foregroundColor(col))
        let below: Bool = ty <= 16
        ctx.draw(t, at: CGPoint(x: size.width - 6, y: below ? ty + 3 : ty - 3), anchor: below ? .topTrailing : .bottomTrailing)
        MasterDraw.title(ctx, "LEVEL", size, theme)
        if hist.frozen { MasterDraw.pauseLabel(ctx, "FREEZE", theme) }
    }

    /// Линия GR по столбцам (сверху вниз).
    static func grLine(_ gr: [Float], _ h: CGFloat) -> Path {
        var p = Path()
        var x: Int = 0
        while x < gr.count {
            let y: CGFloat = min(h, CGFloat(gr[x]) / MasterDraw.scale * h)
            let pt = CGPoint(x: CGFloat(x), y: y)
            if x == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            x += 1
        }
        return p
    }
}

/// TRANSFER компрессора: по горизонтали вход (−48…0 dB), по вертикали выход без MAKEUP; сетка, полоса колена,
/// диагональ 1:1, кривая (белая, 1,5 px), пунктир порога; точка порога тянется вдоль диагонали; кружок RATIO (28 px)
/// на правом краю — вертикально, ratio = (0 − THRESHOLD) / (выход − THRESHOLD); живая точка — уровень детектора
/// последнего кадра; при компрессии участок кривой от колена до текущего GR — оранжевый.
struct CompTransfer: View {
    static let handle: CGFloat = 28
    let model: AppModel
    let hist: TeleHistory
    let now: Double
    /// Что тянет палец: 1 — порог, 2 — RATIO, 0 — ничего; значение и положение в начале.
    @State private var kind: Int = -1
    @State private var start: Double = 0
    @Environment(\.theme) private var theme

    private var thrP: ParamDef { return Params.masterColumns[1][0] }
    private var ratioP: ParamDef { return Params.byId["cmp.ratio"] ?? Params.masterColumns[1][0] }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx, size) }
                .contentShape(Rectangle())
                .gesture(drag(geo.size))
                .modifier(GestureCancelGuard {
                    if kind > 0 { model.endGesture() }
                    kind = -1
                })
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    // MARK: — шкалы

    static func x(_ db: Double, _ w: CGFloat) -> CGFloat {
        let v: CGFloat = (1 + CGFloat(db) / MasterDraw.scale) * w
        return min(w, max(0, v))
    }

    private var curve: (thr: Double, ratio: Double, knee: Double) {
        let thr: Double = model.masterValue(thrP)
        let ratio: Double = model.masterValue(ratioP)
        let knee: Double = model.project.master["cmp.knee"] ?? 6
        return (thr, ratio, knee)
    }

    private func gr(_ l: Double) -> Double {
        let c = curve
        return MasterGlue.staticGr(l, thr: c.thr, ratio: c.ratio, knee: c.knee)
    }

    /// Кружок RATIO: на правом краю, на высоте выхода при входе 0 dB (без колена).
    private func handlePoint(_ size: CGSize) -> CGPoint {
        let c = curve
        let out0: Double = c.thr + (0 - c.thr) / max(1, c.ratio)
        let x: CGFloat = size.width - CompTransfer.handle / 2 - 2
        return CGPoint(x: x, y: MasterDraw.y(out0, size.height))
    }

    // MARK: — касания

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if kind < 0 { begin(g.startLocation, size) }
                if kind == 1 {
                    // Вдоль диагонали: значение — по горизонтали или вертикали (что больше).
                    let dx: Double = Double(g.translation.width / max(1, size.width) * MasterDraw.scale)
                    let dy: Double = Double(-g.translation.height / max(1, size.height) * MasterDraw.scale)
                    let d: Double = abs(dx) >= abs(dy) ? dx : dy
                    model.setMaster(thrP, start + d)
                } else if kind == 2 {
                    let thr: Double = model.masterValue(thrP)
                    if -thr < 0.5 { return }
                    let y: Double = start + Double(g.translation.height)
                    let out0: Double = min(0, -(y / Double(max(1, size.height))) * Double(MasterDraw.scale))
                    model.setMaster(ratioP, -thr / max(1e-3, out0 - thr))
                }
            }
            .onEnded { _ in
                if kind > 0 { model.endGesture() }
                kind = -1
            }
    }

    private func begin(_ p: CGPoint, _ size: CGSize) {
        let hp: CGPoint = handlePoint(size)
        let thr: Double = model.masterValue(thrP)
        let tp = CGPoint(x: CompTransfer.x(thr, size.width), y: MasterDraw.y(thr, size.height))
        let dh: CGFloat = hypot(p.x - hp.x, p.y - hp.y)
        let dt: CGFloat = hypot(p.x - tp.x, p.y - tp.y)
        if dh <= MasterDraw.lineHit {
            kind = 2
            start = Double(hp.y)
        } else if dt <= MasterDraw.lineHit + 6 {
            kind = 1
            start = thr
        } else {
            kind = 0
            return
        }
        model.beginGesture()
    }

    // MARK: — рисование

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let c = curve
        let bypass: Bool = model.project.cmpBypass
        // Сетка: горизонтали — как у LEVEL, вертикали — те же деления по входу.
        MasterDraw.grid(ctx, size, theme)
        var db: Int = -MasterDraw.gridStep
        while CGFloat(-db) < MasterDraw.scale {
            let x: CGFloat = CompTransfer.x(Double(db), w).rounded()
            ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: h)), with: .color(theme.line))
            db -= MasterDraw.gridStep
        }
        // Колено: серая полоса шириной KNEE вокруг порога.
        if c.knee > 0 {
            let a: CGFloat = CompTransfer.x(c.thr - c.knee / 2, w)
            let b: CGFloat = CompTransfer.x(c.thr + c.knee / 2, w)
            ctx.fill(Path(CGRect(x: a, y: 0, width: b - a, height: h)), with: .color(theme.dim.opacity(0.35)))
        }
        var diag = Path()
        diag.move(to: CGPoint(x: 0, y: h))
        diag.addLine(to: CGPoint(x: w, y: 0))
        ctx.stroke(diag, with: .color(theme.dim), lineWidth: 1)
        ctx.stroke(curvePath(w, h, from: 0, to: Int(w)), with: .color(bypass ? theme.dim : theme.text), lineWidth: 1.5)
        drawLive(ctx, size, bypass)
        // Пунктир порога по вертикали и горизонтали, точка порога.
        let tx: CGFloat = CompTransfer.x(c.thr, w)
        let ty: CGFloat = MasterDraw.y(c.thr, h)
        MasterDraw.dashed(ctx, CGPoint(x: tx, y: 0), CGPoint(x: tx, y: h), theme)
        MasterDraw.dashed(ctx, CGPoint(x: 0, y: ty), CGPoint(x: w, y: ty), theme)
        let r: CGFloat = 5
        ctx.fill(Path(ellipseIn: CGRect(x: tx - r, y: ty - r, width: 2 * r, height: 2 * r)), with: .color(theme.meterThr))
        drawHandle(ctx, size, c.ratio)
        MasterDraw.title(ctx, "TRANSFER", size, theme)
    }

    /// Кривая передачи на столбцах a…b.
    private func curvePath(_ w: CGFloat, _ h: CGFloat, from a: Int, to b: Int) -> Path {
        var p = Path()
        var x: Int = a
        while x <= b {
            let l: Double = Double(-MasterDraw.scale + CGFloat(x) / max(1, w) * MasterDraw.scale)
            let pt = CGPoint(x: CGFloat(x), y: MasterDraw.y(l - gr(l), h))
            if x == a { p.move(to: pt) } else { p.addLine(to: pt) }
            x += 1
        }
        return p
    }

    /// Участок сжатия (оранжевый) и живая точка — по последнему кадру компрессора.
    private func drawLive(_ ctx: GraphicsContext, _ size: CGSize, _ bypass: Bool) {
        if bypass { return }
        guard let f = hist.latest(model.audio.core.master.compTele, now: now) else { return }
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let c = curve
        let grNow: Double = Double(f.gr)
        if grNow > 0.05 {
            let a: Int = max(0, Int(CompTransfer.x(c.thr - c.knee / 2, w)))
            var b: Int = a
            while CGFloat(b) < w {
                let l: Double = Double(-MasterDraw.scale + CGFloat(b) / max(1, w) * MasterDraw.scale)
                if gr(l) >= grNow { break }
                b += 1
            }
            ctx.stroke(curvePath(w, h, from: a, to: b), with: .color(theme.gr), lineWidth: 2.5)
        }
        let det: Double = Double(f.det)
        if det > -Double(MasterDraw.scale) {
            let x: CGFloat = CompTransfer.x(det, w)
            let y: CGFloat = MasterDraw.y(det - gr(det), h)
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(theme.text))
        }
    }

    /// Кружок RATIO с числом.
    private func drawHandle(_ ctx: GraphicsContext, _ size: CGSize, _ ratio: Double) {
        let hp: CGPoint = handlePoint(size)
        let rr: CGFloat = CompTransfer.handle / 2 - 1
        let circle = Path(ellipseIn: CGRect(x: hp.x - rr, y: hp.y - rr, width: 2 * rr, height: 2 * rr))
        let col: Color = theme.text
        ctx.fill(circle, with: .color(theme.panel))
        ctx.stroke(circle, with: .color(col), lineWidth: 1.5)
        let s: String = ratio < 9.95 ? String(format: "%.1f", ratio) : "\(Int(ratio.rounded()))"
        let t = ctx.resolve(Text(s).font(.system(size: 9)).foregroundColor(col))
        ctx.draw(t, at: hp, anchor: .center)
    }
}
