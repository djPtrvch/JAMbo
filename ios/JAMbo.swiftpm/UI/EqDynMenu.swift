import SwiftUI

/// Меню DYN (тап по полю DYN, как в вебе): источник — OFF, SELF или дорожка (сетка в два столбца, прокрутка пальцем),
/// под ним THRESHOLD и RANGE — поля как в строке EQ (палец вверх-вниз — 3 px на 0,5 dB, двойной тап — ввод числом).
/// Под полем DYN; окно перетаскивается пальцем за заголовок; тап мимо — закрыть.
struct EqDynMenu: View {
    static let width: CGFloat = 300
    static let rowH: CGFloat = 44
    static let gap: CGFloat = 4
    static let listMax: CGFloat = 240
    let model: AppModel
    let anchor: CGRect
    /// Сдвиг пальцем в текущем жесте (после жеста прибавляется к model.eqDynShift).
    @State private var drag: CGSize = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        let dx: CGFloat = model.eqDynShift.width + drag.width
        let dy: CGFloat = model.eqDynShift.height + drag.height
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.eqDynMenu = nil }
            VStack(alignment: .leading, spacing: 6) {
                head
                list
                fields.frame(height: 52)
            }
            .padding(8)
            .frame(width: EqDynMenu.width)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .offset(x: anchor.minX + dx, y: anchor.maxY + 4 + dy)
        }
    }

    /// Заголовок — ручка перетаскивания окна (полоски справа), высота 28 для пальца.
    private var head: some View {
        HStack(spacing: 0) {
            Text("DYNAMIC · SOURCE").font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(theme.text)
            Spacer(minLength: 8)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1).fill(theme.dim).frame(width: 18, height: 2)
                }
            }
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(move)
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("root"))
            .onChanged { g in drag = g.translation }
            .onEnded { g in
                let w: CGFloat = model.eqDynShift.width + g.translation.width
                let h: CGFloat = model.eqDynShift.height + g.translation.height
                model.eqDynShift = CGSize(width: w, height: h)
                drag = .zero
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
                    double: { model.eqInputAsk = .thr }, model: model)
            EqField(label: "RANGE", value: EqFormat.gain(range), enabled: b != nil, pxPerUnit: 3,
                    get: { ((model.selectedBand?.range ?? EqSpec.dynRangeDef) * 2).rounded() },
                    set: { v in model.setEqDynParams(k, range: v / 2) },
                    double: { model.eqInputAsk = .range }, model: model)
        }
    }
}
