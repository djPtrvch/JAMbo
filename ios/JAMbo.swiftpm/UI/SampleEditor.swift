import SwiftUI

/// Редактор сэмпла (удержание окна сэмпла; как sampleedit.ts веба): на месте центра экрана, справа измеритель.
/// Вверху — имя, длина (и выделение), ST/M, REC (S11e; во время записи на поле — форма волны записи), ▶, LOAD, SAVE (S11), TRIM, NORMALIZE, MONO, CLEAR, ✕.
/// Форма волны во всю ширину (стерео — L и R); маркеры обрезки — за ручки внизу (двумя пальцами — оба сразу);
/// палец по пустому месту: вверх-вниз — масштаб, влево-вправо — прокрутка; двойной тап — маркер нарезки,
/// флажок тянут, двойной тап по флажку — удалить, удержание флажка + клавиша — своя нота маркера; метки варпинга —
/// снизу серыми флажками (только ориентир), маркер ближе 12 pt к метке прилипает к ней.
/// WARP (SampleEditorWarp.swift): по горизонтали доли; двойной тап — метка варпинга; метку берут за флажок снизу или за
/// линию (касание — выделить, тянуть — на столько же, магнит к GRID), выделенную тянут и из любого места полосы
/// флажков; флажок START — метка начала сэмпла; двойной тап по флажку — удалить; верхний флажок без подписи — метку
/// ставят точно на место в сэмпле (линия идёт за пальцем, отпустили — доля к ближайшей линии GRID); маркеры нарезки и
/// обрезки скрыты.
struct SampleEditor: View {
    let model: AppModel
    @State private var sel = EditorSelection()
    @State private var view = EditorWindow()
    @State private var touches: [SpatialEventCollection.Event.ID: EditorTouch] = [:]
    @State private var lastTap: (t: Date, x: CGFloat, flag: Int) = (Date.distantPast, 0, -1)
    @State private var tip: (text: String, at: CGPoint)? = nil
    @State private var cache = PeakCache()
    @State private var warpCache = WarpPeakCache()
    /// Диапазон долей WARP на время перетаскивания метки (окно не прыгает).
    @State private var warpFrozen: (Double, Double)? = nil
    @Environment(\.theme) private var theme

    static let top: CGFloat = 40
    static let handle: CGFloat = 22
    static let slop: CGFloat = 10
    static let zoomPx: CGFloat = 110
    static let flagY: CGFloat = 8
    static let flagH: CGFloat = 18

    var body: some View {
        let _ = RedrawMeter.hit(.editor)
        let key: String = model.editorKey
        let data: SampleData? = model.sample(key)
        let _ = model.samplesVersion
        return VStack(spacing: Layout.gap) {
            EditorBar(model: model, key: key, data: data, sel: sel)
                .frame(height: 48)
            GeometryReader { geo in
                plot(key, data, geo.size)
            }
            .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
            .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
        }
        .onChange(of: key) { _, _ in
            sel = EditorSelection()
            view = EditorWindow()
            touches.removeAll()
            model.heldFlag = nil
            model.warpSel = nil
            warpFrozen = nil
        }
    }

    /// Доли на экране WARP (во время перетаскивания метки — прежний диапазон).
    private func warpView(_ d: SampleData) -> WarpView {
        let map: WarpMap = model.warpMap(d)
        return WarpView(map: map, frames: d.frames, range: warpFrozen ?? WarpView.range(map, frames: d.frames))
    }

    // MARK: — поле

    @ViewBuilder
    private func plot(_ key: String, _ data: SampleData?, _ size: CGSize) -> some View {
        if model.sampleRec.take != nil {
            RecordingPlot(model: model)
        } else if let d = data {
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.headCount == 0)) { _ in
                    let _ = RedrawMeter.hit(.wave)
                    if model.editorWarp { warpCanvas(key, d, size) } else { canvas(key, d, size) }
                }
                if let t = tip {
                    Text(t.text).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.text)
                        .padding(6)
                        .background(theme.bg.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                        .position(x: min(size.width - 50, max(50, t.at.x)), y: max(24, t.at.y - 70))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(fingers(d, size))
        } else {
            Text(model.channel != .track ? "Select a track to edit its sample." : "No sample on this track — LOAD a file or REC.")
                .font(.system(size: 13)).foregroundStyle(theme.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func canvas(_ key: String, _ d: SampleData, _ size: CGSize) -> some View {
        let w: Int = max(1, Int(size.width))
        let lanes = cache.big(d, key: key, width: w, a: view.a, span: view.span)
        let marks: [SliceMark] = model.editorMarks
        let warps: [WarpMark] = model.editorWarpInfo.marks
        let notes: [Int] = model.editorMarkNotes
        let heads = model.playheads(track: model.selectedTrack, key: key)
        let held: Set<Int> = Set(touches.values.compactMap { $0.kind == .slice ? $0.idx : nil })
        let now: Double = Date.timeIntervalSinceReferenceDate
        let refused: Int = model.refusedFlag.until > now ? model.refusedFlag.idx : -1
        let colors = EditorColors(theme: theme)
        let s = sel
        let v = view
        return Canvas { ctx, sz in
            let g = EditorGeometry(size: sz, view: v)
            EditorDraw.lanes(ctx, g, lanes, colors)
            EditorDraw.trim(ctx, g, s, colors)
            EditorWarpDraw.ghosts(ctx, g, warps, colors)
            EditorDraw.flags(ctx, g, marks, notes, held, refused, colors)
            EditorDraw.heads(ctx, g, heads, colors)
            EditorDraw.scrollbar(ctx, g, colors)
        }
    }

    private func warpCanvas(_ key: String, _ d: SampleData, _ size: CGSize) -> some View {
        let w: Int = max(1, Int(size.width))
        let wv: WarpView = warpView(d)
        let lanes = warpCache.lanes(d, key: key, width: w, view: view, wv: wv)
        let heads = model.playheads(track: model.selectedTrack, key: key)
        let hd: EditorTouch? = touches.values.first(where: { $0.kind == .warp || $0.kind == .warpTop })
        let held: Int = hd?.idx ?? (model.warpSel ?? -1)
        let mv: EditorTouch? = touches.values.first(where: { $0.kind == .warpTop && $0.moved })
        let moving: (idx: Int, x: CGFloat)? = mv.map { (idx: $0.idx, x: $0.x) }
        let colors = EditorColors(theme: theme)
        let v = view
        let grid: Double = model.warpGrid
        return Canvas { ctx, sz in
            let g = EditorGeometry(size: sz, view: v)
            let wave = EditorGeometry(size: CGSize(width: sz.width, height: sz.height - EditorWarpDraw.strip), view: v)
            EditorDraw.lanes(ctx, wave, lanes, colors)
            EditorWarpDraw.grid(ctx, g, wv, grid, colors)
            EditorWarpDraw.flags(ctx, g, wv, held, moving, colors)
            EditorWarpDraw.heads(ctx, g, wv, heads, colors)
            EditorDraw.scrollbar(ctx, g, colors)
        }
    }

    // MARK: — жесты

    private func fingers(_ d: SampleData, _ size: CGSize) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    switch e.phase {
                    case .active:
                        if touches[e.id] == nil { down(e.id, e.location, d, size) } else { move(e.id, e.location, d, size) }
                    case .ended:
                        up(e.id, e.location, size, cancelled: false)
                    case .cancelled:
                        up(e.id, e.location, size, cancelled: true)
                    @unknown default:
                        break
                    }
                }
            }
            .onEnded { events in
                for e in events { up(e.id, e.location, size, cancelled: false) }
            }
    }

    private func geometry(_ size: CGSize) -> EditorGeometry {
        return EditorGeometry(size: size, view: view)
    }

    private func down(_ id: SpatialEventCollection.Event.ID, _ p: CGPoint, _ d: SampleData, _ size: CGSize) {
        let g = geometry(size)
        if model.editorWarp {
            // Верхний флажок: место метки в сэмпле.
            let top: Int = p.y < SampleEditor.top ? warpTopHit(p, g, d) : -1
            if top >= 0 {
                if touches.values.contains(where: { $0.kind == .warp || $0.kind == .warpTop }) { return }
                let wv = warpView(d)
                warpFrozen = (wv.b0, wv.b1)
                var t = EditorTouch(kind: .warpTop, idx: top, p0: p)
                t.x = g.x(wv.frac(beat: wv.map.beats[top]))
                model.warpSel = top
                touches[id] = t
                return
            }
            // Метка под пальцем (флажок, START или линия); мимо, но в полосе флажков — выделенная.
            let k: Int = warpHit(p, g, d)
            let inStrip: Bool = p.y >= g.size.height - EditorWarpDraw.strip - 8
            let idx: Int = k != -1 ? k : (inStrip ? (model.warpSel ?? -1) : -1)
            if idx != -1 {
                if touches.values.contains(where: { $0.kind == .warp || $0.kind == .warpTop }) { return }
                let wv = warpView(d)
                warpFrozen = (wv.b0, wv.b1)
                var t = EditorTouch(kind: .warp, idx: idx, p0: p)
                t.onMark = k != -1
                t.b0 = idx >= 0 && idx < wv.map.beats.count ? wv.map.beats[idx] : wv.map.beat(0)
                if idx >= 0 { model.warpSel = idx }
                touches[id] = t
                return
            }
        } else if let m = trimAt(p, g) {
            touches[id] = EditorTouch(kind: .trim, trimB: m, p0: p)
            move(id, p, d, size)
            return
        }
        let fl: Int = model.editorWarp ? -1 : flagAt(p, g)
        if fl >= 0 {
            touches[id] = EditorTouch(kind: .slice, idx: fl, p0: p)
            model.flagUsed = false
            model.heldFlag = fl
            return
        }
        // Масштаб и прокрутка — одним пальцем; второй палец по пустому месту ничего не делает.
        if touches.values.contains(where: { $0.kind == .nav }) { return }
        var t = EditorTouch(kind: .nav, p0: p)
        t.a0 = view.a
        t.span0 = view.span
        t.f0 = g.frac(p.x)
        touches[id] = t
    }

    private func move(_ id: SpatialEventCollection.Event.ID, _ p: CGPoint, _ d: SampleData, _ size: CGSize) {
        guard var t = touches[id] else { return }
        let g = geometry(size)
        let dur: Double = d.duration
        switch t.kind {
        case .trim:
            // Между маркерами обрезки — не меньше 64 отсчётов.
            let gap: Double = min(0.5, 64 / Double(d.frames))
            let f: Double = g.frac(p.x)
            if t.trimB {
                sel.b = min(1, max(f, sel.a + gap))
            } else {
                sel.a = max(0, min(f, sel.b - gap))
            }
            let at: Double = (t.trimB ? sel.b : sel.a) * dur
            tip = ((t.trimB ? "END\n" : "START\n") + EditorDraw.time(at), p)
        case .slice:
            if !t.moved {
                if hypot(p.x - t.p0.x, p.y - t.p0.y) < SampleEditor.slop { return }
                t.moved = true
                model.heldFlag = nil
                model.beginGesture()
            }
            model.moveSlice(t.idx, at: snapToWarp(g.frac(p.x), g), gap: 32 / Double(d.frames))
            let marks = model.editorMarks
            let notes = model.editorMarkNotes
            if t.idx < marks.count {
                tip = (Params.noteName(notes[t.idx]) + "\n" + EditorDraw.time(marks[t.idx].at * dur), p)
            }
        case .warp:
            if !t.moved {
                if hypot(p.x - t.p0.x, p.y - t.p0.y) < SampleEditor.slop { return }
                t.moved = true
                model.beginGesture()
                // START: сначала метка начала (в том же жесте — одна запись UNDO).
                if t.idx == EditorTouch.warpStart {
                    t.idx = model.warpStartMark()
                    model.warpSel = t.idx
                }
            }
            if t.idx < 0 { return }
            // Метка — на столько же долей, на сколько палец, к ближайшей линии GRID.
            let wv = warpView(d)
            let gs: Double = model.warpGrid
            let db: Double = wv.beat(g.frac(p.x)) - wv.beat(g.frac(t.p0.x))
            let b: Double = ((t.b0 + db) / gs).rounded() * gs
            model.moveWarp(t.idx, beat: b)
            let beats = model.warpMap(d).beats
            if t.idx < beats.count { tip = (WarpView.label(beats[t.idx]), p) }
        case .warpTop:
            // Линия — за пальцем (точно, без сетки): от места метки на столько же, сколько палец.
            if !t.moved {
                if abs(p.x - t.p0.x) < SampleEditor.slop { return }
                t.moved = true
                t.f0 = Double(t.x - t.p0.x)
            }
            t.x = p.x + CGFloat(t.f0)
            let wv = warpView(d)
            let sp: Double = wv.map.position(wv.beat(g.frac(t.x)))
            tip = (EditorDraw.time(Swift.max(0, sp) / AudioCore.sampleRate), CGPoint(x: t.x, y: p.y + 130))
        case .nav:
            navigate(&t, p, d, g)
        }
        touches[id] = t
    }

    /// Направление фиксируется после 10 px: вверх-вниз — масштаб (точка под пальцем на месте), вбок — прокрутка.
    private func navigate(_ t: inout EditorTouch, _ p: CGPoint, _ d: SampleData, _ g: EditorGeometry) {
        let dx: CGFloat = p.x - t.p0.x
        let dy: CGFloat = p.y - t.p0.y
        if t.axis == 0 {
            if hypot(dx, dy) < SampleEditor.slop { return }
            t.axis = abs(dy) > abs(dx) ? 2 : 1
            t.p0 = p
            t.a0 = view.a
            t.span0 = view.span
            t.f0 = g.frac(p.x)
            return
        }
        let w: Double = Double(max(1, g.size.width))
        var v = view
        if t.axis == 2 {
            let minSpan: Double = min(1, 256 / Double(d.frames))
            let k: Double = pow(2, Double(p.y - t.p0.y) / Double(SampleEditor.zoomPx))
            v.span = min(1, max(minSpan, t.span0 * k))
            v.a = t.f0 - Double(t.p0.x) / w * v.span
        } else {
            v.a = t.a0 - Double(dx) / w * t.span0
        }
        v.span = min(1, v.span)
        v.a = min(1 - v.span, max(0, v.a))
        view = v
    }

    private func up(_ id: SpatialEventCollection.Event.ID, _ p: CGPoint, _ size: CGSize, cancelled: Bool) {
        guard let t = touches.removeValue(forKey: id) else { return }
        if !touches.values.contains(where: { $0.kind != .nav }) { tip = nil }
        if t.kind == .warpTop {
            // Отпустили: метка — на место под линией, доля — к ближайшей линии GRID.
            if t.moved, let d = model.sample(model.editorKey) {
                let wv = warpView(d)
                let b: Double = wv.beat(geometry(size).frac(t.x))
                let gs: Double = model.warpGrid
                let at: Double = wv.map.position(b) / Double(max(1, d.frames))
                model.placeWarp(t.idx, at: at, beat: (b / gs).rounded() * gs)
            }
            warpFrozen = nil
            return
        }
        if t.kind == .warp {
            warpFrozen = nil
            if t.moved {
                model.endGesture()
                return
            }
        }
        if t.kind == .slice {
            model.heldFlag = nil
            if t.moved {
                model.endGesture()
                return
            }
            if model.flagUsed { return }
        }
        if cancelled { return }
        // Тап без движения: одиночный ничего не делает, двойной — маркер (по пустому месту) или удаление (по флажку).
        let tap: Bool = t.kind == .slice || t.kind == .warp ? !t.moved : (t.kind == .nav && t.axis == 0)
        if !tap { return }
        let flag: Int = t.kind == .slice ? t.idx : (t.kind == .warp && t.onMark ? t.idx : -1)
        let now = Date()
        let dbl: Bool = now.timeIntervalSince(lastTap.t) < 0.35 && abs(p.x - lastTap.x) < 24 && lastTap.flag == flag
        if !dbl {
            lastTap = (now, p.x, flag)
            return
        }
        lastTap = (Date.distantPast, 0, -1)
        if model.editorWarp {
            if flag == EditorTouch.warpStart { return }
            if flag >= 0 {
                model.deleteWarp(flag)
            } else if let d = model.sample(model.editorKey) {
                // Метка — только в пределах сэмпла.
                let f: Double = warpView(d).sample(geometry(size).frac(p.x))
                if f > 0 && f < 1 { model.addWarp(at: f) }
            }
            return
        }
        if flag >= 0 {
            model.deleteSlice(flag)
        } else {
            let g = geometry(size)
            model.addSlice(at: snapToWarp(g.frac(p.x), g))
        }
    }

    /// Маркер нарезки ближе 12 pt к метке варпинга — точно на неё.
    private func snapToWarp(_ f: Double, _ g: EditorGeometry) -> Double {
        var best: Double = f
        var bestD: CGFloat = 12
        for m in model.editorWarpInfo.marks {
            let dx: CGFloat = abs(g.x(m.at) - g.x(f))
            if dx <= bestD {
                bestD = dx
                best = m.at
            }
        }
        return best
    }

    /// Ручка маркера обрезки под пальцем (внизу): false — начало, true — конец; nil — нет.
    private func trimAt(_ p: CGPoint, _ g: EditorGeometry) -> Bool? {
        if p.y < g.size.height - SampleEditor.handle - 10 { return nil }
        let hd: CGFloat = SampleEditor.handle
        let da: CGFloat = abs(p.x - (g.x(sel.a) + hd / 2))
        let db: CGFloat = abs(p.x - (g.x(sel.b) - hd / 2))
        let used: Set<Bool> = Set(touches.values.compactMap { $0.kind == .trim ? $0.trimB : nil })
        let best: Bool = db < da
        if min(da, db) > hd { return nil }
        if !used.contains(best) { return best }
        let other: Bool = !best
        let od: CGFloat = other ? db : da
        return !used.contains(other) && od <= hd ? other : nil
    }

    /// Верхний флажок метки под пальцем (правее нарисованный; зона шире на 6 px; у метки начала его нет) или −1.
    private func warpTopHit(_ p: CGPoint, _ g: EditorGeometry, _ d: SampleData) -> Int {
        let wv = warpView(d)
        var k = wv.map.beats.count - 1
        while k >= 0 {
            if wv.map.pos[k] >= WarpMap.minFrames {
                let r = EditorWarpDraw.topRect(g.x(wv.frac(beat: wv.map.beats[k])))
                if p.x >= r.minX - 6 && p.x <= r.maxX + 6 { return k }
            }
            k -= 1
        }
        return -1
    }

    /// Метка под пальцем: в полосе снизу — флажок (правее нарисованный; зона шире флажка на 6 px) или START
    /// (EditorTouch.warpStart); выше — ближайшая линия метки не дальше 14 px; иначе −1.
    private func warpHit(_ p: CGPoint, _ g: EditorGeometry, _ d: SampleData) -> Int {
        let wv = warpView(d)
        let beats: [Double] = wv.map.beats
        if p.y >= g.size.height - EditorWarpDraw.strip - 8 {
            var k = beats.count - 1
            while k >= 0 {
                let r = EditorWarpDraw.flagRect(g.x(wv.frac(beat: beats[k])), WarpView.label(beats[k]), g.size.height)
                if p.x >= r.minX - 6 && p.x <= r.maxX + 6 { return k }
                k -= 1
            }
            if let sx = EditorWarpDraw.startX(g, wv) {
                let r = EditorWarpDraw.flagRect(sx, "START", g.size.height)
                if p.x >= r.minX - 6 && p.x <= r.maxX + 6 { return EditorTouch.warpStart }
            }
            return -1
        }
        if p.y < SampleEditor.top { return -1 }
        var best: Int = -1
        var bestD: CGFloat = 14
        for (k, b) in beats.enumerated() {
            let dx: CGFloat = abs(p.x - g.x(wv.frac(beat: b)))
            if dx <= bestD {
                bestD = dx
                best = k
            }
        }
        return best
    }

    /// Флажок маркера под пальцем (сверху — правее нарисованный; зона шире флажка на 6 px) или −1.
    private func flagAt(_ p: CGPoint, _ g: EditorGeometry) -> Int {
        if p.y > SampleEditor.top + 8 { return -1 }
        let marks = model.editorMarks
        let notes = model.editorMarkNotes
        var k = marks.count - 1
        while k >= 0 {
            let r = EditorDraw.flagRect(g.x(marks[k].at), Params.noteName(notes[k]))
            if p.x >= r.minX - 6 && p.x <= r.maxX + 6 { return k }
            k -= 1
        }
        return -1
    }
}

/// Выделение маркерами обрезки (доли длины) — только для TRIM и ▶.
struct EditorSelection: Equatable {
    var a: Double = 0
    var b: Double = 1
    var full: Bool { return a <= 0 && b >= 1 }
}

/// Видимая часть сэмпла: начало и ширина окна (доли длины).
struct EditorWindow: Equatable {
    var a: Double = 0
    var span: Double = 1
}

struct EditorTouch {
    enum Kind { case trim, slice, warp, warpTop, nav }
    let kind: Kind
    var trimB: Bool = false
    var idx: Int = -1
    var p0: CGPoint
    var moved: Bool = false
    /// 0 — не определено, 1 — прокрутка, 2 — масштаб.
    var axis: Int = 0
    var a0: Double = 0
    var span0: Double = 1
    var f0: Double = 0
    /// WARP: доля метки в начале перетаскивания; взяли саму метку (флажок, линию), а не выделенную из полосы.
    var b0: Double = 0
    var onMark: Bool = false
    /// WARP, верхний флажок: где сейчас линия метки (x на экране); f0 — сдвиг пальца от линии.
    var x: CGFloat = 0
    /// Номер «метки» START (метки начала ещё нет).
    static let warpStart = -2

    init(kind: Kind, trimB: Bool = false, idx: Int = -1, p0: CGPoint) {
        self.kind = kind
        self.trimB = trimB
        self.idx = idx
        self.p0 = p0
    }
}

struct EditorGeometry {
    let size: CGSize
    let view: EditorWindow

    func x(_ f: Double) -> CGFloat {
        return CGFloat((f - view.a) / view.span) * size.width
    }

    func frac(_ x: CGFloat) -> Double {
        let f: Double = view.a + Double(x / max(1, size.width)) * view.span
        return min(1, max(0, f))
    }
}
