import SwiftUI

// Панда-пасхалка (прототип пользователя DancingPanda.swift): окно MIX слева, SHIFT + тап — панда и обратно
// (PandaWindow.swift). Отличия от прототипа: состояние и фаза долей читаются каждый кадр (stateProvider,
// beatPhaseProvider — аудио-часы секвенсора), переходы сна и бодрствования, подъём рук и рот — плавные (PandaMotion),
// кадры — до 30 в секунду, цвета наушников — из темы (accent, rec), без #Preview. Уши, руки, ноги, глаза, нос и рот — чёрные
// (PandaPalette.limb; по второй версии прототипа и решению пользователя).

// MARK: - Palette (под тёмный UI JAMbo)

enum PandaPalette {
    static let fur    = Color(white: 0.94)
    static let dark   = Color(white: 0.16)
    static let belly  = Color(white: 0.88)
    static let cheek  = Color(red: 1.0, green: 0.55, blue: 0.5).opacity(0.35)
    static let accent = Color(red: 1.0, green: 0.80, blue: 0.10) // обычные наушники
    static let rec    = Color(red: 0.95, green: 0.22, blue: 0.20) // наушники при записи
    static let limb   = Color.black // уши, руки, ноги, глаза, нос, рот
}

// MARK: - Input

struct PandaState {
    var isPlaying: Bool = false
    var isRecording: Bool = false
    var bpm: Double = 130
    /// true, пока на дорожке Voice есть звук (играет голос)
    var voiceActive: Bool = false

    /// Всё на стопе: панда спит
    var isAsleep: Bool { !isPlaying && !isRecording }
}

// MARK: - Motion

/// Плавные величины между кадрами (без наблюдения: перерисовку ведёт TimelineView). Фаза — доли от аудио-часов
/// при игре, без игры — дальше по темпу (раскачивание затихает, не прыгая).
final class PandaMotion {
    struct Frame {
        var phase: Double = 0
        var awake: Double = 0
        var play: Double = 0
        var raise: Double = 0
        var mouth: Double = 0
    }

    private var last: Double = -1
    private var f = Frame()

    func step(_ st: PandaState, beat: Double?, time: Double) -> Frame {
        let dt: Double = last < 0 ? 1 : Swift.min(0.1, Swift.max(0, time - last))
        last = time
        if let b = beat, st.isPlaying {
            f.phase = b
        } else {
            f.phase += dt * st.bpm / 60
        }
        let x: Double = Swift.min(Swift.max((st.bpm - 100) / 70, 0), 1)
        let raiseT: Double = st.isPlaying ? x * x * (3 - 2 * x) : 0
        let mouthT: Double = st.isPlaying && st.voiceActive ? 0.5 + 0.5 * abs(sin(f.phase * .pi * 2)) : 0
        f.awake = PandaMotion.ease(f.awake, st.isAsleep ? 0 : 1, dt, 0.35)
        f.play = PandaMotion.ease(f.play, st.isPlaying ? 1 : 0, dt, 0.3)
        f.raise = PandaMotion.ease(f.raise, raiseT, dt, 0.3)
        f.mouth = PandaMotion.ease(f.mouth, mouthT, dt, 0.04)
        return f
    }

    static func ease(_ v: Double, _ target: Double, _ dt: Double, _ tau: Double) -> Double {
        return v + (target - v) * (1 - exp(-dt / tau))
    }
}

// MARK: - View

/// beatPhaseProvider: доли такта из аудио-часов секвенсора (0...∞; nil — не играет).
/// Если не задан, фаза считается от времени и BPM.
struct DancingPanda: View {
    var state: PandaState = PandaState()
    /// Состояние на каждый кадр (иначе — state).
    var stateProvider: (() -> PandaState)? = nil
    var beatPhaseProvider: (() -> Double?)? = nil
    var accent: Color = PandaPalette.accent
    var rec: Color = PandaPalette.rec
    @State private var motion = PandaMotion()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let time: Double = tl.date.timeIntervalSinceReferenceDate
            let st: PandaState = stateProvider?() ?? state
            let m: PandaMotion.Frame = motion.step(st, beat: beatPhaseProvider?() ?? nil, time: time)
            PandaCanvas(state: st, m: m, time: time, headphones: st.isRecording ? rec : accent)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Drawing

private struct PandaCanvas: View {
    let state: PandaState
    let m: PandaMotion.Frame
    let time: Double
    let headphones: Color

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let sleep: Double = 1 - m.awake
            let asleep: Bool = m.awake < 0.5

            // Раскачивание влево-вправо: полный цикл за 2 доли
            let sway: Double = sin(m.phase * .pi) * m.play
            let breathe: Double = sin(time * 1.6)

            let bodyTilt = Angle.degrees(sway * 7)
            let headTilt = Angle.degrees(-sway * 5 + 3 * sleep)
            let breatheY: CGFloat = CGFloat(1 + 0.015 * breathe * sleep)

            ZStack {
                Ellipse()
                    .fill(.black.opacity(0.35))
                    .frame(width: s * 0.55, height: s * 0.07)
                    .position(x: s * 0.5, y: s * 0.93)

                ZStack {
                    Circle().fill(PandaPalette.limb).frame(width: s * 0.208)
                        .position(x: s * 0.31, y: s * 0.18)
                    Circle().fill(PandaPalette.limb).frame(width: s * 0.208)
                        .position(x: s * 0.69, y: s * 0.18)

                    Capsule().fill(PandaPalette.limb)
                        .frame(width: s * 0.177, height: s * 0.246)
                        .position(x: s * 0.37, y: s * 0.82)
                    Capsule().fill(PandaPalette.limb)
                        .frame(width: s * 0.177, height: s * 0.246)
                        .position(x: s * 0.63, y: s * 0.82)

                    Ellipse().fill(PandaPalette.fur)
                        .frame(width: s * 0.54, height: s * 0.48)
                        .position(x: s * 0.5, y: s * 0.62)
                    Ellipse().fill(PandaPalette.belly)
                        .frame(width: s * 0.34, height: s * 0.30)
                        .position(x: s * 0.5, y: s * 0.66)

                    arm(left: true, angle: -35 + 180 * m.raise + sway * 12, s: s)
                    arm(left: false, angle: 35 - 180 * m.raise + sway * 12, s: s)

                    head(s: s, asleep: asleep, mouth: m.mouth)
                        .rotationEffect(headTilt, anchor: UnitPoint(x: 0.5, y: 0.8))
                }
                .scaleEffect(x: 1, y: breatheY, anchor: .bottom)
                .rotationEffect(bodyTilt, anchor: .bottom)

                if sleep > 0.01 { zzz(s: s).opacity(sleep) }
            }
            .frame(width: s, height: s)
        }
    }

    // MARK: parts

    private func arm(left: Bool, angle: Double, s: CGFloat) -> some View {
        Capsule().fill(PandaPalette.limb)
            .frame(width: s * 0.11, height: s * 0.26)
            .rotationEffect(.degrees(angle), anchor: .top)
            .position(x: s * (left ? 0.27 : 0.73), y: s * 0.60)
    }

    private func head(s: CGFloat, asleep: Bool, mouth: Double) -> some View {
        let hp: Color = headphones
        let mo: CGFloat = CGFloat(mouth)
        return ZStack {
            Circle().fill(PandaPalette.fur)
                .frame(width: s * 0.52, height: s * 0.52)
                .position(x: s * 0.5, y: s * 0.30)

            // Пятна вокруг глаз
            Ellipse().fill(PandaPalette.limb)
                .frame(width: s * 0.13, height: s * 0.17)
                .rotationEffect(.degrees(20))
                .position(x: s * 0.40, y: s * 0.30)
            Ellipse().fill(PandaPalette.limb)
                .frame(width: s * 0.13, height: s * 0.17)
                .rotationEffect(.degrees(-20))
                .position(x: s * 0.60, y: s * 0.30)

            // Глаза: закрыты, когда спит
            if asleep {
                Capsule().fill(PandaPalette.fur).frame(width: s * 0.06, height: s * 0.012)
                    .position(x: s * 0.40, y: s * 0.30)
                Capsule().fill(PandaPalette.fur).frame(width: s * 0.06, height: s * 0.012)
                    .position(x: s * 0.60, y: s * 0.30)
            } else {
                Circle().fill(PandaPalette.fur).frame(width: s * 0.045)
                    .position(x: s * 0.41, y: s * 0.295)
                Circle().fill(PandaPalette.fur).frame(width: s * 0.045)
                    .position(x: s * 0.59, y: s * 0.295)
            }

            Circle().fill(PandaPalette.cheek).frame(width: s * 0.06)
                .position(x: s * 0.33, y: s * 0.38)
            Circle().fill(PandaPalette.cheek).frame(width: s * 0.06)
                .position(x: s * 0.67, y: s * 0.38)

            Ellipse().fill(PandaPalette.limb)
                .frame(width: s * 0.07, height: s * 0.045)
                .position(x: s * 0.5, y: s * 0.355)

            // Рот
            Capsule().fill(PandaPalette.limb)
                .frame(width: s * 0.05 + s * 0.03 * mo,
                       height: s * 0.015 + s * 0.05 * mo)
                .position(x: s * 0.5, y: s * 0.41)

            // Наушники: жёлтые, при записи красные
            Capsule().stroke(hp, lineWidth: s * 0.02)
                .frame(width: s * 0.58, height: s * 0.30)
                .offset(y: -s * 0.01)
                .mask(Rectangle().frame(width: s, height: s * 0.2).offset(y: -s * 0.12))
                .position(x: s * 0.5, y: s * 0.22)
            RoundedRectangle(cornerRadius: s * 0.02).fill(hp)
                .frame(width: s * 0.05, height: s * 0.11)
                .position(x: s * 0.215, y: s * 0.31)
            RoundedRectangle(cornerRadius: s * 0.02).fill(hp)
                .frame(width: s * 0.05, height: s * 0.11)
                .position(x: s * 0.785, y: s * 0.31)
        }
    }

    // z Z Z, по очереди загораются
    private func zzz(s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let k: Double = max(0, sin(time * 1.5 - Double(i) * 0.8))
                Text(i == 0 ? "z" : "Z")
                    .font(.system(size: s * (0.07 + 0.025 * CGFloat(i)), weight: .bold, design: .rounded))
                    .foregroundStyle(PandaPalette.fur)
                    .opacity(0.25 + 0.75 * k)
                    .position(x: s * (0.78 + 0.06 * CGFloat(i)),
                              y: s * (0.16 - 0.055 * CGFloat(i)))
            }
        }
    }
}
