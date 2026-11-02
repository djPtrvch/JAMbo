import SwiftUI

/// Дисплей окна компрессора (решение пользователя: один дисплей с волной): WAVE | блок COMP. WAVE — вход серым,
/// выход после MAKEUP жёлтым, GR оранжевым сверху, пунктир THRESHOLD (тянется пальцем) — MasterWave.
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
                          now: now, wave: true) { ctx, size, c in
                    MasterWave.draw(ctx, size, c, out: theme.accent, bypass: model.project.cmpBypass,
                                    line: model.masterValue(thrParam), dashed: true, frozen: hist.frozen, theme)
                }
                DynBlock(model: model, module: MasterScope.comp, now: now)
                    .frame(width: 96)
            }
        }
    }
}
