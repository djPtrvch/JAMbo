// ОТЛОЖЕНО (решение пользователя): окно DIAGNOSTICS, счётчики перерисовок (RedrawMeter) и кадров (FrameMeter) убраны
// из сборки JAMbo.swiftpm, чтобы облегчить сборку в Playgrounds. Вернуть: перенести 4 файла этой папки в
// ios/JAMbo.swiftpm/UI; в AppModel — `var appWindow: AppWindow? = nil`, `@ObservationIgnored let frameMeter = FrameMeter()`,
// в init — `audio.core.profile.enabled = true; frameMeter.start()`, в drain — замер frameMeter.drained; в RootView —
// окно AppWindowView в overlays и пункты AppWindow в меню бутерброда (с SHIFT); вызовы RedrawMeter.hit(...) в телах
// видов — по коммиту f0e3f64 (последняя версия с ними).

import SwiftUI

/// Окна раздела APP бутерброда (S9e): поверх экрана, название слева, ✕ справа в верхней строке.
enum AppWindow: String, CaseIterable {
    case diagnostics = "DIAGNOSTICS"
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
                CloseButton { model.appWindow = nil }
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
        }
    }
}
