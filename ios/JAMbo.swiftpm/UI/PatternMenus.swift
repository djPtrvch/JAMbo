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
            .modifier(MenuBox())
    }
}

/// Фон окна меню: панель цвета фона со скруглением, обводка 1 px, тень (shadow). Один модификатор вместо цепочки из
/// трёх на каждом месте (S14, объём сборки).
struct MenuBox: ViewModifier {
    var radius: CGFloat = Layout.radius
    var shadow: Bool = true
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let framed = content
            .background(theme.bg, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(theme.line, lineWidth: 1))
        if shadow {
            return AnyView(framed.shadow(color: .black.opacity(0.5), radius: 12, y: 4))
        }
        return AnyView(framed)
    }
}

/// Плитка: на всю ширину и высоту (содержимое — по alignment), фон fill со скруглением radius. Один модификатор вместо
/// двух на каждом месте (S14, объём сборки).
struct Tile: ViewModifier {
    let fill: Color
    var radius: CGFloat = Layout.radius
    var alignment: Alignment = .center

    init(_ fill: Color, radius: CGFloat = Layout.radius, alignment: Alignment = .center) {
        self.fill = fill
        self.radius = radius
        self.alignment = alignment
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
    }
}

/// Фон fill со скруглением radius и обводка line толщиной width. Один модификатор вместо двух на каждом месте (S14).
struct Framed: ViewModifier {
    let fill: Color
    let line: Color
    var radius: CGFloat = Layout.radius
    var width: CGFloat = 1

    init(_ fill: Color, line: Color, radius: CGFloat = Layout.radius, width: CGFloat = 1) {
        self.fill = fill
        self.line = line
        self.radius = radius
        self.width = width
    }

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(line, lineWidth: width))
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

/// Вариант в ряду кнопок меню (MenuChoiceRow): данные вместо отдельной кнопки в коде — сборщику легче (S14, сборка
/// в Playgrounds упирается в память компилятора).
struct MenuChoice {
    let title: String
    var enabled: Bool = true
    var red: Bool = false
    let current: Bool
    let action: () -> Void
}

/// Подпись поля (FieldLabel) и ряд кнопок MenuItem поровну — по списку вариантов.
struct MenuChoiceRow: View {
    let label: String
    let items: [MenuChoice]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: label)
            MenuChoiceButtons(items: items)
        }
    }
}

/// Ряд кнопок MenuItem поровну — по списку вариантов (без подписи).
struct MenuChoiceButtons: View {
    let items: [MenuChoice]
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items.indices, id: \.self) { i in
                let c: MenuChoice = items[i]
                MenuItem(title: c.title, enabled: c.enabled, red: c.red, current: c.current, action: c.action)
            }
        }
    }
}

/// Столбик кнопок MenuItem (меню блока, дорожки, клипа) — по списку вариантов, зазор 6.
struct MenuChoiceColumn: View {
    let items: [MenuChoice]
    var spacing: CGFloat = 6

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(items.indices, id: \.self) { i in
                let c: MenuChoice = items[i]
                MenuItem(title: c.title, enabled: c.enabled, red: c.red, current: c.current, action: c.action)
            }
        }
    }
}

struct CellMenu: View {
    /// TO ARRANGE 40 с отступом 8 снизу, 3 строки по 40, 3 зазора по 6, поля 16.
    static let height: CGFloat = 202
    let model: AppModel
    let state: CellMenuState

    var body: some View {
        let c = state.cell
        let t: Track = model.project.tracks[min(c.track, model.project.tracks.count - 1)]
        let filled: Bool = t.clipFilled(c.row)
        let arrange: Bool = t.clipHasTrigs(c.row) || model.gridSel.contains(c)
        let group: Bool = model.carryGroup(c) != nil
        let m: AppModel = model
        let sel: GridSelection = m.gridSel
        let run: (@escaping () -> Void) -> () -> Void = { f in
            return {
                m.cellMenu = nil
                m.gridSel = GridSelection()
                f()
            }
        }
        // Клип в выделении рамкой — DELETE удаляет все выделенные.
        let items: [MenuChoice] = [
            MenuChoice(title: "COPY", enabled: filled, current: false, action: run { m.copyClip(c) }),
            MenuChoice(title: "PASTE", enabled: m.clipClipboard != nil, current: false, action: run { m.pasteClip(c) }),
            MenuChoice(title: "DELETE", enabled: filled || group, red: true, current: false,
                       action: run { if group { m.deleteSelection(sel, rows: false) } else { m.deleteClip(c) } }),
        ]
        return VStack(spacing: 6) {
            MenuItem(title: "TO ARRANGE", enabled: arrange) {
                m.cellMenu = nil
                m.clipToArrange(c)
            }
            .padding(.bottom, 8)
            MenuChoiceColumn(items: items)
        }
        .frame(width: 180)
        .modifier(MenuPanel())
    }
}

/// Меню строки: имя (до 12 знаков), REPEATS − n +, TO ARRANGE, DUPLICATE, COPY, PASTE, DELETE, OK.
struct RowMenu: View {
    /// Имя 44, REPEATS 44, TO ARRANGE 40 и отступы 8 сверху и снизу, 3 строки по 40, 5 зазоров по 6, поля 16.
    static let height: CGFloat = 310
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
            MenuChoiceButtons(items: [
                MenuChoice(title: "DUPLICATE", enabled: model.project.canAddRow, current: false) { act { model.duplicateRow(row) } },
                MenuChoice(title: "COPY", current: false) { act { model.copyRow(row) } },
            ], spacing: 6)
            MenuChoiceButtons(items: [
                MenuChoice(title: "PASTE", enabled: model.rowClipboard != nil, current: false) { act { model.pasteRow(row) } },
                MenuChoice(title: "DELETE", red: true, current: false) { deleteRow() },
            ], spacing: 6)
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

    /// TO ARRANGE (S15e): блоки строки (или всего выделенного рамкой) — с курсора (имя и повторы — из этого окна).
    private var arrangeRow: some View {
        let p: Project = model.project
        let any: Bool = p.tracks.contains { $0.clipHasTrigs(row) } || model.gridSel.touches(row: row)
        // Отступ — чтобы не сливался с кнопками окна (решение пользователя).
        return MenuItem(title: "TO ARRANGE", enabled: any) {
            model.rowMenu = nil
            model.rowToArrange(row, name: name, repeats: reps)
        }
        .padding(.vertical, 8)
    }

    /// Строка в выделении рамкой — удаляются все выделенные (строки целиком и клипы).
    private func deleteRow() {
        var sel: GridSelection = model.gridSel
        if sel.touches(row: row) && (sel.rows.count + sel.cells.count) > 1 {
            sel.rows.insert(row)
            act { model.deleteSelection(sel, rows: true) }
        } else {
            act { model.deleteRow(row) }
        }
    }

    private func done() {
        model.setScene(row, name: name, repeats: reps)
        model.rowMenu = nil
    }

    private func act(_ f: () -> Void) {
        model.rowMenu = nil
        model.gridSel = GridSelection()
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
/// Не обобщённый (содержимое — AnyView): одна копия кода на все меню (объём сборки, 7.11).
struct MenuScroll: View {
    let content: AnyView
    @State private var geo: ScrollGeometry? = nil
    @Environment(\.theme) private var theme

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
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
