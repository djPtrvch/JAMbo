import SwiftUI

// Кнопки мастера: при MST на месте LFO1–3 и ENV (сетка 2×2: COMP, CLIP / SAT, LIM). Тап — окно модуля (S6);
// с зажатой SHIFT — BYPASS модуля (с SHIFT включённый bypass залит цветом модуля, как волны скопа). Рамка цветом модуля —
// модуль работает (bypass выключен); bypass включён — рамки нет.

extension AppModel {
    /// Bypass модуля мастера (номер — как MasterScope: SAT 0, COMP 1, CLIP 2, LIM 3).
    func masterBypass(_ m: Int) -> Bool {
        switch m {
        case MasterScope.sat: return project.satBypass
        case MasterScope.comp: return project.cmpBypass
        case MasterScope.clip: return project.clipBypass
        default: return project.limBypass
        }
    }

    /// Включить и выключить bypass модуля (одна запись в UNDO).
    func toggleMasterBypass(_ m: Int) {
        edit { p in
            switch m {
            case MasterScope.sat: p.satBypass.toggle()
            case MasterScope.comp: p.cmpBypass.toggle()
            case MasterScope.clip: p.clipBypass.toggle()
            default: p.limBypass.toggle()
            }
        }
    }
}

struct MasterButton: View {
    let model: AppModel
    let module: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let names: [String] = ["SAT", "COMP", "CLIP", "LIM"]
        let colors: [Color] = [theme.text, theme.accent, theme.gr, theme.rec]
        let shift: Bool = model.shiftHeld
        let bypass: Bool = model.masterBypass(module)
        let on: Bool = shift && bypass
        // С SHIFT — в две строки: BYPASS и имя модуля.
        let title: String = shift ? "BYPASS\n" + names[module] : names[module]
        return Text(title)
            .font(.system(size: shift ? 11 : 13, weight: .semibold))
            .tracking(1)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundStyle(on ? (module == MasterScope.sat ? theme.bg : theme.onAccent) : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? colors[module] : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(bypass ? Color.clear : colors[module], lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture {
                // Без SHIFT — окно модуля.
                if model.shiftHeld { model.toggleMasterBypass(module) } else { model.openMasterWindow(module) }
            }
    }
}
