import SwiftUI

/// DIAGNOSTICS: фактическое состояние звука («Now:»), нагрузка, время колбэка по разделам и кадры интерфейса (S14a:
/// последняя секунда и худшее с RESET — замер идёт и при закрытом окне), сборка, место privacy manifest (SELF-TEST —
/// своё окно, S9e). Тест-тон и строка Tap — только в отладочной сборке (S14: в App Store отладочных функций нет).
struct DiagnosticsView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                info
            }
            HStack(spacing: 12) {
                InkButton(title: "RESET") {
                    model.audio.core.profile.resetWorst()
                    model.frameMeter.reset()
                }
                .frame(width: 120)
                #if DEBUG
                InkButton(title: "TEST TONE 440 Hz", active: model.toneOn) { model.toggleTone() }
                    .frame(width: 220)
                #endif
            }
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
            profileRows(core.profile.read())
            uiRows(model.frameMeter)
            row("Build", DiagnosticsView.build)
            row("Privacy", DiagnosticsView.privacy)
            #if DEBUG
            row("Tap", tapLine)
            #endif
            if !error.isEmpty { row("Error", error) }
        }
    }

    /// Время колбэка по разделам: доля блока (5,3 мс при буфере 256) — средняя и наибольшая за секунду звука, худшая
    /// с RESET.
    @ViewBuilder
    private func profileRows(_ stats: RenderProfile.Stats?) -> some View {
        if let s = stats {
            ForEach(0...RenderProfile.count, id: \.self) { k in
                let name: String = k < RenderProfile.count ? RenderProfile.names[k] : "Audio"
                row(name, DiagnosticsView.share(s.avg[k], s.peak[k], s.worst[k]))
            }
        } else {
            row("Audio", "measuring…")
        }
    }

    /// «12.5% avg · 30.1% peak · 41.0% worst».
    static func share(_ avg: Float, _ peak: Float, _ worst: Float) -> String {
        let a: String = String(format: "%.1f", avg * 100)
        let p: String = String(format: "%.1f", peak * 100)
        let w: String = String(format: "%.1f", worst * 100)
        return "\(a)% avg · \(p)% peak · \(w)% worst"
    }

    /// Кадры интерфейса за секунду и с RESET; drain — сообщения колбэка → состояние (главный поток).
    @ViewBuilder
    private func uiRows(_ m: FrameMeter) -> some View {
        let w: FrameMeter.FrameStats = m.last
        let fps: String = String(format: "%.0f", w.fps)
        let avg: String = String(format: "%.1f", w.avgMs)
        let worst: String = String(format: "%.1f", w.worstMs)
        row("UI", "\(fps) fps · frame \(avg) ms avg · \(worst) ms worst · \(w.dropped) dropped")
        let tw: String = String(format: "%.1f", m.totalWorstMs)
        row("UI total", "\(m.totalDropped) dropped of \(m.totalFrames) · \(tw) ms worst")
        let da: String = String(format: "%.2f", w.drainAvgMs)
        let dp: String = String(format: "%.2f", w.drainPeakMs)
        let dt: String = String(format: "%.2f", m.totalDrainMs)
        row("Drain", "\(da) ms avg · \(dp) ms peak · \(dt) ms worst")
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

    /// PrivacyInfo.xcprivacy (S14): App Store ищет его в корне бандла; Resources — проверить, куда его кладёт Playgrounds.
    static let privacy: String = {
        let b: Bundle = Bundle.main
        if b.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil { return "manifest in bundle root" }
        if b.url(forResource: "PrivacyInfo", withExtension: "xcprivacy", subdirectory: "Resources") != nil {
            return "manifest in Resources/ (not root)"
        }
        return "manifest missing"
    }()

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(theme.dim).frame(width: 60, alignment: .leading)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
        }
    }
}
