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

    /// Звук запускается первым нажатием TONE (S0: так интерфейс виден, даже если звук не стартует).
    private var audioStarted: Bool = false

    init() {
        trace("model init")
    }

    func resumeAudio() {
        if audioStarted { audio.start() }
    }

    func pauseAudio() {
        if audioStarted { audio.stop() }
    }

    func toggleTone() {
        if !audioStarted {
            audioStarted = true
            audio.start()
        }
        toneOn.toggle()
        audio.core.events.push(.tone(on: toneOn))
    }

    private static func loadAppearance() -> Appearance {
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? ""
        return Appearance(rawValue: raw) ?? .system
    }
}
