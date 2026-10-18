import SwiftUI

/// Меню окна модуля мастера (поверх экрана; тап мимо — закрыть): модули SAT, COMP, CLIP, LIM (по цепочке, открытое —
/// жёлтое) под названием; PRESETS — SAVE и список пресетов модуля под кнопкой (тап — загрузить, свайп влево —
/// RENAME и DELETE). Меню не выходит за окно модуля.
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

/// PRESETS модуля: заголовок с числом, SAVE (имя — окном ввода), список пресетов с прокруткой.
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
                MenuScroll { rows(m, list) }
                    .frame(height: listHeight(list.count))
            }
        }
    }

    /// Высота списка: все строки (44 + 4), но не выше места под заголовком и SAVE.
    private func listHeight(_ n: Int) -> CGFloat {
        let full: CGFloat = CGFloat(n) * 48 - 4
        let room: CGFloat = max(48, maxHeight - 110)
        return min(full, room)
    }

    private func rows(_ m: Int, _ list: [MasterPreset]) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<list.count, id: \.self) { k in
                PresetRow(title: list[k].name, tap: {
                    model.masterMenu = nil
                    model.loadMasterPreset(m, k)
                }, rename: {
                    model.masterMenu = nil
                    model.masterInput = .rename(k)
                }, delete: {
                    model.deleteMasterPreset(m, k)
                })
                // Другой список (удалили пресет) — строки закрыты заново.
                .id("\(k)#\(list.count)#\(list[k].name)")
            }
        }
        .padding(.trailing, 6)
    }
}

/// Пресет в списке (как строки списков iPad): тап — загрузить; свайп влево открывает справа кнопки — карандаш
/// на сером (RENAME) и корзина на красном (DELETE); свайп вправо или тап по открытой строке — закрыть.
struct PresetRow: View {
    static let button: CGFloat = 52
    static let reveal: CGFloat = 2 * PresetRow.button + 4
    let title: String
    let tap: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var open: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .trailing) {
            actions.opacity(offset < -1 ? 1 : 0)
            label
                .offset(x: offset)
                .simultaneousGesture(swipe)
                .onTapGesture {
                    if open { close() } else { tap() }
                }
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var label: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(theme.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }

    private var actions: some View {
        HStack(spacing: 4) {
            icon("pencil", Color(hex: 0x8e8e93)) {
                close()
                rename()
            }
            icon("trash", theme.rec) {
                close()
                delete()
            }
        }
    }

    private func icon(_ name: String, _ bg: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: PresetRow.button, height: 44)
                .background(bg, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// Горизонтальный свайп (вертикальный — прокрутка списка).
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { g in
                if abs(g.translation.width) < abs(g.translation.height) { return }
                let base: CGFloat = open ? -PresetRow.reveal : 0
                let x: CGFloat = base + g.translation.width
                offset = min(0, max(-PresetRow.reveal - 24, x))
            }
            .onEnded { _ in
                let show: Bool = offset < -PresetRow.reveal / 2
                open = show
                withAnimation(.easeOut(duration: 0.2)) { offset = show ? -PresetRow.reveal : 0 }
            }
    }

    private func close() {
        open = false
        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
    }
}
