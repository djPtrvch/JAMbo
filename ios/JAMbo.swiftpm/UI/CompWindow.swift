import SwiftUI

/// Дисплей окна компрессора (решение пользователя: один дисплей с волной): WAVE | блок COMP. WAVE — вход серым,
/// выход после MAKEUP жёлтым, GR оранжевым сверху, пунктир THRESHOLD (тянется пальцем), кривая TRANSFER — MasterWave.
struct CompDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    @Environment(\.theme) private var theme

    private var thrParam: ParamDef { return Params.masterColumns[1][0] }

    /// Кривая TRANSFER: выход без MAKEUP = вход − статическое GR.
    private var transfer: (Double) -> Double {
        let thr: Double = model.masterValue(thrParam)
        let ratio: Double = model.masterValue(Params.byId["cmp.ratio"] ?? thrParam)
        let knee: Double = model.project.master["cmp.knee"] ?? 6
        return { l in l - MasterGlue.staticGr(l, thr: thr, ratio: ratio, knee: knee) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: Layout.gap) {
                LevelPlot(model: model, tele: model.audio.core.master.compTele, hist: hist, line: thrParam,
                          now: now, wave: true) { ctx, size, c in
                    MasterWave.draw(ctx, size, c, out: theme.accent, bypass: model.project.cmpBypass,
                                    line: model.masterValue(thrParam), dashed: true, frozen: hist.frozen,
                                    curve: transfer, theme)
                }
                DynBlock(model: model, module: MasterScope.comp, now: now)
                    .frame(width: 96)
            }
        }
    }
}
