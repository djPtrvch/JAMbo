import SwiftUI

/// Главный экран (сверху вниз, как в вебе): верхняя панель, центр, строка дорожек, секвенсор, пианоролл.
/// S1a: центр и пианоролл — заглушки (сетка ручек — S1b, пианоролл — S1c).
struct RootView: View {
    let model: AppModel
    @State private var menuOpen: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let layout: Layout = Layout(width: geo.size.width - 24)
            ZStack(alignment: .topLeading) {
                theme.bg.ignoresSafeArea()
                screen(layout)
                overlays
            }
        }
    }

    private func screen(_ layout: Layout) -> some View {
        VStack(spacing: Layout.gap) {
            TopBar(model: model, menuOpen: $menuOpen)
            Placeholder(title: "KNOBS · S1b")
            TrackRow(model: model, layout: layout)
            SequencerRow(model: model)
            Placeholder(title: "PIANO ROLL · S1c").frame(height: layout.pianoHeight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var overlays: some View {
        if menuOpen {
            MainMenu(model: model, isOpen: $menuOpen).padding(.top, 58).padding(.leading, 12)
        }
        if model.showDiagnostics {
            DiagnosticsView(model: model).padding(8)
        }
    }
}

/// Заглушка будущей части экрана.
struct Placeholder: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .foregroundStyle(theme.off)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
    }
}

/// Меню бутерброда: APPEARANCE (тема) и DIAGNOSTICS.
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
        .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
    }
}
