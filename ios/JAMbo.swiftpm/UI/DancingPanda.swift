import SwiftUI

// Панда-пасхалка (прототип пользователя DancingPanda.swift): окно MIX слева, SHIFT + тап — панда и обратно
// (PandaWindow.swift). Отличия от прототипа: состояние и фаза долей читаются каждый кадр (stateProvider,
// beatPhaseProvider — аудио-часы секвенсора), переходы сна и бодрствования, подъём рук и рот — плавные (PandaMotion),
// кадры — до 30 в секунду, рисование — одним Canvas (PandaDraw), цвета наушников — из темы (accent, rec), без #Preview. Уши, руки, ноги, глаза, нос и рот — чёрные
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

/// Панда одним Canvas (S14e: прежние ~30 фигур SwiftUI с длинными выражениями размеров иногда не укладывались в лимит
/// проверки типов компилятора Playgrounds — сборка то проходила, то нет). Геометрия прототипа — в долях стороны
/// квадрата (1 × 1), повороты — переносом начала координат; вид тот же.
private struct PandaCanvas: View {
    let state: PandaState
    let m: PandaMotion.Frame
    let time: Double
    let headphones: Color

    var body: some View {
        Canvas { ctx, size in
            PandaDraw.draw(ctx, size, m: m, time: time, headphones: headphones)
        }
    }
}

enum PandaDraw {
    static func draw(_ base: GraphicsContext, _ size: CGSize, m: PandaMotion.Frame, time: Double, headphones: Color) {
        let s: CGFloat = min(size.width, size.height)
        var ctx: GraphicsContext = base
        ctx.translateBy(x: (size.width - s) / 2, y: (size.height - s) / 2)
        let sleep: Double = 1 - m.awake
        // Раскачивание влево-вправо: полный цикл за 2 доли.
        let sway: Double = sin(m.phase * Double.pi) * m.play
        let breathe: Double = sin(time * 1.6)
        let bodyTilt: Double = sway * 7
        let headTilt: Double = -sway * 5 + 3 * sleep
        let breatheY: CGFloat = CGFloat(1 + 0.015 * breathe * sleep)

        var u: GraphicsContext = ctx
        u.scaleBy(x: s, y: s)
        u.fill(ellipse(0.5, 0.93, 0.55, 0.07), with: .color(Color.black.opacity(0.35)))

        // Тело: поворот вокруг низа, дыхание — растяжение от низа.
        var b: GraphicsContext = u
        b.translateBy(x: 0.5, y: 1)
        b.rotate(by: Angle.degrees(bodyTilt))
        b.scaleBy(x: 1, y: breatheY)
        b.translateBy(x: -0.5, y: -1)
        drawBody(b, m: m, sway: sway)

        var h: GraphicsContext = b
        h.translateBy(x: 0.5, y: 0.8)
        h.rotate(by: Angle.degrees(headTilt))
        h.translateBy(x: -0.5, y: -0.8)
        drawHead(h, asleep: m.awake < 0.5, mouth: CGFloat(m.mouth), headphones: headphones)

        if sleep > 0.01 { drawZzz(ctx, s, time: time, alpha: sleep) }
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        let r: CGRect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        return Path(ellipseIn: r)
    }

    static func capsule(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        let r: CGRect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        return Path(roundedRect: r, cornerRadius: min(w, h) / 2)
    }

    /// Уши, ноги, туловище, живот, руки.
    static func drawBody(_ c: GraphicsContext, m: PandaMotion.Frame, sway: Double) {
        let limb: GraphicsContext.Shading = .color(PandaPalette.limb)
        c.fill(ellipse(0.31, 0.18, 0.208, 0.208), with: limb)
        c.fill(ellipse(0.69, 0.18, 0.208, 0.208), with: limb)
        c.fill(capsule(0.37, 0.82, 0.177, 0.246), with: limb)
        c.fill(capsule(0.63, 0.82, 0.177, 0.246), with: limb)
        c.fill(ellipse(0.5, 0.62, 0.54, 0.48), with: .color(PandaPalette.fur))
        c.fill(ellipse(0.5, 0.66, 0.34, 0.30), with: .color(PandaPalette.belly))
        let up: Double = 180 * m.raise
        let swing: Double = sway * 12
        drawArm(c, x: 0.27, angle: -35 + up + swing)
        drawArm(c, x: 0.73, angle: 35 - up + swing)
    }

    /// Рука: капсула 0,11 × 0,26 с центром на высоте 0,60, поворот вокруг верха.
    static func drawArm(_ base: GraphicsContext, x: CGFloat, angle: Double) {
        var c: GraphicsContext = base
        let top: CGFloat = 0.47
        c.translateBy(x: x, y: top)
        c.rotate(by: Angle.degrees(angle))
        c.translateBy(x: -x, y: -top)
        c.fill(capsule(x, 0.60, 0.11, 0.26), with: .color(PandaPalette.limb))
    }

    static func drawHead(_ c: GraphicsContext, asleep: Bool, mouth: CGFloat, headphones: Color) {
        let limb: GraphicsContext.Shading = .color(PandaPalette.limb)
        let fur: GraphicsContext.Shading = .color(PandaPalette.fur)
        c.fill(ellipse(0.5, 0.30, 0.52, 0.52), with: fur)
        // Пятна вокруг глаз.
        drawPatch(c, x: 0.40, angle: 20)
        drawPatch(c, x: 0.60, angle: -20)
        // Глаза: закрыты, когда спит.
        if asleep {
            c.fill(capsule(0.40, 0.30, 0.06, 0.012), with: fur)
            c.fill(capsule(0.60, 0.30, 0.06, 0.012), with: fur)
        } else {
            c.fill(ellipse(0.41, 0.295, 0.045, 0.045), with: fur)
            c.fill(ellipse(0.59, 0.295, 0.045, 0.045), with: fur)
        }
        let cheek: GraphicsContext.Shading = .color(PandaPalette.cheek)
        c.fill(ellipse(0.33, 0.38, 0.06, 0.06), with: cheek)
        c.fill(ellipse(0.67, 0.38, 0.06, 0.06), with: cheek)
        // Нос и рот.
        c.fill(ellipse(0.5, 0.355, 0.07, 0.045), with: limb)
        let mw: CGFloat = 0.05 + 0.03 * mouth
        let mh: CGFloat = 0.015 + 0.05 * mouth
        c.fill(capsule(0.5, 0.41, mw, mh), with: limb)
        drawHeadphones(c, headphones)
    }

    static func drawPatch(_ base: GraphicsContext, x: CGFloat, angle: Double) {
        var c: GraphicsContext = base
        c.translateBy(x: x, y: 0.30)
        c.rotate(by: Angle.degrees(angle))
        c.fill(ellipse(0, 0, 0.13, 0.17), with: .color(PandaPalette.limb))
    }

    /// Наушники: дуга — верх контура капсулы 0,58 × 0,30 (выше 0,20), чашки по бокам; жёлтые, при записи красные.
    static func drawHeadphones(_ base: GraphicsContext, _ color: Color) {
        let hp: GraphicsContext.Shading = .color(color)
        var arc: GraphicsContext = base
        arc.clip(to: Path(CGRect(x: 0, y: 0, width: 1, height: 0.20)))
        arc.stroke(capsule(0.5, 0.21, 0.58, 0.30), with: hp, lineWidth: 0.02)
        let left: CGRect = CGRect(x: 0.19, y: 0.255, width: 0.05, height: 0.11)
        let right: CGRect = CGRect(x: 0.76, y: 0.255, width: 0.05, height: 0.11)
        base.fill(Path(roundedRect: left, cornerRadius: 0.02), with: hp)
        base.fill(Path(roundedRect: right, cornerRadius: 0.02), with: hp)
    }

    /// z Z Z — по очереди загораются (в точках экрана: размер шрифта — от стороны s).
    static func drawZzz(_ base: GraphicsContext, _ s: CGFloat, time: Double, alpha: Double) {
        for i in 0..<3 {
            var c: GraphicsContext = base
            let k: Double = max(0, sin(time * 1.5 - Double(i) * 0.8))
            c.opacity = alpha * (0.25 + 0.75 * k)
            let fi: CGFloat = CGFloat(i)
            let size: CGFloat = s * (0.07 + 0.025 * fi)
            let x: CGFloat = s * (0.78 + 0.06 * fi)
            let y: CGFloat = s * (0.16 - 0.055 * fi)
            let t: Text = Text(i == 0 ? "z" : "Z")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundColor(PandaPalette.fur)
            c.draw(t, at: CGPoint(x: x, y: y))
        }
    }
}
