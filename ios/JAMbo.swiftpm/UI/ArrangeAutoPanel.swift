import SwiftUI

/// Окно AUTO аранжировщика (S15f2, решения пользователя): на месте строки дорожек, секвенсора и клавиатуры. Слева, под
/// заголовками дорожек, — 16 ячеек ручек сетки выбранной дорожки (4 × 4, как сетка ручек); справа, под таймлайном, —
/// кривая выбранной ручки в том же масштабе и прокрутке. Тап по ячейке — её кривая; двойной тап по ячейке с кривой —
/// CLEAR. В поле кривой: тап — точка, сдвиг точки — двигать, двойной тап по точке — удалить; сдвиг по пустому —
/// прокрутка, два пальца — масштаб по времени.
struct ArrAutoPanel: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ArrAutoCells(model: model)
                .padding(.trailing, Layout.gap)
                .frame(width: ArrMetrics.headerW)
            ArrAutoCurve(model: model)
            // Место измерителя справа — как у окна аранжировщика (поле кривой ровно под таймлайном).
            Color.clear.frame(width: Layout.meterWidth).padding(.leading, Layout.gap)
        }
        .background(theme.bg)
        .contentShape(Rectangle())
    }
}

/// 16 ячеек ручек: подпись ручки; выбранная — жёлтая рамка; с кривой — жёлтая волна; пустое место и ручка без
/// автоматизации — серые, не нажимаются.
struct ArrAutoCells: View {
    let model: AppModel
    @State private var lastTap: (at: Date, slot: Int)? = nil
    @State private var menu: Int? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let t: Int = model.arrAutoTrack ?? -1
        let slots: [ParamDef] = model.arrAutoSlots(t)
        let cur: String = model.arrAutoParam(t)?.id ?? ""
        return GeometryReader { geo in
            let gap: CGFloat = 4
            let w: CGFloat = (geo.size.width - 3 * gap) / 4
            let h: CGFloat = (geo.size.height - 3 * gap) / 4
            ZStack(alignment: .topLeading) {
                ForEach(0..<slots.count, id: \.self) { i in
                    cell(t, i, slots[i], selected: slots[i].id == cur)
                        .frame(width: w, height: h)
                        .offset(x: CGFloat(i % 4) * (w + gap), y: CGFloat(i / 4) * (h + gap))
                }
                if let k = menu, k < slots.count { clearMenu(t, k, slots[k], w: w, h: h, gap: gap, size: geo.size) }
            }
        }
    }

    private func cell(_ t: Int, _ i: Int, _ p: ParamDef, selected: Bool) -> some View {
        let on: Bool = !p.id.isEmpty && ArrAutoTarget.index(p.id) != nil
        let has: Bool = on && ArrAutoCells.hasCurve(model.project, t, p.id)
        let fg: Color = on ? theme.text : theme.off
        return ZStack(alignment: .topTrailing) {
            Text(p.id.isEmpty ? "" : p.label)
                .font(.system(size: 11, weight: selected ? .heavy : .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .foregroundStyle(fg)
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if has { ArrWaveIcon(color: theme.accent).scaleEffect(0.6).frame(width: 18, height: 14).padding(2) }
        }
        .background(theme.trackBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? theme.accent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if on { tapped(t, i, p, has: has) } }
    }

    /// Тап — кривая ручки; второй тап за 0,3 с по ячейке с кривой — меню CLEAR.
    private func tapped(_ t: Int, _ i: Int, _ p: ParamDef, has: Bool) {
        let now = Date()
        let double: Bool = lastTap.map { $0.slot == i && now.timeIntervalSince($0.at) < 0.3 } ?? false
        lastTap = double ? nil : (now, i)
        model.arrAutoId = p.id
        menu = double && has ? i : nil
    }

    /// CLEAR — под ячейкой (внизу окна — над ней); тап мимо — закрыть.
    private func clearMenu(_ t: Int, _ k: Int, _ p: ParamDef, w: CGFloat, h: CGFloat, gap: CGFloat, size: CGSize) -> some View {
        let mw: CGFloat = 140
        let mh: CGFloat = 56
        let x: CGFloat = min(size.width - mw, CGFloat(k % 4) * (w + gap))
        let below: CGFloat = CGFloat(k / 4 + 1) * (h + gap)
        let y: CGFloat = below + mh <= size.height ? below : max(0, CGFloat(k / 4) * (h + gap) - mh - gap)
        return ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { menu = nil }
            MenuItem(title: "CLEAR") {
                menu = nil
                model.arrAutoDelete(track: t, p.id)
            }
            .frame(width: mw - 16)
            .modifier(MenuPanel())
            .offset(x: x, y: y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    static func hasCurve(_ p: Project, _ t: Int, _ id: String) -> Bool {
        guard t >= 0 && t < p.tracks.count, let k = p.tracks[t].autoLane(id) else { return false }
        return !p.tracks[t].autos[k].points.isEmpty
    }
}

/// Поле кривой: сетка тактов как у таймлайна, петля, ровная серая линия — значение ручки (вне кривой звучит оно),
/// кривая — жёлтая линия с точками (действует от первой точки до последней), курсор.
struct ArrAutoCurve: View {
    let model: AppModel
    @State private var touches = ArrAutoTouches()
    @Environment(\.theme) private var theme

    var body: some View {
        let p: Project = model.project
        let port: ArrPort = model.arrPort
        let now: Int = model.arrNow
        let t: Int = model.arrAutoTrack ?? -1
        let param: ParamDef? = model.arrAutoParam(t)
        return GeometryReader { geo in
            let m = ArrMetrics(size: geo.size, port: port, tracks: p.tracks.count, end: p.arrangeEnd,
                               expanded: model.settings.arrangeExpanded)
            Canvas { ctx, size in
                let d = ArrAutoDraw(ctx: ctx, m: m, theme: theme)
                d.grid(p)
                if let pd = param, t >= 0 { d.curve(p, t, pd) }
                d.cursor(now)
            }
            .overlay(alignment: .topLeading) { title(p, t, param) }
            .contentShape(Rectangle())
            .gesture(touch(geo.size))
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    /// Слева сверху: дорожка и ручка (при MIX и MST — подсказка).
    private func title(_ p: Project, _ t: Int, _ param: ParamDef?) -> some View {
        let name: String = t >= 0 && t < p.tracks.count ? p.tracks[t].name : ""
        let s: String = t < 0 ? "SELECT A TRACK" : name + " · " + (param?.label ?? "")
        return Text(s)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.dim)
            .padding(.leading, 8)
            .padding(.top, 5)
            .allowsHitTesting(false)
    }

    private func touch(_ size: CGSize) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { e in apply(e, size) }
            .onEnded { e in apply(e, size) }
    }

    private func apply(_ events: SpatialEventCollection, _ size: CGSize) {
        let p: Project = model.project
        let expanded: Bool = model.settings.arrangeExpanded
        let m = ArrMetrics(size: size, port: model.arrPort, tracks: p.tracks.count, end: p.arrangeEnd, expanded: expanded)
        var port: ArrPort = model.arrPort
        touches.handle(events, port: &port, m, model)
        let c = ArrMetrics(size: size, port: port, tracks: p.tracks.count, end: p.arrangeEnd, expanded: expanded)
        let next = ArrPort(stepW: port.stepW == nil ? nil : c.stepW, x: c.x, rowH: port.rowH, y: port.y)
        if next != model.arrPort { model.arrPort = next }
    }
}

/// Значение 0…1 ↔ высота поля кривой: сверху место под подпись.
enum ArrAutoGeo {
    static let top: CGFloat = 24
    static let bottom: CGFloat = 10

    static func y(_ v: Double, _ h: CGFloat) -> CGFloat {
        return top + CGFloat(1 - v) * max(1, h - top - bottom)
    }

    static func value(_ y: CGFloat, _ h: CGFloat) -> Double {
        let n: CGFloat = 1 - (y - top) / max(1, h - top - bottom)
        return Double(min(1, max(0, n)))
    }
}

/// Рисование поля кривой.
struct ArrAutoDraw {
    let ctx: GraphicsContext
    let m: ArrMetrics
    let theme: Theme

    /// Петля (бледная полоса) и линии тактов и сетки — как на таймлайне.
    func grid(_ p: Project) {
        let h: CGFloat = m.size.height
        let a: Arrangement = p.arrange
        if a.hasLoop {
            let x0: CGFloat = m.stepX(Double(a.loopFrom))
            let x1: CGFloat = m.stepX(Double(a.loopTo))
            ctx.fill(Path(CGRect(x: x0, y: 0, width: max(2, x1 - x0), height: h)),
                     with: .color(theme.accent.opacity(a.loop ? 0.08 : 0.04)))
        }
        let first: Int = max(0, Int(m.step(at: 0)))
        let last: Int = Int(m.step(at: m.size.width)) + 1
        let g: Int = max(1, a.gridSteps)
        let fine: Bool = CGFloat(g) * m.stepW >= 8
        var s: Int = first - first % g
        while s <= last {
            let bar: Bool = s % ArrMetrics.stepsPerBar == 0
            if bar || fine {
                let x: CGFloat = m.stepX(Double(s))
                let c: Color = bar ? theme.gridStrong : theme.grid
                if x >= 1 { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: h)), with: .color(c)) }
            }
            s += g
        }
    }

    /// Серая линия — значение ручки; кривая — жёлтая линия с точками.
    func curve(_ p: Project, _ t: Int, _ pd: ParamDef) {
        let h: CGFloat = m.size.height
        let base: Double = pd.toNorm(p.tracks[t].params[pd.id] ?? pd.def)
        let by: CGFloat = ArrAutoGeo.y(base, h)
        ctx.fill(Path(CGRect(x: 0, y: by - 0.5, width: m.size.width, height: 1)), with: .color(theme.dim.opacity(0.6)))
        guard let k = p.tracks[t].autoLane(pd.id) else { return }
        let pts: [ArrAutoPoint] = p.tracks[t].autos[k].points
        if pts.isEmpty { return }
        var line = Path()
        var dots = Path()
        for (i, pt) in pts.enumerated() {
            let x: CGFloat = m.stepX(pt.x)
            let y: CGFloat = ArrAutoGeo.y(pt.y, h)
            if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            if x >= -6 && x <= m.size.width + 6 { dots.addEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)) }
        }
        ctx.stroke(line, with: .color(theme.accent), lineWidth: 2)
        ctx.fill(dots, with: .color(theme.accent))
    }

    func cursor(_ pos: Int) {
        let x: CGFloat = m.stepX(Double(pos))
        if x < -2 || x > m.size.width + 2 { return }
        ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: m.size.height)), with: .color(theme.accent))
    }
}

/// Касания поля кривой: у точки (до 24 pt) — перетаскивание (одна запись UNDO) или двойной тап (удалить); по пустому
/// тап — новая точка, сдвиг — прокрутка по времени; два пальца — масштаб по времени (точка между пальцами на месте) и
/// прокрутка.
final class ArrAutoTouches {
    enum Mode { case idle, tap, point, scroll, zoom }

    private var points: [SpatialEventCollection.Event.ID: CGPoint] = [:]
    private var mode: Mode = .idle
    private var start: CGPoint = .zero
    private var base = ArrPort()
    private var spread0: CGFloat = 0
    private var mid: CGFloat = 0
    private var track: Int = -1
    private var param: String = ""
    private var index: Int = -1
    private var orig: [ArrAutoPoint] = []
    private var moved: Bool = false
    private var lastTap: (at: Date, point: CGPoint)? = nil

    func handle(_ events: SpatialEventCollection, port: inout ArrPort, _ m: ArrMetrics, _ model: AppModel) {
        for e in events {
            if e.phase == .active {
                points[e.id] = e.location
                continue
            }
            if points.removeValue(forKey: e.id) != nil && points.isEmpty {
                finish(model, m, ended: e.phase == .ended)
            }
        }
        if points.isEmpty { return }
        let p: [CGPoint] = Array(points.values)
        if p.count >= 2 && mode != .zoom && mode != .point {
            beginZoom(p[0], p[1], m)
        } else if p.count == 1 && mode == .idle {
            begin(p[0], m, model)
        }
        move(p, &port, m, model)
    }

    private func begin(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        start = p
        base = ArrPort(stepW: m.stepW, x: m.x, rowH: model.arrPort.rowH, y: model.arrPort.y)
        moved = false
        index = -1
        mode = .tap
        guard let t = model.arrAutoTrack, let pd = model.arrAutoParam(t) else {
            track = -1
            return
        }
        track = t
        param = pd.id
        let lane: Int? = model.project.tracks[t].autoLane(pd.id)
        orig = lane.map { model.project.tracks[t].autos[$0].points } ?? []
        var best: CGFloat = 24
        for (i, pt) in orig.enumerated() {
            let d: CGFloat = hypot(m.stepX(pt.x) - p.x, ArrAutoGeo.y(pt.y, m.size.height) - p.y)
            if d < best {
                best = d
                index = i
            }
        }
        if index >= 0 { mode = .point }
    }

    private func move(_ p: [CGPoint], _ port: inout ArrPort, _ m: ArrMetrics, _ model: AppModel) {
        let far: Bool = hypot(p[0].x - start.x, p[0].y - start.y) > ArrTouches.slop
        switch mode {
        case .tap:
            if far { mode = .scroll }
            if mode == .scroll { port.x = base.x - (p[0].x - start.x) }
        case .scroll:
            port.x = base.x - (p[0].x - start.x)
        case .point:
            if far && !moved {
                moved = true
                model.beginGesture()
            }
            if moved { drag(p[0], m, model) }
        case .zoom:
            if p.count >= 2 { zoom(p[0], p[1], &port, m) }
        case .idle:
            break
        }
    }

    /// Точка за пальцем: шаг — с привязкой (магнит — линии сетки), не дальше соседних точек.
    private func drag(_ p: CGPoint, _ m: ArrMetrics, _ model: AppModel) {
        guard index >= 0 && index < orig.count else { return }
        var x: Double = model.arrAutoSnap(m.step(at: p.x))
        if index > 0 { x = max(x, orig[index - 1].x) }
        if index + 1 < orig.count { x = min(x, orig[index + 1].x) }
        var pts: [ArrAutoPoint] = orig
        pts[index] = ArrAutoPoint(x: x, y: ArrAutoGeo.value(p.y, m.size.height))
        model.arrAutoSet(track: track, param, pts)
    }

    private func finish(_ model: AppModel, _ m: ArrMetrics, ended: Bool) {
        let was: Mode = mode
        mode = .idle
        if track < 0 || !ended {
            if was == .point && moved { model.endGesture() }
            return
        }
        switch was {
        case .tap:
            var pts: [ArrAutoPoint] = orig
            pts.append(ArrAutoPoint(x: model.arrAutoSnap(m.step(at: start.x)), y: ArrAutoGeo.value(start.y, m.size.height)))
            model.arrAutoSet(track: track, param, pts)
        case .point:
            if moved {
                model.endGesture()
            } else if isDouble() {
                var pts: [ArrAutoPoint] = orig
                if index < pts.count { pts.remove(at: index) }
                // Последняя точка — кривой больше нет.
                if pts.isEmpty { model.arrAutoDelete(track: track, param) } else { model.arrAutoSet(track: track, param, pts) }
            }
        default:
            break
        }
    }

    /// Второй тап по точке за 0,3 с.
    private func isDouble() -> Bool {
        let now = Date()
        var d: Bool = false
        if let l = lastTap {
            d = now.timeIntervalSince(l.at) < ArrTouches.doubleTap && hypot(l.point.x - start.x, l.point.y - start.y) < 30
        }
        lastTap = d ? nil : (now, start)
        return d
    }

    private func beginZoom(_ a: CGPoint, _ b: CGPoint, _ m: ArrMetrics) {
        mode = .zoom
        spread0 = max(20, abs(a.x - b.x))
        mid = (a.x + b.x) / 2
        base = ArrPort(stepW: m.stepW, x: m.x, rowH: base.rowH, y: base.y)
    }

    private func zoom(_ a: CGPoint, _ b: CGPoint, _ port: inout ArrPort, _ m: ArrMetrics) {
        let w0: CGFloat = base.stepW ?? m.stepW
        let k: CGFloat = max(20, abs(a.x - b.x)) / spread0
        let w: CGFloat = ArrMetrics.clampStep(w0 * k, width: m.size.width)
        let cx: CGFloat = (a.x + b.x) / 2
        port.stepW = w
        port.x = (base.x + mid) / w0 * w - cx
    }
}
