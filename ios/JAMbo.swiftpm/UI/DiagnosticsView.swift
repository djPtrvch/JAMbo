import SwiftUI

/// DIAGNOSTICS: фактическое состояние звука («Now:»), нагрузка, сборка, тест-тон (SELF-TEST — своё окно, S9e).
struct DiagnosticsView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                info
            }
            InkButton(title: "TEST TONE 440 Hz", active: model.toneOn) { model.toggleTone() }
                .frame(width: 220)
        }
    }

    private var info: some View {
        let core: AudioCore = model.audio.core
        let seconds: Double = Double(core.framesRendered) / AudioCore.sampleRate
        let error: String = model.audio.lastError
        return VStack(alignment: .leading, spacing: 6) {
            row("Now", model.audio.statusLine)
            row("Core", "48.0 kHz · \(String(format: "%.1f", seconds)) s rendered")
            row("CPU", "\(Int((core.cpu.load * 100).rounded()))% avg · \(Int((core.cpu.peak * 100).rounded()))% peak block")
            row("Build", DiagnosticsView.build)
            row("Tap", tapLine)
            if !error.isEmpty { row("Error", error) }
        }
    }

    /// KEY VELOCITY: последний толчок (g) и сила; подбор порогов TapVelocity.gMin / gMax.
    private var tapLine: String {
        let s: TapSensor = model.tapSensor
        if !s.available { return "no accelerometer — key position" }
        if !s.running { return "off (KEY VELOCITY)" }
        return String(format: "last tap %.3f g → %d%%", s.lastPeak, Int((s.lastVelocity * 100).rounded()))
    }

    /// Сборка: оптимизация компилятора (_isDebugAssertConfiguration — true при -Onone) и флаг DEBUG.
    /// Нагрузка CPU в отладочной сборке в разы выше, чем в релизной (App Store).
    static let build: String = {
        let optimized: String = _isDebugAssertConfiguration() ? "Debug (no optimization)" : "Release (optimized)"
        #if DEBUG
        let flag = "DEBUG flag on"
        #else
        let flag = "DEBUG flag off"
        #endif
        return "\(optimized) · \(flag)"
    }()

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(theme.dim).frame(width: 60, alignment: .leading)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
        }
    }
}
