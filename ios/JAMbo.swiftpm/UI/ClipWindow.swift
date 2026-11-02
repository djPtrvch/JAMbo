import SwiftUI

/// Дисплей окна клиппера (clipper.ts веба, вид LEVEL; решение пользователя: один дисплей, без WAVE и кнопки VIEW,
/// без TRANSFER): LEVEL | блок CLIP. Шкала — 0…−48 dB, сетка через 6 dB.
struct ClipDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    @Environment(\.theme) private var theme

    private var ceilingParam: ParamDef { return Params.masterColumns[2][1] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: Layout.gap) {
                LevelPlot(model: model, tele: model.audio.core.master.clipTele, hist: hist, line: ceilingParam,
                          now: now) { ctx, size, c in drawLevel(ctx, size, c, now) }
                DynBlock(model: model, module: MasterScope.clip, now: now)
                    .frame(width: 96)
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
        MasterDraw.line(ctx, model.masterValue(ceilingParam), size, theme)
        MasterDraw.title(ctx, "LEVEL", size, theme)
        if hist.frozen { MasterDraw.pauseLabel(ctx, "FREEZE", theme) }
    }
}

