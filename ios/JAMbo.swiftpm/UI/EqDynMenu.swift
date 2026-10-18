import SwiftUI

/// Меню DYN (тап по полю DYN, как в вебе): источник — OFF, SELF или дорожка (сетка в два столбца, прокрутка пальцем),
/// под ним THRESHOLD и RANGE — поля как в строке EQ (палец вверх-вниз — 3 px на 0,5 dB, удержание — ввод числом).
/// Под полем DYN; тап мимо — закрыть.
struct EqDynMenu: View {
    static let width: CGFloat = 300
    static let rowH: CGFloat = 44
    static let gap: CGFloat = 4
    static let listMax: CGFloat = 240
    let model: AppModel
    let anchor: CGRect
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.eqDynMenu = nil }
            VStack(alignment: .leading, spacing: 6) {
                Text("DYNAMIC · SOURCE").font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(theme.text)
                list
                fields.frame(height: 52)
            }
            .padding(8)
            .frame(width: EqDynMenu.width)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .offset(x: anchor.minX, y: anchor.maxY + 4)
        }
    }

    /// Пункты: (подпись, источник).
    private var items: [(String, Int)] {
        var out: [(String, Int)] = [("OFF", -1), ("SELF", 0)]
        for (i, t) in model.project.tracks.enumerated() { out.append((t.name, i + 1)) }
        return out
    }

    private var list: some View {
        let all: [(String, Int)] = items
        let rows: Int = (all.count + 1) / 2
        let need: CGFloat = CGFloat(rows) * EqDynMenu.rowH + CGFloat(rows - 1) * EqDynMenu.gap
        let b: EqBand? = model.selectedBand
        let k: Int = model.eqBand
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: EqDynMenu.gap), count: 2)
        return MenuScroll {
            LazyVGrid(columns: cols, spacing: EqDynMenu.gap) {
                ForEach(0..<all.count, id: \.self) { i in
                    let v: Int = all[i].1
                    MenuItem(title: all[i].0, current: EqDynMenu.current(b, v)) { model.setEqDyn(k, v) }
                        .frame(height: EqDynMenu.rowH)
                }
            }
        }
        .frame(height: min(EqDynMenu.listMax, need))
    }

    /// Пункт выбран: источник полосы (OFF — и когда полоса не динамическая).
    static func current(_ b: EqBand?, _ v: Int) -> Bool {
        guard let b = b else { return false }
        if v < 0 { return !EqSpec.dynOn(b) }
        return EqSpec.dynOn(b) && b.dyn == v
    }

    private var fields: some View {
        let b: EqBand? = model.selectedBand
        let k: Int = model.eqBand
        let thr: Double = b?.thr ?? EqSpec.dynThrDef
        let range: Double = b?.range ?? EqSpec.dynRangeDef
        return HStack(spacing: 6) {
            EqField(label: "THRESHOLD", value: String(format: "%.1f dB", thr), enabled: b != nil, pxPerUnit: 3,
                    get: { ((model.selectedBand?.thr ?? EqSpec.dynThrDef) * 2).rounded() },
                    set: { v in model.setEqDynParams(k, thr: v / 2) },
                    hold: { model.eqInputAsk = .thr }, model: model)
            EqField(label: "RANGE", value: EqFormat.gain(range), enabled: b != nil, pxPerUnit: 3,
                    get: { ((model.selectedBand?.range ?? EqSpec.dynRangeDef) * 2).rounded() },
                    set: { v in model.setEqDynParams(k, range: v / 2) },
                    hold: { model.eqInputAsk = .range }, model: model)
        }
    }
}
