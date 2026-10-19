import SwiftUI

/// Выбор корневой ноты (тап по ROOT) — квинтовый круг: 12 секторов по часовой стрелке от C сверху
/// (C, G, D, A, E, B, F#, C#, G#, D#, A#, F); выбранная — жёлтая. В центре — тональность (нота и гамма), без кнопок.
/// Тап по сектору — нота (UNDO) и закрыть; тап мимо — закрыть.
struct RootWheel: View {
    let model: AppModel
    let anchor: CGRect
    let screen: CGSize
    @Environment(\.theme) private var theme

    static let side: CGFloat = 300

    var body: some View {
        let side: CGFloat = RootWheel.side + 24
        let x: CGFloat = min(max(8, anchor.midX - side / 2), screen.width - side - 8)
        let below: Bool = anchor.maxY + 6 + side < screen.height
        let y: CGFloat = below ? anchor.maxY + 6 : max(8, anchor.minY - 6 - side)
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.rootWheel = nil }
            wheel
                .frame(width: RootWheel.side, height: RootWheel.side)
                .padding(12)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .offset(x: x, y: y)
        }
    }

    private var wheel: some View {
        let root: Int = model.project.root
        let key: String = Params.noteNames[root] + " " + Scales.all[model.project.scale].short
        return ZStack {
            Canvas { ctx, size in draw(ctx, size, root) }
            Text(key).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: RootWheel.side * 0.36)
        }
        .contentShape(Circle())
        .gesture(SpatialTapGesture().onEnded { e in tap(e.location) })
    }

    /// Нота сектора k (квинта за квинтой от C).
    static func note(_ k: Int) -> Int {
        return (k * 7) % 12
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ root: Int) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer: CGFloat = min(size.width, size.height) / 2
        let inner: CGFloat = outer * 0.5
        let step: Double = Double.pi / 6
        for k in 0..<12 {
            let n: Int = RootWheel.note(k)
            let a0: Double = -Double.pi / 2 + (Double(k) - 0.5) * step
            let a1: Double = a0 + step
            var p = Path()
            p.addArc(center: c, radius: outer, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            p.addArc(center: c, radius: inner, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
            p.closeSubpath()
            let on: Bool = n == root
            ctx.fill(p, with: .color(on ? theme.accent : theme.panel2))
            ctx.stroke(p, with: .color(theme.bg), lineWidth: 3)
            let mid: Double = a0 + step / 2
            let r: CGFloat = (outer + inner) / 2
            let at = CGPoint(x: c.x + r * CGFloat(cos(mid)), y: c.y + r * CGFloat(sin(mid)))
            let label = SwiftUI.Text(Params.noteNames[n]).font(.system(size: 17, weight: .bold))
                .foregroundColor(on ? theme.onAccent : theme.text)
            ctx.draw(label, at: at, anchor: .center)
        }
        let hole = Path(ellipseIn: CGRect(x: c.x - inner * 0.8, y: c.y - inner * 0.8, width: inner * 1.6, height: inner * 1.6))
        ctx.fill(hole, with: .color(theme.panel))
    }

    /// Сектор под пальцем (в кольце) — нота; середина и углы — ничего.
    private func tap(_ p: CGPoint) {
        let half: CGFloat = RootWheel.side / 2
        let dx: Double = Double(p.x - half)
        let dy: Double = Double(p.y - half)
        let d: Double = (dx * dx + dy * dy).squareRoot()
        if d < Double(half) * 0.5 || d > Double(half) { return }
        // Угол от верха по часовой стрелке, 0…2π; сектор k — с центром на k·30°.
        var a: Double = atan2(dx, -dy)
        if a < 0 { a += 2 * Double.pi }
        let k: Int = Int((a / (Double.pi / 6)).rounded()) % 12
        model.rootWheel = nil
        model.setRoot(RootWheel.note(k))
    }
}
