import SwiftUI

/// Окна раздела APP бутерброда (S9e): поверх экрана, название слева, ✕ справа в верхней строке.
enum AppWindow: String, CaseIterable {
    case diagnostics = "DIAGNOSTICS"
    case selfTest = "SELF-TEST"
    case song = "EXPORT SONG"

    /// Окна в разделе APP бутерброда (EXPORT SONG — в PROJECTS).
    static let menu: [AppWindow] = [.diagnostics, .selfTest]
}

struct AppWindowView: View {
    let model: AppModel
    let window: AppWindow
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(window.rawValue).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                CloseButton {
                    // Закрыли окно во время экспорта песни — экспорт отменяется.
                    if window == .song { model.cancelSong() }
                    model.appWindow = nil
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch window {
        case .diagnostics: DiagnosticsView(model: model)
        case .selfTest: SelfTestPanel()
        case .song: SongExportView(model: model)
        }
    }
}
