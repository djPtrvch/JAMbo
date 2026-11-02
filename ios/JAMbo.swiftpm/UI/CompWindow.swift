import SwiftUI

/// Дисплей окна компрессора (comp.ts веба; решение пользователя: без TRANSFER): LEVEL | блок COMP. Шкала по высоте
/// 0…−48 dB, пунктир порога тянется пальцем.
struct CompDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    @Environment(\.theme) private var theme

    private var thrParam: ParamDef { return Params.masterColumns[1][0] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: Layout.gap) {
                LevelPlot(model: model, tele: model.audio.core.master.compTele, hist: hist, line: thrParam,
                          now: now) { ctx, size, c in drawLevel(ctx, size, c, now) }
                DynBlock(model: model, module: MasterScope.comp, now: now)
                    .frame(width: 96)
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

