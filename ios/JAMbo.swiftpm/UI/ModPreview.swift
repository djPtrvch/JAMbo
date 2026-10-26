import SwiftUI

// Миниатюры LFO1–3 и ENV в окне сэмпла (как renderLfo, renderEnv в sample.ts веба): пока держат MOD (отпустили —
// сразу гаснут). LFO — период формы с Polarity и Invert и точка на текущей фазе; ENV — форма ADSR (без ноты —
// условный гейт, видны все стадии; нота короче A+D — её настоящий гейт) и точка на кривой.

struct ModPreview: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    /// Шаги условного Random на миниатюре.
    static let randomSteps: [Double] = [0.6, -0.3, 0.9, -0.8, 0.2, -0.5, 0.75, -0.1]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let _ = RedrawMeter.hit(.modPreview)
            VStack(spacing: 4) {
                ForEach(1..<5, id: \.self) { n in mini(n, tl.date) }
            }
            .padding(6)
        }
    }

    /// date — кадр таймлайна: без него во входе Canvas не перерисовывается и точка стоит, пока не тронут ручки.
    private func mini(_ n: Int, _ date: Date) -> some View {
        let frame: Double = date.timeIntervalSinceReferenceDate
        let p: [String: Double] = model.track.params
        let t: Int = model.selectedTrack
        let title: String = n == 4 ? envTitle(p) : lfoTitle(p, n)
        let colors = ThumbColors(theme: theme)
        let lfoPhase: Double = n < 4 ? Double(model.audio.core.mod.phaseOuts[t * 3 + n - 1].load()) : 0
        let envT: Double = Double(model.audio.core.mod.envOuts[t * 2].load())
        let envG: Double = Double(model.audio.core.mod.envOuts[t * 2 + 1].load())
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(theme.dim).lineLimit(1)
            Canvas(rendersAsynchronously: true) { ctx, size in
                _ = frame
                if n < 4 {
                    ModPreview.drawLfo(ctx, size, p, n, lfoPhase, colors)
                } else {
                    ModPreview.drawEnv(ctx, size, p, envT, envG, colors)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func lfoTitle(_ p: [String: Double], _ n: Int) -> String {
        let w = Int((p["lfo\(n).wave"] ?? 0).rounded())
        let name: String = w >= 0 && w < Params.lfoWaves.count ? Params.lfoWaves[w] : ""
        return "LFO\(n) · \(name) · " + String(format: "%.2fHz", p["lfo\(n).speed"] ?? 0)
    }

    private func envTitle(_ p: [String: Double]) -> String {
        let a = Int((p["env.attack"] ?? 0).rounded()), d = Int((p["env.decay"] ?? 0).rounded())
        let s = Int((p["env.sustain"] ?? 0).rounded()), r = Int((p["env.release"] ?? 0).rounded())
        return "ENV · A\(a) D\(d) S\(s)% R\(r)"
    }

    static func lfoValue(_ p: [String: Double], _ n: Int, _ ph: Double) -> Double {
        let steps = randomSteps
        let rnd: Double = steps[Int(ph * Double(steps.count)) % steps.count]
        let s: Double = ModEngine.shape(Int((p["lfo\(n).wave"] ?? 0).rounded()), ph, rnd)
        let u: Double = p["lfo\(n).polar"] ?? 0
        return (s * (1 - u) + ((s + 1) / 2) * u) * (1 - 2 * (p["lfo\(n).invert"] ?? 0))
    }

    static func drawLfo(_ ctx: GraphicsContext, _ size: CGSize, _ p: [String: Double], _ n: Int, _ phase: Double,
                        _ c: ThumbColors) {
        let h: CGFloat = size.height
        func y(_ v: Double) -> CGFloat { return h / 2 - CGFloat(v) * (h / 2 - 3) }
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: h / 2))
        axis.addLine(to: CGPoint(x: size.width, y: h / 2))
        ctx.stroke(axis, with: .color(c.off), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        var path = Path()
        let points = 100
        for i in 0...points {
            let ph: Double = Swift.min(Double(i) / Double(points), 0.9999)
            let pt = CGPoint(x: CGFloat(Double(i) / Double(points)) * size.width, y: y(lfoValue(p, n, ph)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(c.text), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        let dot = CGPoint(x: CGFloat(phase) * size.width, y: y(lfoValue(p, n, phase)))
        ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(c.accent))
    }

    static func envShape(_ p: [String: Double], _ x: Double, _ gate: Double) -> Double {
        let a = p["env.attack"] ?? 10, d = p["env.decay"] ?? 100, s = (p["env.sustain"] ?? 40) / 100
        let r = p["env.release"] ?? 300
        func ads(_ y: Double) -> Double { return y < a ? y / a : (y < a + d ? 1 - (1 - s) * (y - a) / d : s) }
        if x < 0 { return 0 }
        if x < gate { return ads(x) }
        let rel = x - gate
        return rel < r ? ads(gate) * (1 - rel / r) : 0
    }

    static func drawEnv(_ ctx: GraphicsContext, _ size: CGSize, _ p: [String: Double], _ t: Double, _ g: Double,
                        _ c: ThumbColors) {
        let a = p["env.attack"] ?? 10, d = p["env.decay"] ?? 100, r = p["env.release"] ?? 300
        let ad = a + d
        let gate: Double = t >= 0 && g < ad ? g : ad + Swift.max(200, (ad + r) * 0.3)
        let total: Double = gate + r
        let h: CGFloat = size.height
        func y(_ v: Double) -> CGFloat { return h - 3 - CGFloat(v) * (h - 6) }
        var path = Path()
        let points = 100
        for i in 0...points {
            let x: Double = Double(i) / Double(points) * total
            let pt = CGPoint(x: CGFloat(Double(i) / Double(points)) * size.width, y: y(envShape(p, x, gate)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(c.text), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        var x: Double = 0
        if t >= 0 { x = t < g ? Swift.min(gate, t) : gate + Swift.min(r, t - g) }
        let dot = CGPoint(x: CGFloat(x / total) * size.width, y: y(envShape(p, x, gate)))
        ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(c.accent))
    }
}
