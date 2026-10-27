import SwiftUI

@main
struct JAMboApp: App {
    @State private var model = AppModel()

    init() {
        trace("app init")
    }
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ThemedRoot(model: model)
                .preferredColorScheme(model.appearance.scheme)
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active: model.activate()
            case .background:
                model.flushAutosave()
                model.enterBackground()
            default: break
            }
        }
    }
}

/// Корень: подставляет тему по текущей схеме.
/// Отметки запуска в консоли Playgrounds (Show Console) — где остановился запуск; только в отладочной сборке.
func trace(_ text: @autoclosure () -> String) {
    #if DEBUG
    print("JAMbo: \(text())")
    #endif
}

struct ThemedRoot: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let _ = trace("root view")
        // Смена темы iPad — раскладка заново: ячейки .equatable() (ручки, шаги, дорожки, картинки FX) сравнивают
        // только свои данные и без этого оставались в цветах прежней темы (заливка ручек MIX).
        RootView(model: model)
            .id(scheme)
            .environment(\.theme, Theme.of(scheme))
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }
}
