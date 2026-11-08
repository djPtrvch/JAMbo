import SwiftUI

/// Окна раздела APP бутерброда (S9e): поверх экрана, название слева, ✕ справа в верхней строке. SELF-TEST убран
/// (1.11, облегчение сборки): сверки с эталонами — в тестах Core.
enum AppWindow: String, CaseIterable {
    case diagnostics = "DIAGNOSTICS"
}

struct AppWindowView: View {
    let model: AppModel
    let window: AppWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(window.rawValue).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                CloseButton { model.appWindow = nil }
            }
            content
        }
        .padding(12)
        .tile(theme.bg, radius: 10, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
    }

    private var content: AnyView {
        switch window {
        case .diagnostics:
            return AnyView(DiagnosticsView(model: model))
        }
    }
}
