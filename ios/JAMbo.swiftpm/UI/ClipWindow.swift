import SwiftUI

/// Дисплей окна клиппера (решение пользователя: один дисплей с волной): WAVE | блок CLIP. WAVE — вход после INPUT
/// серым, выход оранжевым, GR оранжевым сверху, линия CEILING (тянется пальцем) — MasterWave.
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
                          now: now, wave: true) { ctx, size, c in
                    MasterWave.draw(ctx, size, c, out: theme.gr, bypass: model.project.clipBypass,
                                    line: model.masterValue(ceilingParam), dashed: false, frozen: hist.frozen, theme)
                }
                DynBlock(model: model, module: MasterScope.clip, now: now)
                    .frame(width: 96)
            }
        }
    }
}
