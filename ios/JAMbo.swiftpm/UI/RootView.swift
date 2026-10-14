import SwiftUI

/// Экран S0: верхняя панель (меню, тест-тон, CPU) и пустой центр.
struct RootView: View {
    let model: AppModel
    @State private var menuOpen: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 6) {
                topBar
                center
            }
            .padding(6)
            if menuOpen { MainMenu(model: model, isOpen: $menuOpen).padding(.top, 60).padding(.leading, 6) }
            if model.showDiagnostics { DiagnosticsView(model: model).padding(6) }
        }
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            BurgerButton { menuOpen.toggle() }
            InkButton(title: "TONE", active: model.toneOn) { model.toggleTone() }
                .frame(width: 120)
            Spacer()
            CPUIndicator(meter: model.audio.core.cpu)
        }
        .frame(height: 48)
    }

    private var center: some View {
        VStack(spacing: 8) {
            Text("JAMbo").font(.system(size: 28, weight: .bold)).foregroundStyle(theme.text)
            Text("S0 · test tone 440 Hz −12 dBFS").font(.system(size: 12)).foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Меню бутерброда: APP — SETTINGS (тема, DIAGNOSTICS).
struct MainMenu: View {
    let model: AppModel
    @Binding var isOpen: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuHead(title: "APPEARANCE")
            HStack(spacing: 6) {
                ForEach(Appearance.allCases, id: \.self) { a in
                    InkButton(title: a.rawValue, active: model.appearance == a) { model.setAppearance(a) }
                }
            }
            Divider().overlay(theme.line)
            MenuHead(title: "DIAGNOSTICS")
            InkButton(title: "DIAGNOSTICS") {
                isOpen = false
                model.showDiagnostics = true
            }
        }
        .padding(12)
        .frame(width: 330)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
    }
}
