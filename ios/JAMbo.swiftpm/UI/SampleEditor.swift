import SwiftUI

/// Редактор сэмпла (удержание окна сэмпла; как sampleedit.ts веба): на месте центра экрана, справа измеритель.
/// Вверху — имя, длина (и выделение), ST/M, REC (S10), ▶, LOAD, SAVE (S10), TRIM, NORMALIZE, MONO, CLEAR, ✕.
/// Форма волны во всю ширину (стерео — L и R); маркеры обрезки — за ручки внизу (двумя пальцами — оба сразу);
/// палец по пустому месту: вверх-вниз — масштаб, влево-вправо — прокрутка; двойной тап — маркер нарезки,
/// флажок тянут, двойной тап по флажку — удалить, удержание флажка + клавиша — своя нота маркера.
struct SampleEditor: View {
    let model: AppModel
    @State private var sel = EditorSelection()
    @State private var view = EditorWindow()
    @State private var touches: [SpatialEventCollection.Event.ID: EditorTouch] = [:]
    @State private var lastTap: (t: Date, x: CGFloat, flag: Int) = (Date.distantPast, 0, -1)
    @State private var tip: (text: String, at: CGPoint)? = nil
    @State private var cache = PeakCache()
    @Environment(\.theme) private var theme

    static let top: CGFloat = 40
    static let handle: CGFloat = 22
    static let slop: CGFloat = 10
    static let zoomPx: CGFloat = 110
    static let flagY: CGFloat = 8
    static let flagH: CGFloat = 18

    var body: some View {
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
        }
    }

    // MARK: — поле

    @ViewBuilder
    private func plot(_ key: String, _ data: SampleData?, _ size: CGSize) -> some View {
        if let d = data {
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.headCount == 0)) { _ in
                    canvas(key, d, size)
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
            Text(model.channel != .track ? "Select a track to edit its sample." : "No sample on this track — LOAD a file.")
                .font(.system(size: 13)).foregroundStyle(theme.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func canvas(_ key: String, _ d: SampleData, _ size: CGSize) -> some View {
        let w: Int = max(1, Int(size.width))
        let lanes = cache.big(d, key: key, width: w, a: view.a, span: view.span)
        let marks: [SliceMark] = model.editorMarks
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
            EditorDraw.flags(ctx, g, marks, notes, held, refused, colors)
            EditorDraw.heads(ctx, g, heads, colors)
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
        if let m = trimAt(p, g) {
            touches[id] = EditorTouch(kind: .trim, trimB: m, p0: p)
            move(id, p, d, size)
            return
        }
        let fl = flagAt(p, g)
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
            model.moveSlice(t.idx, at: g.frac(p.x), gap: 32 / Double(d.frames))
            let marks = model.editorMarks
            let notes = model.editorMarkNotes
            if t.idx < marks.count {
                tip = (Params.noteName(notes[t.idx]) + "\n" + EditorDraw.time(marks[t.idx].at * dur), p)
            }
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
        let tap: Bool = t.kind == .slice ? !t.moved : (t.kind == .nav && t.axis == 0)
        if !tap { return }
        let flag: Int = t.kind == .slice ? t.idx : -1
        let now = Date()
        let dbl: Bool = now.timeIntervalSince(lastTap.t) < 0.35 && abs(p.x - lastTap.x) < 24 && lastTap.flag == flag
        if !dbl {
            lastTap = (now, p.x, flag)
            return
        }
        lastTap = (Date.distantPast, 0, -1)
        if flag >= 0 {
            model.deleteSlice(flag)
        } else {
            model.addSlice(at: geometry(size).frac(p.x))
        }
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
    enum Kind { case trim, slice, nav }
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
