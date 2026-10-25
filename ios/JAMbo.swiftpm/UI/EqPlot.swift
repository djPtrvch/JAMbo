import SwiftUI

/// Координаты поля EQ (как в src/ui/eq.ts): частота low — 20 кГц логарифмически по ширине, усиление ±21 dB на
/// всю высоту. Поле EQ — от 10 Гц (viewLow; полосы — от 20 Гц, срез у нижней точки виден слева), окно SAT — от 20 Гц.
struct EqGeometry {
    static let dbRange: Double = 21
    static let viewLow: Double = 10
    let size: CGSize
    var low: Double = EqSpec.freqMin

    var octaves: Double { return log2(EqSpec.freqMax / low) }

    func x(_ f: Double) -> CGFloat {
        let u: Double = log2(f / low) / octaves
        return size.width * CGFloat(u)
    }

    func freq(_ x: CGFloat) -> Double {
        let u: Double = Double(x / max(1, size.width))
        return low * pow(2, u * octaves)
    }

    func y(_ g: Double) -> CGFloat {
        let half: CGFloat = size.height / 2
        let u: CGFloat = CGFloat(g / EqGeometry.dbRange)
        return half - u * half
    }

    func gain(_ y: CGFloat) -> Double {
        let half: CGFloat = max(1, size.height / 2)
        let u: Double = Double((half - y) / half)
        return u * EqGeometry.dbRange
    }

    /// Точка полосы: у cut и notch — на 0 dB.
    func point(_ b: EqBand) -> CGPoint {
        return CGPoint(x: x(b.freq), y: y(EqSpec.hasGain(b.type) ? b.gain : 0))
    }
}

/// Палец на поле EQ: начало, где сейчас, полоса (−1 — пустое место) и её значения в начале, сдвинулся ли, открыл ли меню.
struct EqTouch {
    var start: CGPoint
    var at: CGPoint
    var band: Int = -1
    var f0: Double = 0
    var g0: Double = 0
    var moved: Bool = false
    var menu: Bool = false
    /// Палец слушает полосу (SHIFT при касании): без меню удержания и двойного тапа.
    var listen: Bool = false
}

/// Поле EQ: сетка, суммарная кривая, точки полос; мультитач (две точки сразу). Двойной тап по пустому месту — новая
/// bell-полоса; точку тянут (у cut и notch — только частота); двойной тап по точке — удалить (решение пользователя; в
/// вебе — вкл./выкл., здесь оно в меню); удержание — меню типа, крутизны, ON/OFF, DELETE. Над пальцем, который держит точку, — частота (Гц и нота), усиление, Q. Под кривой —
/// спектры (EqSpectrumLayer).
/// Кривые EQ на экране (координаты y через 2 px) и какие из них рисовать.
struct EqCurves {
    var stereo: [CGFloat] = []
    var mid: [CGFloat] = []
    var side: [CGFloat] = []
    var hasStereo: Bool = false
    var hasMid: Bool = false
    var hasSide: Bool = false
}

struct EqPlot: View {
    static let hitR: CGFloat = 24
    static let moveTol: CGFloat = 8
    static let hold: Double = 0.5
    static let doubleTap: Double = 0.32
    let model: AppModel
    @State private var touches: [SpatialEventCollection.Event.ID: EqTouch] = [:]
    /// Пальцы, снятые при открытии меню удержанием: их дальнейшие события не считаются.
    @State private var dropped: Set<SpatialEventCollection.Event.ID> = []
    @State private var lastTap: (at: Date, p: CGPoint, band: Int)? = nil
    @State private var frame: CGRect = .zero
    @State private var spectrum = SpectrumDisplay()
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let g = EqGeometry(size: geo.size, low: EqGeometry.viewLow)
            let eq: Eq = model.eqTarget
            ZStack(alignment: .topLeading) {
                EqSpectrumLayer(model: model, display: spectrum)
                // Динамические полосы: точки и кривая — с текущим сдвигом, 30 кадров в секунду (без них — пауза).
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.eqHasDyn)) { _ in
                    let offs: [Double] = model.eqDynOffsets()
                    let curves: EqCurves = EqPlot.curves(eq, g, offs)
                    Canvas { ctx, _ in
                        drawGrid(ctx, g)
                        if let b = eq.band(model.eqListenBand) { drawListen(ctx, b, g) }
                        drawCurves(ctx, curves, on: eq.on)
                        drawPoints(ctx, eq, g, offs)
                    }
                }
                tips(eq, g)
            }
            .contentShape(Rectangle())
            .gesture(touch(g))
            // Пока открыто меню (полосы, COMPARE), касания — только ему: тап по пункту не доходит до точек.
            .allowsHitTesting(model.eqMenu == nil && !model.eqCompareMenu && model.eqMsMenu == nil && model.eqDynMenu == nil
                              && model.eqPresetMenu == nil)
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
    }

    /// Суммарные кривые включённых полос через 2 px (как в вебе): стерео-полосы, середина (стерео + MID), бока
    /// (стерео + SIDE); у динамических полос — усиление со сдвигом offs (dB по полосам).
    static func curves(_ eq: Eq, _ g: EqGeometry, _ offs: [Double]) -> EqCurves {
        let n: Int = Int(g.size.width / 2) + 1
        let freqs: [Double] = (0..<n).map { min(24000, g.freq(CGFloat($0) * 2)) }
        var st = [Double](repeating: 0, count: n)
        var mid = [Double](repeating: 0, count: n)
        var side = [Double](repeating: 0, count: n)
        var out = EqCurves()
        for k in 0..<eq.bands.count {
            guard var b = eq.bands[k], b.on else { continue }
            if k < offs.count && offs[k] != 0 { b.gain += offs[k] }
            let r: [Double] = EqCoeffs.response(b, hz: freqs)
            let ms: Int = b.ms
            if ms == 0 { out.hasStereo = true }
            if ms == 1 { out.hasMid = true }
            if ms == 2 { out.hasSide = true }
            for i in 0..<n {
                if ms == 0 { st[i] += r[i] }
                if ms != 2 { mid[i] += r[i] }
                if ms != 1 { side[i] += r[i] }
            }
        }
        let lim: Double = EqGeometry.dbRange * 1.2
        out.stereo = st.map { g.y(max(-lim, min(lim, $0))) }
        if out.hasMid { out.mid = mid.map { g.y(max(-lim, min(lim, $0))) } }
        if out.hasSide { out.side = side.map { g.y(max(-lim, min(lim, $0))) } }
        return out
    }

    // MARK: — отрисовка

    private func drawGrid(_ ctx: GraphicsContext, _ g: EqGeometry) {
        var d: Double = 10
        while d <= 10000 {
            for m in 1...9 {
                let f: Double = d * Double(m)
                if f < g.low || f > EqSpec.freqMax { continue }
                let x: CGFloat = g.x(f).rounded() + 0.5
                let p = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: g.size.height)) }
                ctx.stroke(p, with: .color(m == 1 ? theme.gridStrong : theme.grid), lineWidth: 1)
            }
            d *= 10
        }
        for db in stride(from: -18, through: 18, by: 6) {
            let y: CGFloat = g.y(Double(db)).rounded() + 0.5
            let p = Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: g.size.width, y: y)) }
            ctx.stroke(p, with: .color(db == 0 ? theme.gridStrong : theme.grid), lineWidth: 1)
        }
        for (f, s) in [(100.0, "100 Hz"), (1000.0, "1 kHz"), (10000.0, "10 kHz")] {
            ctx.draw(label(s), at: CGPoint(x: g.x(f) + 4, y: g.size.height - 4), anchor: .bottomLeading)
        }
        for db in [12, 0, -12] {
            ctx.draw(label(db > 0 ? "+\(db) dB" : "\(db) dB"), at: CGPoint(x: 6, y: g.y(Double(db)) - 8), anchor: .leading)
        }
    }

    /// Область прослушиваемой полосы: АЧХ фильтра EqListen жёлтой полупрозрачной заливкой (0 dB — верх поля,
    /// −30 dB — низ).
    private func drawListen(_ ctx: GraphicsContext, _ b: EqBand, _ g: EqGeometry) {
        let n: Int = Int(g.size.width / 2) + 1
        let freqs: [Double] = (0..<n).map { min(24000, g.freq(CGFloat($0) * 2)) }
        let r: [Double] = EqListen.response(b, hz: freqs)
        let h: CGFloat = g.size.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        for i in 0..<n {
            let u: Double = max(0, min(1, -r[i] / 30))
            p.addLine(to: CGPoint(x: CGFloat(i) * 2, y: h * CGFloat(u)))
        }
        p.addLine(to: CGPoint(x: CGFloat(n - 1) * 2, y: h))
        p.closeSubpath()
        ctx.fill(p, with: .color(theme.accent.opacity(0.16)))
    }

    private func label(_ s: String) -> Text {
        return Text(s).font(.system(size: 11)).foregroundColor(theme.dim)
    }

    /// Белая — стерео-полосы (и когда полос MID/SIDE нет); середина — красная, бока — оранжевая.
    private func drawCurves(_ ctx: GraphicsContext, _ c: EqCurves, on: Bool) {
        let a: Double = on ? 1 : 0.35
        if c.hasStereo || (!c.hasMid && !c.hasSide) { drawCurve(ctx, c.stereo, theme.text.opacity(a)) }
        if c.hasMid { drawCurve(ctx, c.mid, theme.rec.opacity(a)) }
        if c.hasSide { drawCurve(ctx, c.side, theme.gr.opacity(a)) }
    }

    private func drawCurve(_ ctx: GraphicsContext, _ ys: [CGFloat], _ color: Color) {
        guard let first = ys.first else { return }
        var p = Path()
        p.move(to: CGPoint(x: 0, y: first))
        for i in 1..<ys.count { p.addLine(to: CGPoint(x: CGFloat(i) * 2, y: ys[i])) }
        ctx.stroke(p, with: .color(color), lineWidth: 2)
    }

    /// Цвет точки по режиму: STEREO — белая, MID — красная, SIDE — оранжевая.
    private func msColor(_ b: EqBand) -> Color {
        return b.ms == 1 ? theme.rec : (b.ms == 2 ? theme.gr : theme.text)
    }

    /// Точки: цвета режима M/S с номерами, выбранная крупнее и жёлтая (MID/SIDE — с кольцом цвета режима),
    /// выключенные серые; динамическая — с текущим сдвигом, на месте статического усиления — полое кольцо.
    private func drawPoints(_ ctx: GraphicsContext, _ eq: Eq, _ g: EqGeometry, _ offs: [Double]) {
        for k in 0..<eq.bands.count {
            guard let b = eq.bands[k] else { continue }
            let sel: Bool = k == model.eqBand
            let r: CGFloat = sel ? 13 : 10
            var moved: EqBand = b
            if k < offs.count { moved.gain += offs[k] }
            let c: CGPoint = g.point(moved)
            if b.on && EqSpec.dynOn(b) {
                let p0: CGPoint = g.point(b)
                let rr: CGFloat = r - 1
                let ring = Path(ellipseIn: CGRect(x: p0.x - rr, y: p0.y - rr, width: 2 * rr, height: 2 * rr))
                ctx.stroke(ring, with: .color(msColor(b).opacity(0.7)), lineWidth: 1.5)
            }
            let fill: Color = !b.on ? theme.muteGrey : (sel ? theme.accent : msColor(b))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(fill))
            if sel && b.on && b.ms > 0 {
                let rr: CGFloat = r + 2.5
                let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
                ctx.stroke(ring, with: .color(msColor(b)), lineWidth: 3)
            }
            let num: Text = Text("\(k + 1)").font(.system(size: sel ? 13 : 11, weight: .semibold))
                .foregroundColor(sel ? theme.onAccent : theme.bg)
            ctx.draw(num, at: CGPoint(x: c.x, y: c.y + 0.5), anchor: .center)
        }
    }

    /// Центр подсказки: над пальцем, не за краями поля.
    static func tipCenter(_ p: CGPoint, _ g: EqGeometry) -> CGPoint {
        let x: CGFloat = max(60, min(g.size.width - 60, p.x))
        let y: CGFloat = max(26, p.y - 68)
        return CGPoint(x: x, y: y)
    }

    /// Подсказки над пальцами, которые держат точки.
    @ViewBuilder
    private func tips(_ eq: Eq, _ g: EqGeometry) -> some View {
        let held: [EqTouch] = touches.values.filter { $0.band >= 0 && !$0.menu }
        ForEach(0..<held.count, id: \.self) { i in
            if let b = eq.band(held[i].band) {
                EqTip(band: b)
                    .position(EqPlot.tipCenter(held[i].at, g))
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Подсказка над пальцем: частота · нота, усиление · Q.
struct EqTip: View {
    let band: EqBand
    @Environment(\.theme) private var theme

    var body: some View {
        let gain: String = EqSpec.hasGain(band.type) ? EqFormat.gain(band.gain) : "—"
        return Text("\(EqFormat.hz(band.freq)) · \(EqFormat.note(band.freq))\n\(gain) · Q \(String(format: "%.2f", band.q))")
            .font(.system(size: 13)).monospacedDigit()
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .foregroundStyle(theme.text)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(theme.panel2, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            .fixedSize()
    }
}

extension EqPlot {
    private func touch(_ g: EqGeometry) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    if dropped.contains(e.id) {
                        if e.phase != .active { dropped.remove(e.id) }
                        continue
                    }
                    switch e.phase {
                    case .active:
                        if touches[e.id] == nil { down(e.id, e.location, g) } else { move(e.id, e.location, g) }
                    case .ended:
                        up(e.id, e.location, g, tap: true)
                    case .cancelled:
                        up(e.id, e.location, g, tap: false)
                    @unknown default:
                        break
                    }
                }
            }
            .onEnded { events in
                for e in events {
                    if dropped.remove(e.id) != nil { continue }
                    up(e.id, e.location, g, tap: e.phase != .cancelled)
                }
            }
    }

    /// Ближайшая точка в зоне касания (выбранная — в приоритете).
    private func hit(_ p: CGPoint, _ g: EqGeometry) -> Int {
        var best: Int = -1
        var bestD: CGFloat = EqPlot.hitR
        let eq: Eq = model.eqTarget
        for k in 0..<eq.bands.count {
            guard let b = eq.bands[k] else { continue }
            let c: CGPoint = g.point(b)
            let bias: CGFloat = k == model.eqBand ? 6 : 0
            let d: CGFloat = hypot(c.x - p.x, c.y - p.y) - bias
            if d < bestD {
                bestD = d
                best = k
            }
        }
        return best
    }

    private func down(_ id: SpatialEventCollection.Event.ID, _ p: CGPoint, _ g: EqGeometry) {
        model.ensureAudio()
        model.eqMenu = nil
        var t = EqTouch(start: p, at: p)
        let k: Int = hit(p, g)
        // Одну точку держит один палец.
        if k >= 0, !touches.values.contains(where: { $0.band == k }), let b = model.eqTarget.band(k) {
            t.band = k
            t.f0 = b.freq
            t.g0 = b.gain
            model.eqBand = k
            model.beginGesture()
            if model.shiftHeld && model.eqListenBand < 0 {
                t.listen = true
                model.startEqListen(k)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(EqPlot.hold * 1e9))
                guard let cur = touches[id], !cur.moved, !cur.listen, cur.band == k else { return }
                openMenu(k, at: cur.at)
            }
        }
        touches[id] = t
    }

    private func move(_ id: SpatialEventCollection.Event.ID, _ p: CGPoint, _ g: EqGeometry) {
        guard var t = touches[id] else { return }
        t.at = p
        if !t.moved && hypot(p.x - t.start.x, p.y - t.start.y) > EqPlot.moveTol { t.moved = true }
        touches[id] = t
        guard t.band >= 0, !t.menu, t.moved, let b = model.eqTarget.band(t.band) else { return }
        let dx: Double = Double((p.x - t.start.x) / max(1, g.size.width))
        let f: Double = t.f0 * pow(2, dx * g.octaves)
        if EqSpec.hasGain(b.type) {
            model.setEqBand(t.band, freq: f, gain: t.g0 + g.gain(p.y) - g.gain(t.start.y))
        } else {
            model.setEqBand(t.band, freq: f)
        }
        if t.listen { model.syncEqListen() }
    }

    /// Меню полосы (удержание): все пальцы снимаются сразу (жесты UNDO закрываются) — поле до закрытия меню касаний не
    /// получает, и конца касания может не прийти.
    private func openMenu(_ k: Int, at p: CGPoint) {
        for (id, t) in touches {
            if t.band >= 0 { model.endGesture() }
            if t.listen { model.stopEqListen() }
            dropped.insert(id)
        }
        touches.removeAll()
        lastTap = nil
        let anchor = CGPoint(x: frame.minX + p.x, y: frame.minY + p.y)
        model.eqMenu = EqMenuState(band: k, anchor: anchor, bounds: frame)
    }

    private func up(_ id: SpatialEventCollection.Event.ID, _ p: CGPoint, _ g: EqGeometry, tap: Bool) {
        guard let t = touches.removeValue(forKey: id) else { return }
        if t.band >= 0 { model.endGesture() }
        if t.listen { model.stopEqListen() }
        if t.moved || t.menu || t.listen || !tap { return }
        let now = Date()
        if let l = lastTap, now.timeIntervalSince(l.at) < EqPlot.doubleTap, hypot(l.p.x - t.start.x, l.p.y - t.start.y) < 30,
           l.band == t.band {
            if t.band >= 0 {
                model.deleteEqBand(t.band)
            } else {
                model.addEqBand(freq: g.freq(t.start.x), gain: g.gain(t.start.y))
            }
            lastTap = nil
        } else {
            lastTap = (now, t.start, t.band)
        }
    }
}
