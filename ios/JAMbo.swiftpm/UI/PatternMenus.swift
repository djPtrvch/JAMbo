import SwiftUI

/// Меню сетки паттернов: ячейки (duplicate, copy, paste, delete), строки (имя, повторы, duplicate, copy, paste, delete),
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
                RowMenu(model: model, row: k).offset(rowOffset(k))
            }
            if model.gridMenuOpen {
                dismiss { model.gridMenuOpen = false }
                GridMenu(model: model)
                    .frame(width: gridMenuWidth)
                    .offset(x: geometry.size.width - gridMenuWidth, y: 0)
            }
        }
    }

    private func dismiss(_ close: @escaping () -> Void) -> some View {
        Color.black.opacity(0.001)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onTapGesture { close() }
    }

    private var gridMenuWidth: CGFloat {
        let want: CGFloat = geometry.trackW + Layout.gap + geometry.sceneW + 220
        return min(geometry.size.width, want)
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
        return CGSize(width: 6, height: fits ? below : above)
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
    /// 4 строки по 40, 3 зазора по 6, поля 16.
    static let height: CGFloat = 194
    let model: AppModel
    let state: CellMenuState

    var body: some View {
        let c = state.cell
        let t: Track = model.project.tracks[min(c.track, model.project.tracks.count - 1)]
        let filled: Bool = t.clipFilled(c.row)
        return VStack(spacing: 6) {
            MenuItem(title: "DUPLICATE", enabled: filled && t.freeSlot(after: c.row) >= 0) { run { model.duplicateClip(c) } }
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

/// Меню строки: имя (до 12 знаков), REPEATS − n +, DUPLICATE, COPY, PASTE, DELETE, OK.
struct RowMenu: View {
    /// Имя 44, REPEATS 44, 3 строки по 40, 4 зазора по 6, поля 16.
    static let height: CGFloat = 248
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
        .frame(width: 236)
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
        return ScrollView {
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
        }
        .frame(maxHeight: 420)
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
