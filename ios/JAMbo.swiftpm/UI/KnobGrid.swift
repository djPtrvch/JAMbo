import SwiftUI

/// Сетка ручек 4×4: палец вверх-вниз (240 px — весь ход), мультитач. С зажатым шагом — p-lock (жёлтый),
/// двойной тап с зажатым шагом — снять p-lock, SHIFT + двойной тап — снять все p-lock дорожки.
struct KnobGrid: View {
    let model: AppModel
    @State private var turns: [SpatialEventCollection.Event.ID: KnobTurn] = [:]
    @State private var lastTap: [Int: Date] = [:]

    static let travel: CGFloat = 240
    static let dead: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { col in
                            KnobView(state: model.knobState(row * 4 + col))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(touches(size: geo.size))
        }
    }

    private func slot(_ p: CGPoint, size: CGSize) -> Int {
        let col: Int = min(3, max(0, Int(p.x / (size.width / 4))))
        let row: Int = min(3, max(0, Int(p.y / (size.height / 4))))
        return row * 4 + col
    }

    private func touches(size: CGSize) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    switch e.phase {
                    case .active:
                        if turns[e.id] == nil { down(e.id, at: e.location, size: size) } else { move(e.id, y: e.location.y) }
                    case .ended, .cancelled:
                        up(e.id)
                    @unknown default:
                        break
                    }
                }
            }
            .onEnded { events in
                for e in events { up(e.id) }
            }
    }

    private func down(_ id: SpatialEventCollection.Event.ID, at p: CGPoint, size: CGSize) {
        model.ensureAudio()
        let s: Int = slot(p, size: size)
        var turn = KnobTurn(slot: s, startY: p.y, lastY: p.y, acc: model.knobStart(s))
        if let t = lastTap[s], Date().timeIntervalSince(t) < 0.35 {
            lastTap[s] = nil
            model.knobDoubleTap(s)
            turn.consumed = true
        } else {
            lastTap[s] = Date()
        }
        // С зажатой SHIFT ручки не крутятся.
        if model.shiftHeld { turn.consumed = true }
        turns[id] = turn
        model.beginGesture()
    }

    private func move(_ id: SpatialEventCollection.Event.ID, y: CGFloat) {
        guard var t = turns[id], !t.consumed else { return }
        if !t.moved {
            if abs(y - t.startY) < KnobGrid.dead { return }
            t.moved = true
            t.lastY = y
            turns[id] = t
            return
        }
        let d: Double = Double((t.lastY - y) / KnobGrid.travel)
        t.lastY = y
        t.acc = min(1, max(0, t.acc + d))
        turns[id] = t
        model.setKnob(t.slot, norm: t.acc)
    }

    private func up(_ id: SpatialEventCollection.Event.ID) {
        guard turns.removeValue(forKey: id) != nil else { return }
        model.endGesture()
    }
}

/// Поворот ручки одним пальцем.
struct KnobTurn {
    let slot: Int
    let startY: CGFloat
    var lastY: CGFloat
    /// Накопитель положения 0…1.
    var acc: Double
    var moved: Bool = false
    var consumed: Bool = false
}

/// Ручка: кольцо (серое), дуга значения (белая; у двухполярных — от центра), p-lock — жёлтая дуга внутри
/// и жёлтая стрелка, значение в центре, подпись под ручкой. Геометрия как в вебе (поле 100×100).
struct KnobView: View {
    let state: KnobState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Canvas { ctx, size in draw(ctx, size) }
                valueText
            }
            Text(state.param?.label ?? "")
                .font(.system(size: 11))
                .foregroundStyle(theme.dim)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var valueText: some View {
        let text: String = state.param.map { $0.format(state.value) } ?? ""
        return Text(text)
            .font(.system(size: 11))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .foregroundStyle(state.locked ? theme.accent : theme.text)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let side: CGFloat = min(size.width, size.height)
        let k: CGFloat = side / 100
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let active: Bool = state.param != nil
        ctx.stroke(KnobView.arc(c, 36 * k, 0, 1), with: .color(active ? theme.off : theme.panel),
                   style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
        let cap = Path(ellipseIn: CGRect(x: c.x - 24 * k, y: c.y - 24 * k, width: 48 * k, height: 48 * k))
        ctx.fill(cap, with: .color(active ? theme.panel2 : theme.panel))
        guard let p = state.param else { return }
        let origin: Double = p.bipolar ? 0.5 : 0
        ctx.stroke(KnobView.arc(c, 36 * k, origin, state.baseNorm), with: .color(theme.text),
                   style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
        if state.locked {
            ctx.stroke(KnobView.arc(c, 28 * k, origin, state.norm), with: .color(theme.accent),
                       style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
        }
        let a: Double = KnobView.angle(state.norm)
        var pointer = Path()
        pointer.move(to: KnobView.polar(c, 21 * k, a))
        pointer.addLine(to: KnobView.polar(c, 28 * k, a))
        ctx.stroke(pointer, with: .color(state.locked ? theme.accent : theme.text),
                   style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
    }

    /// Угол положения n (0…1): от −135° до +135° (0° — вверх), в радианах для CGPoint.
    static func angle(_ n: Double) -> Double {
        return (-135 + 270 * n - 90) * Double.pi / 180
    }

    static func polar(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint {
        return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
    }

    static func arc(_ c: CGPoint, _ r: CGFloat, _ n0: Double, _ n1: Double) -> Path {
        var path = Path()
        if abs(n1 - n0) < 0.002 { return path }
        let a0: Double = angle(min(n0, n1))
        let a1: Double = angle(max(n0, n1))
        path.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        return path
    }
}
