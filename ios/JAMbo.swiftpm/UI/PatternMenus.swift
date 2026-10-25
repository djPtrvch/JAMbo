import SwiftUI

/// Меню сетки паттернов: ячейки (copy, paste, delete), строки (имя, повторы, duplicate, copy, paste, delete),
/// бутерброд сетки (START FROM ROW, AT THE END, + ADDS, ▲ ▼ ARROWS). Тап мимо — закрыть.
struct PatternMenus: View {
    let model: AppModel
    let geometry: GridGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let m = model.cellMenu {
                dismiss { model.cellMenu = nil }
                CellMenu(model: model, state: m).offset(cellOffset(m.anchor))
            }
            if let k = model.rowMenu {
                dismiss { model.rowMenu = nil }
                RowMenu(model: model, row: k).frame(width: menuWidth).offset(rowOffset(k))
            }
            if model.gridMenuOpen {
                dismiss { model.gridMenuOpen = false }
                GridMenu(model: model)
                    .frame(width: gridMenuWidth, height: geometry.size.height)
                    .offset(x: gridMenuX, y: 0)
            }
        }
    }

    private func dismiss(_ close: @escaping () -> Void) -> some View {
        Color.black.opacity(0.001)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onTapGesture { close() }
    }

    /// Ширина двух столбцов дорожек (как два крайних паттерна), у правого края экрана.
    private var gridMenuWidth: CGFloat {
        return min(geometry.size.width, menuWidth)
    }

    /// Правый край меню бутерброда — по правому краю последнего столбца паттернов.
    private var gridMenuX: CGFloat {
        let last: Int = max(0, geometry.tracks - 1)
        let right: CGFloat = geometry.origin(col: last, row: 0).width + geometry.trackW
        return max(0, right - gridMenuWidth)
    }

    /// Меню строки и бутерброда — шириной два столбца дорожек с зазором между ними.
    private var menuWidth: CGFloat {
        return 2 * geometry.trackW + Layout.gap
    }

    /// Меню ячейки — под ней (не помещается — над ней).
    private func cellOffset(_ a: CGRect) -> CGSize {
        let w: CGFloat = 180
        let h: CGFloat = CellMenu.height
        let left: CGFloat = max(0, a.midX - w / 2)
        let x: CGFloat = min(left, geometry.size.width - w)
        let below: CGFloat = a.maxY + 6
        let above: CGFloat = max(0, a.minY - 6 - h)
        let fits: Bool = below + h < geometry.size.height
        return CGSize(width: x, height: fits ? below : above)
    }

    /// Меню строки — под ячейкой строки (не помещается — над ней), от колонки строк до первой дорожки.
    private func rowOffset(_ k: Int) -> CGSize {
        let w = model.gridWindow
        let r: Int = w.rows.firstIndex(where: { $0 == k }) ?? 0
        let pitch: CGFloat = geometry.rowH + PatternGrid.rowGap
        let top: CGFloat = CGFloat(r) * pitch
        let h: CGFloat = RowMenu.height
        let below: CGFloat = top + geometry.rowH + 6
        let above: CGFloat = max(0, top - 6 - h)
        let fits: Bool = below + h < geometry.size.height
        // Левый край — по левому краю первого столбца паттернов.
        let x: CGFloat = geometry.origin(col: 0, row: 0).width
        return CGSize(width: x, height: fits ? below : above)
    }
}

/// Оформление всплывающего меню.
struct MenuPanel: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}

/// Кнопка меню: неактивная — серая, DELETE — красная.
struct MenuItem: View {
    let title: String
    var enabled: Bool = true
    var red: Bool = false
    var current: Bool = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let fg: Color = !enabled ? theme.off : (current ? theme.onAccent : (red ? theme.rec : theme.text))
        return Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(current ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct CellMenu: View {
    /// 3 строки по 40, 2 зазора по 6, поля 16.
    static let height: CGFloat = 148
    let model: AppModel
    let state: CellMenuState

    var body: some View {
        let c = state.cell
        let t: Track = model.project.tracks[min(c.track, model.project.tracks.count - 1)]
        let filled: Bool = t.clipFilled(c.row)
        return VStack(spacing: 6) {
            MenuItem(title: "COPY", enabled: filled) { run { model.copyClip(c) } }
            MenuItem(title: "PASTE", enabled: model.clipClipboard != nil) { run { model.pasteClip(c) } }
            MenuItem(title: "DELETE", enabled: filled, red: true) { run { model.deleteClip(c) } }
        }
        .frame(width: 180)
        .modifier(MenuPanel())
    }

    private func run(_ f: () -> Void) {
        model.cellMenu = nil
        f()
    }
}

/// Меню строки: имя (до 12 знаков), REPEATS − n +, TO ARRANGE (END, CURSOR), DUPLICATE, COPY, PASTE, DELETE, OK.
struct RowMenu: View {
    /// Имя 44, REPEATS 44, TO ARRANGE 54 (подпись 12, зазор 2, кнопки 40), 3 строки по 40, 5 зазоров по 6, поля 16.
    static let height: CGFloat = 308
    let model: AppModel
    let row: Int
    @State private var name: String = ""
    @State private var reps: Int = 1
    @State private var loaded: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            TextField("name", text: $name)
                .font(.system(size: 16))
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
            repeatsRow
            arrangeRow
            HStack(spacing: 6) {
                MenuItem(title: "DUPLICATE", enabled: model.project.canAddRow) { act { model.duplicateRow(row) } }
                MenuItem(title: "COPY") { act { model.copyRow(row) } }
            }
            HStack(spacing: 6) {
                MenuItem(title: "PASTE", enabled: model.rowClipboard != nil) { act { model.pasteRow(row) } }
                MenuItem(title: "DELETE", red: true) { act { model.deleteRow(row) } }
            }
            MenuItem(title: "OK") { done() }
        }
        .frame(maxWidth: .infinity)
        .modifier(MenuPanel())
        .onAppear {
            if loaded { return }
            loaded = true
            name = model.project.scenes[row].name
            reps = model.project.scenes[row].repeats
        }
    }

    private var repeatsRow: some View {
        HStack(spacing: 6) {
            Text("REPEATS").font(.system(size: 10)).tracking(0.8).foregroundStyle(theme.dim).frame(maxWidth: .infinity, alignment: .leading)
            MenuItem(title: "−") { reps = max(1, reps - 1) }.frame(width: 44)
            Text("×\(reps)").font(.system(size: 17)).monospacedDigit().foregroundStyle(theme.text).frame(width: 44)
            MenuItem(title: "+") { reps = min(64, reps + 1) }.frame(width: 44)
        }
        .frame(height: 44)
    }

    /// TO ARRANGE (S15e): блоки строки — в конец аранжировки или с курсора (имя и повторы — из этого окна).
    private var arrangeRow: some View {
        let filled: Bool = model.project.rowFilled(row)
        return VStack(spacing: 2) {
            Text("TO ARRANGE").font(.system(size: 9)).foregroundStyle(theme.dim)
                .frame(maxWidth: .infinity, minHeight: 12, alignment: .leading)
            HStack(spacing: 6) {
                MenuItem(title: "END", enabled: filled) { toArrange(false) }
                MenuItem(title: "CURSOR", enabled: filled) { toArrange(true) }
            }
        }
    }

    private func toArrange(_ cursor: Bool) {
        model.rowMenu = nil
        model.rowToArrange(row, name: name, repeats: reps, atCursor: cursor)
    }

    private func done() {
        model.setScene(row, name: name, repeats: reps)
        model.rowMenu = nil
    }

    private func act(_ f: () -> Void) {
        model.rowMenu = nil
        f()
    }
}

/// Бутерброд сетки: строка старта, что в конце строк, что делает «+», режим стрелок.
struct GridMenu: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let p: Project = model.project
        let start: Int = min(p.arrStart, p.visibleRows - 1)
        return MenuScroll {
            VStack(alignment: .leading, spacing: 6) {
                title("START FROM ROW")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(0..<p.visibleRows, id: \.self) { k in
                        MenuItem(title: p.sceneName(k), current: k == start) { model.setArrangement(start: k) }
                    }
                }
                title("AT THE END")
                pair("STOP", p.arrEndStop, "LOOP", !p.arrEndStop) { model.setArrangement(endStop: $0) }
                title("+ ADDS")
                pair("NEW PATTERNS", !p.plusCopy, "COPY PLAYING", p.plusCopy) { model.setArrangement(plusCopy: !$0) }
                title("▲ ▼ ARROWS")
                pair("VIEW", !p.arrowSwitch, "SWITCH", p.arrowSwitch) { model.setArrangement(arrowSwitch: !$0) }
            }
            .padding(.trailing, 6)
        }
        .modifier(MenuPanel())
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(theme.text).padding(.top, 4)
    }

    /// Два пункта: выбор левого — pick(true), правого — pick(false).
    private func pair(_ a: String, _ aOn: Bool, _ b: String, _ bOn: Bool, pick: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 6) {
            MenuItem(title: a, current: aOn) { pick(true) }
            MenuItem(title: b, current: bOn) { pick(false) }
        }
    }
}

/// Прокрутка меню: содержимое не помещается — прокручивается пальцем, справа тонкая полупрозрачная полоса,
/// видна всегда, пока есть что прокручивать (системная видна только во время прокрутки). Для всех меню.
struct MenuScroll<Content: View>: View {
    let content: Content
    @State private var geo: ScrollGeometry? = nil
    @Environment(\.theme) private var theme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) { content }
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, g in geo = g }
            .overlay(alignment: .topTrailing) { bar }
    }

    @ViewBuilder
    private var bar: some View {
        if let g = geo, g.contentSize.height > g.containerSize.height + 1 {
            let box: CGFloat = g.containerSize.height
            let total: CGFloat = g.contentSize.height
            let thumb: CGFloat = max(24, box * box / total)
            let range: CGFloat = max(1, total - box)
            let at: CGFloat = min(1, max(0, (g.contentOffset.y + g.contentInsets.top) / range))
            Capsule().fill(theme.text.opacity(0.35))
                .frame(width: 3, height: thumb)
                .offset(y: at * (box - thumb))
                .allowsHitTesting(false)
        }
    }
}
