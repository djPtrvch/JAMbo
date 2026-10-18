import SwiftUI

// Кнопки мастера: при MST на месте LFO1–3 и ENV (сетка 2×2: CLIP, LIM / SAT, COMP). Тап — окно модуля (S9a);
// с зажатой SHIFT — BYPASS модуля (видно только с SHIFT: включённый bypass окрашен цветом модуля, как волны скопа).

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
        let on: Bool = shift && model.masterBypass(module)
        let title: String = shift ? "BYPASS " + names[module] : names[module]
        return Text(title)
            .font(.system(size: shift ? 11 : 13, weight: .semibold))
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(on ? (module == MasterScope.sat ? theme.bg : theme.onAccent) : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? colors[module] : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture {
                // Без SHIFT — окно модуля.
                if model.shiftHeld { model.toggleMasterBypass(module) } else { model.openMasterWindow(module) }
            }
    }
}
