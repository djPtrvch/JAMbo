import SwiftUI

/// Меню окна модуля мастера (поверх экрана; тап мимо — закрыть): модули SAT, COMP, CLIP, LIM (по цепочке, открытое —
/// жёлтое) под названием; PRESETS — SAVE и список пресетов модуля под кнопкой (тап — загрузить, удержание — RENAME,
/// DELETE). Меню не выходит за окно модуля.
struct MasterMenuView: View {
    let model: AppModel
    let state: MasterMenuState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.masterMenu = nil }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.kind {
        case .modules:
            MasterModulesMenu(model: model)
                .modifier(MenuPanel())
                .frame(width: 150)
                .offset(x: state.anchor.minX, y: state.anchor.maxY + 6)
        case .presets:
            MasterPresetsMenu(model: model, maxHeight: menuHeight)
                .modifier(MenuPanel())
                .frame(width: MasterPresetsMenu.width)
                .offset(x: left(MasterPresetsMenu.width), y: state.anchor.maxY + 6)
        case .actions(let k):
            MasterPresetActions(model: model, index: k)
                .modifier(MenuPanel())
                .frame(width: 180)
                .offset(x: left(180), y: state.anchor.maxY + 6)
        }
    }

    /// Левый край: правым краем к кнопке, в пределах окна.
    private func left(_ w: CGFloat) -> CGFloat {
        let x: CGFloat = state.anchor.maxX - w
        return max(state.bounds.minX, x)
    }

    /// Высота списка: от кнопки до низа окна (низ меню не ниже верха кнопок дорожек).
    private var menuHeight: CGFloat {
        let h: CGFloat = state.bounds.maxY - state.anchor.maxY - 6 - 16
        return max(120, h)
    }
}

struct MasterModulesMenu: View {
    let model: AppModel

    var body: some View {
        let cur: Int = model.masterWin ?? -1
        return VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { m in
                MenuItem(title: MasterPresetBook.titles[m], current: m == cur) {
                    model.masterMenu = nil
                    model.openMasterWindow(m)
                }
            }
        }
    }
}

/// PRESETS модуля: заголовок с числом, SAVE (имя — окном ввода), сетка пресетов в 2 столбца с прокруткой.
struct MasterPresetsMenu: View {
    static let width: CGFloat = 340
    let model: AppModel
    let maxHeight: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let m: Int = model.masterWin ?? 0
        let list: [MasterPreset] = model.masterPresets.list(m)
        let title: String = "\(MasterPresetBook.titles[m]) PRESETS · \(list.count)"
        return VStack(alignment: .leading, spacing: 8) {
            MenuHead(title: title)
            MenuItem(title: "SAVE") {
                model.masterMenu = nil
                model.masterInput = .save
            }
            if list.isEmpty {
                Text("No \(MasterPresetBook.titles[m]) presets yet — save one with SAVE")
                    .font(.system(size: 12)).foregroundStyle(theme.dim)
            } else {
                MenuScroll { grid(m, list) }
                    .frame(height: listHeight(list.count))
            }
        }
    }

    /// Высота списка: все строки (40 + 6), но не выше места под заголовком и SAVE.
    private func listHeight(_ n: Int) -> CGFloat {
        let rows: CGFloat = CGFloat((n + 1) / 2)
        let full: CGFloat = rows * 46 - 6
        let room: CGFloat = max(46, maxHeight - 110)
        return min(full, room)
    }

    private func grid(_ m: Int, _ list: [MasterPreset]) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<list.count, id: \.self) { k in
                PresetCell(title: list[k].name, tap: {
                    model.masterMenu = nil
                    model.loadMasterPreset(m, k)
                }, hold: { r in
                    guard let s = model.masterMenu else { return }
                    model.masterMenu = MasterMenuState(kind: .actions(k), anchor: r, bounds: s.bounds)
                })
            }
        }
        .padding(.trailing, 6)
    }
}

/// Пресет в списке: тап — загрузить, удержание 0,5 с — действия (рамка ячейки — в hold).
struct PresetCell: View {
    let title: String
    let tap: () -> Void
    let hold: (CGRect) -> Void
    @State private var frame: CGRect = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(theme.text)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
            .onTapGesture { tap() }
            .onLongPressGesture(minimumDuration: 0.5) { hold(frame) }
    }
}

/// Действия с пресетом (удержание): RENAME (окно ввода), DELETE (красная).
struct MasterPresetActions: View {
    let model: AppModel
    let index: Int

    var body: some View {
        let m: Int = model.masterWin ?? 0
        let k: Int = index
        return VStack(spacing: 6) {
            MenuItem(title: "RENAME") {
                model.masterMenu = nil
                model.masterInput = .rename(k)
            }
            MenuItem(title: "DELETE", red: true) {
                model.masterMenu = nil
                model.deleteMasterPreset(m, k)
            }
        }
    }
}
