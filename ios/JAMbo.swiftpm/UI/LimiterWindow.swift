import SwiftUI

/// Дисплей окна лимитера (limiter.ts веба): пик в dB за 4 с (справа новое), 60 кадров в секунду; справа блок LIM.
/// Слои: сетка; вход после INPUT — серая заливка с тонким контуром (выше 0 dBFS — светлая метка у кромки); выход —
/// красный контур и заливка ~20 %; GR — оранжевая заливка сверху; линия CEILING с числом — тянется пальцем (±22 px,
/// приоритет над FREEZE); подписи пиков GR; красная точка — выход выше CEILING больше чем на 0,1 dB. Тап — FREEZE.
struct LimiterDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    @Environment(\.theme) private var theme

    private var ceilingParam: ParamDef { return Params.masterColumns[3][1] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: Layout.gap) {
                LevelPlot(model: model, tele: model.audio.core.master.limTele, hist: hist, line: ceilingParam, now: now) {
                    ctx, size, c in draw(ctx, size, c)
                }
                DynBlock(model: model, module: MasterScope.lim, now: now)
                    .frame(width: 96)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ c: TeleHistory.Columns) {
        let h: CGFloat = size.height
        MasterDraw.grid(ctx, size, theme)
        let bypass: Bool = model.project.limBypass
        // Вход после INPUT: серая заливка с тонким контуром; выше 0 dBFS — светлая метка у верхней кромки.
        ctx.fill(MasterDraw.levelPath(c.inDb, h, closed: true), with: .color(theme.dim.opacity(0.35)))
        ctx.stroke(MasterDraw.levelPath(c.inDb, h, closed: false), with: .color(theme.dim), lineWidth: 1)
        MasterDraw.overMarks(ctx, c.inDb, theme)
        if !bypass {
            // Выход — красный контур и заливка ~20 %; GR — оранжевая заливка сверху вниз.
            ctx.fill(MasterDraw.levelPath(c.outDb, h, closed: true), with: .color(theme.rec.opacity(0.2)))
            ctx.stroke(MasterDraw.levelPath(c.outDb, h, closed: false), with: .color(theme.rec), lineWidth: 1.5)
            ctx.fill(MasterDraw.grPath(c.gr, h), with: .color(theme.gr))
        }
        let ceil: Double = model.masterValue(ceilingParam)
        MasterDraw.line(ctx, ceil, size, theme)
        if !bypass {
            MasterDraw.grPeaks(ctx, c.gr, size, gapMs: 80, theme)
            overDots(ctx, c.outDb, ceil)
        }
        if hist.frozen { MasterDraw.pauseLabel(ctx, "FREEZE", theme) }
    }

    /// Выход выше CEILING больше чем на 0,1 dB — красная точка у верхней кромки.
    private func overDots(_ ctx: GraphicsContext, _ outDb: [Float], _ ceil: Double) {
        let lim: Float = Float(ceil + 0.1)
        var x: Int = 0
        while x < outDb.count {
            if outDb[x] > lim {
                let r = CGRect(x: CGFloat(x) - 3, y: 1, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: r), with: .color(theme.rec))
            }
            x += 1
        }
    }
}
