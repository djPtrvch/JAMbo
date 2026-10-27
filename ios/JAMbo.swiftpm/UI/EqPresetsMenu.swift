import SwiftUI

/// Меню PRESETS EQ (как пресеты EQ веба и модулей мастера): заголовок, SAVE (имя — окном ввода), список имён
/// с прокруткой (без числа пресетов и полос — решение пользователя): тап — загрузить в EQ показанного канала (UNDO),
/// SAVE DEFAULT — полосы EQ по умолчанию для новых дорожек или проектов (у коррекции наушников — свой список, без него),
/// свайп влево — RENAME (карандаш на сером) и DELETE (корзина на красном). Правым краем к кнопке, не ниже поля EQ; тап мимо — закрыть.
struct EqPresetsMenu: View {
    static let width: CGFloat = 260
    let model: AppModel
    let state: EqPresetMenuState
    @Environment(\.theme) private var theme

    var body: some View {
        let x: CGFloat = max(8, state.anchor.maxX - EqPresetsMenu.width)
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.eqPresetMenu = nil }
            content
                .modifier(MenuPanel())
                .frame(width: EqPresetsMenu.width)
                .offset(x: x, y: state.anchor.maxY + 6)
        }
    }

    /// Место под меню: от кнопки до низа поля EQ.
    private var maxHeight: CGFloat {
        let h: CGFloat = state.bottom - state.anchor.maxY - 6 - 16
        return max(120, h)
    }

    private var content: some View {
        let list: [EqPreset] = model.eqBook.list
        let phones: Bool = model.phonesShown
        let saved: Bool = model.defaultSaved == .eq
        return VStack(alignment: .leading, spacing: 8) {
            MenuHead(title: phones ? "PHONES PRESETS" : "EQ PRESETS")
            MenuItem(title: "SAVE") {
                model.eqPresetMenu = nil
                model.eqInputAsk = .save
            }
            if phones {
                // Профили в файлах AutoEQ (ParametricEQ.txt): IMPORT — в список и в коррекцию, EXPORT — коррекция.
                HStack(spacing: 4) {
                    MenuItem(title: "IMPORT") { model.choosePhonesFiles() }
                    MenuItem(title: "EXPORT") { model.exportPhones() }
                }
            } else {
                MenuItem(title: saved ? "SAVED" : "SAVE DEFAULT", current: saved) { model.saveEqDefault() }
            }
            if list.isEmpty {
                Text("No EQ presets yet — save one with SAVE")
                    .font(.system(size: 12)).foregroundStyle(theme.dim)
            } else {
                MenuScroll { rows(list) }
                    .frame(height: listHeight(list.count))
            }
        }
    }

    /// Высота списка: все строки (44 + 4), но не выше места под заголовком и SAVE.
    private func listHeight(_ n: Int) -> CGFloat {
        let full: CGFloat = CGFloat(n) * 48 - 4
        let room: CGFloat = max(48, maxHeight - 158)
        return min(full, room)
    }

    private func rows(_ list: [EqPreset]) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<list.count, id: \.self) { k in
                SwipeRow(title: list[k].name, tap: {
                    model.eqPresetMenu = nil
                    model.loadEqPreset(k)
                }, rename: {
                    model.eqPresetMenu = nil
                    model.eqInputAsk = .rename(k)
                }, delete: {
                    model.deleteEqPreset(k)
                })
                // Другой список (удалили пресет) — строки закрыты заново.
                .id("\(k)#\(list.count)#\(list[k].name)")
            }
        }
        .padding(.trailing, 6)
    }
}
