import SwiftUI

/// Сетка ручек 4×4: палец вверх-вниз (240 px — весь ход), мультитач. С зажатым шагом — p-lock (жёлтый),
/// двойной тап с зажатым шагом — снять p-lock, SHIFT + двойной тап — снять все p-lock дорожки.
/// MST: параметры мастера (без p-lock). MIX: громкости дорожек (с зажатым шагом — p-lock на шагах MIX); справа от
/// ручки — M, S, ● (стем — S11); двойной тап — меню дорожки (по серой — ADD TRACK), с зажатым шагом — снять p-lock;
/// удержание ручки 0,5 с без движения и протягивание — перестановка дорожек.
struct KnobGrid: View {
    let model: AppModel
    @State private var turns: [SpatialEventCollection.Event.ID: KnobTurn] = [:]
    @State private var lastTap: [Int: Date] = [:]
    @State private var lift: TrackLift? = nil
    @State private var gridSize: CGSize = .zero

    static let travel: CGFloat = 240
    static let dead: CGFloat = 4
    static let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                cells(geo.size)
                    .contentShape(Rectangle())
                    .gesture(touches(size: geo.size))
                TrackMenus(model: model, size: geo.size)
            }
        }
    }

    private func cells(_ size: CGSize) -> some View {
        let mix: Bool = model.channel == .mix
        return VStack(spacing: KnobGrid.spacing) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: KnobGrid.spacing) {
                    ForEach(0..<4, id: \.self) { col in
                        let k: Int = row * 4 + col
                        if mix {
                            MixCell(model: model, slot: k)
                                .midiMarks(model, [model.midiLearn.press ? .press(k) : .knob(k)])
                                .offset(liftOffset(k, size))
                                .scaleEffect(lift?.from == k ? 1.12 : 1)
                                .zIndex(lift?.from == k ? 1 : 0)
                                .animation(.easeOut(duration: 0.15), value: lift?.to)
                        } else {
                            KnobCell(model: model, slot: k).midiMarks(model, [model.midiLearn.press ? .press(k) : .knob(k)])
                        }
                    }
                }
            }
        }
    }

    /// Центр ручки k (ряд за рядом).
    static func center(_ k: Int, _ size: CGSize) -> CGPoint {
        let cw: CGFloat = (size.width + spacing) / 4
        let ch: CGFloat = (size.height + spacing) / 4
        return CGPoint(x: (CGFloat(k % 4) + 0.5) * cw, y: (CGFloat(k / 4) + 0.5) * ch)
    }

    /// Перестановка: поднятая ручка — за пальцем, ручки между старым и новым местом — на место соседа.
    private func liftOffset(_ k: Int, _ size: CGSize) -> CGSize {
        guard let l = lift else { return .zero }
        if k == l.from { return CGSize(width: l.cur.x - l.start.x, height: l.cur.y - l.start.y) }
        let p: Int
        if l.from < l.to {
            p = k > l.from && k <= l.to ? k - 1 : k
        } else {
            p = k >= l.to && k < l.from ? k + 1 : k
        }
        if p == k { return .zero }
        let c = KnobGrid.center(k, size)
        let t = KnobGrid.center(p, size)
        return CGSize(width: t.x - c.x, height: t.y - c.y)
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
                        if turns[e.id] == nil { down(e.id, at: e.location, size: size) } else { move(e.id, at: e.location) }
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
        gridSize = size
        let s: Int = slot(p, size: size)
        var turn = KnobTurn(slot: s, startY: p.y, lastY: p.y, acc: model.knobStart(s))
        // MIDI LEARN: тап выбирает цель — ручку (TURN / PRESS) или кнопку M, S, ● в MIX; действие не выполняется.
        if model.midiLearn.on {
            if model.channel == .mix, let b = MixLayout.button(at: p, slot: s, size: size) {
                let names: [String] = ["MUTE", "SOLO", "ARM"]
                model.learnTap(.button("\(names[b]) \(s + 1)"))
            } else {
                model.learnKnob(s)
            }
            turn.consumed = true
            turns[id] = turn
            model.beginGesture()
            return
        }
        // MIX: кнопки M, S, ● справа от ручки — тап сразу.
        if model.channel == .mix, let b = MixLayout.button(at: p, slot: s, size: size), s < model.project.tracks.count {
            if b == 0 { model.toggleMute(s) }
            if b == 1 { model.toggleSolo(s) }
            if b == 2 { model.stemTap(s) }
            turn.consumed = true
            turns[id] = turn
            model.beginGesture()
            return
        }
        if let t = lastTap[s], Date().timeIntervalSince(t) < 0.35 {
            lastTap[s] = nil
            // SHIFT + двойной тап снимает p-lock: синхронизацию, переключённую первым тапом, — обратно.
            if model.shiftHeld { model.knobShiftTap(s) }
            if model.heldSteps.isEmpty && model.canAssign, let src = model.heldSource {
                model.clearAssign(s, lfo: src)
            } else {
                model.knobDoubleTap(s)
            }
            turn.consumed = true
        } else {
            lastTap[s] = Date()
            // SHIFT + тап по Dly Time или Speed LFO — по темпу / свободно.
            if model.shiftHeld { model.knobShiftTap(s) }
        }
        // С зажатой SHIFT ручки не крутятся.
        if model.shiftHeld { turn.consumed = true }
        // Удерживаемый LFO/ENV (без зажатого шага) — степень назначения −1…+1.
        if model.heldSteps.isEmpty && model.canAssign, let src = model.heldSource {
            turn.lfo = src
            let a = model.assign(s)
            turn.acc = a?.lfo == src ? a!.amount : 0
        }
        if model.channel != .mix { model.knobFingers.insert(s) }
        turns[id] = turn
        model.beginGesture()
        // С зажатым шагом ручка ставит p-lock — перестановки дорожек нет.
        if model.channel == .mix && s < model.project.tracks.count && !turn.consumed && model.heldSteps.isEmpty {
            armLift(id, s, p)
        }
    }

    /// Удержание ручки громкости 0,5 с без движения — она поднимается (перестановка дорожек).
    private func armLift(_ id: SpatialEventCollection.Event.ID, _ s: Int, _ p: CGPoint) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard var t = turns[id], !t.moved, !t.consumed, lift == nil else { return }
            t.consumed = true
            turns[id] = t
            lift = TrackLift(id: id, from: s, to: s, start: p, cur: p)
        }
    }

    private func move(_ id: SpatialEventCollection.Event.ID, at p: CGPoint) {
        if var l = lift, l.id == id {
            l.cur = p
            l.to = nearestTrack(p)
            lift = l
            return
        }
        let y: CGFloat = p.y
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
        if let src = t.lfo {
            t.acc = min(1, max(-1, t.acc + d))
            turns[id] = t
            model.setAssign(t.slot, lfo: src, amount: t.acc)
            return
        }
        t.acc = min(1, max(0, t.acc + d))
        turns[id] = t
        model.setKnob(t.slot, norm: t.acc)
    }

    /// Место для дорожки — ближайшая к пальцу ручка существующей дорожки.
    private func nearestTrack(_ p: CGPoint) -> Int {
        var best = 0
        var bd = CGFloat.greatestFiniteMagnitude
        for k in 0..<min(16, model.project.tracks.count) {
            let c = KnobGrid.center(k, gridSize)
            let d: CGFloat = (c.x - p.x) * (c.x - p.x) + (c.y - p.y) * (c.y - p.y)
            if d < bd {
                bd = d
                best = k
            }
        }
        return best
    }

    private func up(_ id: SpatialEventCollection.Event.ID) {
        guard let turn = turns.removeValue(forKey: id) else { return }
        if !turns.values.contains(where: { $0.slot == turn.slot }) { model.knobFingers.remove(turn.slot) }
        model.endGesture()
        if let l = lift, l.id == id {
            lift = nil
            if l.to != l.from { model.moveTrack(l.from, l.to) }
        }
    }
}

/// Поднятая ручка громкости (перестановка дорожек в MIX).
struct TrackLift {
    let id: SpatialEventCollection.Event.ID
    let from: Int
    var to: Int
    let start: CGPoint
    var cur: CGPoint
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
    /// Назначение источника (1–4): накопитель — степень −1…+1.
    var lfo: Int? = nil
}

/// Ручка сетки: с назначенным LFO/ENV — перерисовка каждый кадр (кольцо модуляции идёт за источником).
struct KnobCell: View {
    let model: AppModel
    let slot: Int

    var body: some View {
        let st: KnobState = model.knobState(slot)
        return Group {
            if st.assign != nil {
                TimelineView(.animation) { _ in KnobView(state: st, mod: model.modulatedNorm(st)) }
            } else {
                KnobView(state: st)
            }
        }
    }
}

/// Ручка: кольцо (серое), дуга значения (белая; у двухполярных — от центра), p-lock — жёлтая дуга внутри
/// и жёлтая стрелка, значение в центре, подпись под ручкой; LFO/ENV — кольцо снаружи от значения до текущего
/// (LFO1–3 — своя прозрачность, ENV — пунктир), пока держат источник — вся зона воздействия. Геометрия как в вебе.
struct KnobView: View {
    let state: KnobState
    /// Положение с модуляцией (0…1); nil — без назначения.
    var mod: Double? = nil
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
        var text: String = state.param.map { $0.format(state.value) } ?? ""
        if let p = state.param, let a = state.assign {
            if let h = state.heldSource, h == a.lfo {
                let pct = Int((a.amount * 100).rounded())
                text = (h == 4 ? "ENV" : "L\(h)") + " " + (pct > 0 ? "+" : "") + "\(pct)%"
            } else if let m = mod {
                text = p.format(p.fromNorm(m))
            }
        }
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
        if let am = state.assign {
            drawMod(ctx, c, k, am)
        }
        let a: Double = KnobView.angle(mod ?? state.norm)
        var pointer = Path()
        pointer.move(to: KnobView.polar(c, 21 * k, a))
        pointer.addLine(to: KnobView.polar(c, 28 * k, a))
        ctx.stroke(pointer, with: .color(state.locked ? theme.accent : theme.text),
                   style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
    }

    /// Кольцо модуляции (r 45) от значения до текущего; зона воздействия — пока держат этот источник.
    private func drawMod(_ ctx: GraphicsContext, _ c: CGPoint, _ k: CGFloat, _ am: ModAssign) {
        let n: Double = state.norm
        if let h = state.heldSource, h == am.lfo {
            let op: Double = h == 1 ? 0.18 : (h == 2 ? 0.09 : 0.12)
            let r: Path = KnobView.arc(c, 45 * k, Swift.max(0, n - abs(am.amount)), Swift.min(1, n + abs(am.amount)))
            ctx.stroke(r, with: .color(theme.text.opacity(op)), style: StrokeStyle(lineWidth: 8 * k))
        }
        guard let m = mod else { return }
        let ops: [Double] = [0.95, 0.4, 0.65, 0.85]
        let op: Double = ops[Swift.max(0, Swift.min(3, am.lfo - 1))]
        let style: StrokeStyle = am.lfo == 4
            ? StrokeStyle(lineWidth: 4 * k, lineCap: .butt, dash: [3 * k, 3 * k])
            : StrokeStyle(lineWidth: 4 * k, lineCap: .round)
        ctx.stroke(KnobView.arc(c, 45 * k, n, m), with: .color(theme.text.opacity(op)), style: style)
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
