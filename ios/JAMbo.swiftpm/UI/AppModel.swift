import Observation
import SwiftUI

/// Состояние интерфейса. Аудио меняется только через события (AudioCore.events).
@Observable
final class AppModel {
    let audio = AudioHost()
    var toneOn: Bool = false
    var showDiagnostics: Bool = false
    private(set) var appearance: Appearance = AppModel.loadAppearance()

    func setAppearance(_ value: Appearance) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance")
    }

    func toggleTone() {
        toneOn.toggle()
        audio.core.events.push(.tone(on: toneOn))
    }

    private static func loadAppearance() -> Appearance {
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? ""
        return Appearance(rawValue: raw) ?? .system
    }
}
