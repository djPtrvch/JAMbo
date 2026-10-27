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
        RootView(model: model)
            .environment(\.theme, Theme.of(scheme))
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }
}
