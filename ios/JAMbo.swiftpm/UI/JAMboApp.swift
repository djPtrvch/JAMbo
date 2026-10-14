import SwiftUI

@main
struct JAMboApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ThemedRoot(model: model)
                .preferredColorScheme(model.appearance.scheme)
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active: model.audio.start()
            case .background: model.audio.stop()
            default: break
            }
        }
    }
}

/// Корень: подставляет тему по текущей схеме.
struct ThemedRoot: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RootView(model: model)
            .environment(\.theme, Theme.of(scheme))
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }
}
