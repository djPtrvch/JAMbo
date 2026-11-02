import SwiftUI

/// Дисплей окна клиппера (решение пользователя: один дисплей с волной): WAVE | блок CLIP. WAVE — вход после INPUT
/// серым, выход оранжевым, GR оранжевым сверху, линия CEILING (тянется пальцем), кривая TRANSFER — MasterWave.
struct ClipDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    @Environment(\.theme) private var theme

    private var ceilingParam: ParamDef { return Params.masterColumns[2][1] }

    /// Кривая TRANSFER: по горизонтали источник до INPUT, по вертикали выход клиппера.
    private var transfer: (Double) -> Double {
        let input: Double = model.masterValue(Params.masterColumns[2][0])
        let ceil: Double = model.masterValue(ceilingParam)
        let soft: Double = model.masterValue(Params.masterColumns[2][2])
        return { x in MasterClipper.staticOut(x, input: input, ceiling: ceil, softness: soft) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: Layout.gap) {
                LevelPlot(model: model, tele: model.audio.core.master.clipTele, hist: hist, line: ceilingParam,
                          now: now, wave: true) { ctx, size, c in
                    MasterWave.draw(ctx, size, c, out: theme.gr, bypass: model.project.clipBypass,
                                    line: model.masterValue(ceilingParam), dashed: false, frozen: hist.frozen,
                                    curve: transfer, theme)
                }
                DynBlock(model: model, module: MasterScope.clip, now: now)
                    .frame(width: 96)
            }
        }
    }
}
