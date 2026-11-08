// Пробный прототип отслеживания головы — экран и модель.
// Слева — вид сверху: голова (нос — поворот) и источник у iPad. Справа — замеры и кнопки.

import SwiftUI
import UIKit

@main
struct HeadTrackApp: App {
    var body: some Scene {
        WindowGroup {
            HTScreen()
        }
    }
}

@MainActor
final class HTModel: ObservableObject {
    let shared = HTShared()
    let tracker: HTTracker
    let audio: HTAudio
    @Published var metrics = HTMetrics()
    @Published var tracking = true
    @Published var invert = false
    @Published var swapAxes = false
    @Published var tiltFix = true
    @Published var source = 0
    @Published var outMs: Double = 0
    @Published var bufMs: Double = 0
    @Published var route = ""
    private var started = false

    init() {
        tracker = HTTracker(shared: shared)
        audio = HTAudio(shared: shared)
    }

    func start() {
        if started { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true
        audio.start()
        tracker.start()
        applySign()
    }

    func tick() {
        metrics = tracker.snapshot()
        let l = audio.latency()
        outMs = l.0
        bufMs = l.1
        route = audio.error.isEmpty ? l.2 : audio.error
        applySign()
    }

    // Знак поворота: без TILT FIX в landscapeRight оси камеры развёрнуты на 180° относительно landscapeLeft
    // (с TILT FIX ориентация не важна — разворот на 180° снимает CENTER); INVERT — ручная правка.
    func applySign() {
        var s: Double = 1
        if !tiltFix, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if scene.interfaceOrientation == .landscapeRight { s = -1 }
        }
        if invert { s = -s }
        tracker.setSign(s)
    }

    func toggleTracking() {
        tracking.toggle()
        shared.cell[1] = tracking ? 1 : 0
    }

    func toggleInvert() {
        invert.toggle()
        applySign()
    }

    func toggleSwap() {
        swapAxes.toggle()
        tracker.setSwap(swapAxes)
    }

    func toggleTiltFix() {
        tiltFix.toggle()
        tracker.setGravity(tiltFix)
        applySign()
    }

    func setSource(_ i: Int) {
        source = i
        shared.cell[2] = Float(i) * 0.5236
    }

    func center() {
        tracker.center()
    }
}

struct HTScreen: View {
    @StateObject private var model = HTModel()
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            HTTopView(yawDeg: model.metrics.yawDeg, source: model.source)
                .frame(width: 320, height: 320)
            VStack(alignment: .leading, spacing: 16) {
                HTStats(model: model)
                HTButtons(model: model)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .foregroundColor(.white)
        .onAppear { model.start() }
        .onReceive(timer) { _ in model.tick() }
    }
}

// Вид сверху: iPad — полоса вверху, источник — жёлтая точка, голова — круг с носом.
struct HTTopView: View {
    let yawDeg: Double
    let source: Int

    var body: some View {
        Canvas { ctx, size in
            let cx: CGFloat = size.width / 2
            let cy: CGFloat = size.height * 0.62
            let r: CGFloat = size.width * 0.42
            let pad = CGRect(x: cx - 50, y: 8, width: 100, height: 8)
            ctx.fill(Path(pad), with: .color(.gray))
            let az: CGFloat = CGFloat(source) * 0.5236
            let sx: CGFloat = cx + r * sin(az)
            let sy: CGFloat = cy - r * cos(az)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - 9, y: sy - 9, width: 18, height: 18)), with: .color(.yellow))
            let head = CGRect(x: cx - 34, y: cy - 34, width: 68, height: 68)
            ctx.stroke(Path(ellipseIn: head), with: .color(.white), lineWidth: 2)
            let yaw: CGFloat = CGFloat(yawDeg * Double.pi / 180)
            var nose = Path()
            nose.move(to: CGPoint(x: cx, y: cy))
            nose.addLine(to: CGPoint(x: cx + 60 * sin(yaw), y: cy - 60 * cos(yaw)))
            ctx.stroke(nose, with: .color(.white), lineWidth: 3)
        }
    }
}

struct HTStats: View {
    @ObservedObject var model: HTModel

    var body: some View {
        let m = model.metrics
        let total: Double = m.camLatencyMs + model.outMs + model.bufMs
        return VStack(alignment: .leading, spacing: 6) {
            Text(m.status).font(.system(size: 22, weight: .bold))
            Text(String(format: "YAW %+.1f°   PITCH %+.1f°", m.yawDeg, m.pitchDeg))
                .font(.system(size: 32, weight: .bold).monospacedDigit())
            Text(String(format: "Tracking rate %.0f Hz   camera → angle %.0f ms", m.rateHz, m.camLatencyMs))
            Text(String(format: "Range seen %+.0f° … %+.0f°   lost %d times", m.minYaw, m.maxYaw, m.lostCount))
            Text(String(format: "Audio out %.0f ms + buffer %.1f ms", model.outMs, model.bufMs))
            Text("Output: " + model.route).foregroundColor(.gray)
            Text(String(format: "Estimated turn → sound ≈ %.0f ms (+ camera exposure)", total))
                .font(.system(size: 18, weight: .bold))
        }
        .font(.system(size: 16, weight: .semibold).monospacedDigit())
    }
}

struct HTButtons: View {
    @ObservedObject var model: HTModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HTButton(title: model.tracking ? "TRACKING ON" : "TRACKING OFF", on: model.tracking) { model.toggleTracking() }
                HTButton(title: "CENTER", on: false) { model.center() }
                HTButton(title: "INVERT", on: model.invert) { model.toggleInvert() }
                HTButton(title: "TILT FIX", on: model.tiltFix) { model.toggleTiltFix() }
                HTButton(title: "SWAP AXES", on: model.swapAxes) { model.toggleSwap() }
            }
            HStack(spacing: 12) {
                Text("SOURCE").foregroundColor(.gray)
                HTButton(title: "L 30°", on: model.source == -1) { model.setSource(-1) }
                HTButton(title: "CENTER", on: model.source == 0) { model.setSource(0) }
                HTButton(title: "R 30°", on: model.source == 1) { model.setSource(1) }
            }
        }
    }
}

struct HTButton: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .foregroundColor(on ? .black : .white)
                .background(on ? Color.yellow : Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
