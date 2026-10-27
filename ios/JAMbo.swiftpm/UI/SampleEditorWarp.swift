import SwiftUI

// Режим WARP редактора сэмпла (docs/ai/sound-sampler.md): по горизонтали — доли (окно масштаба — доли диапазона
// b0…b1), форма волны — по карте меток; сетка долей (такты ярче, номера тактов сверху); метки — флажки в полосе
// под формой волны. Строка WARP: ▶ (по карте в темпе проекта), BPM файла, GRID, AUTO WARP, CLEAR WARP, WARP, ✕.

/// Доли на экране: диапазон b0…b1 (доли) — это доли окна 0…1 (EditorWindow).
struct WarpView {
    let map: WarpMap
    let frames: Int
    let b0: Double
    let b1: Double

    /// Диапазон по карте: от min(0, начала сэмпла) до конца сэмпла (с запасом в долю), целыми долями.
    static func range(_ map: WarpMap, frames: Int) -> (Double, Double) {
        let a: Double = Swift.min(0, map.beat(0)).rounded(.down)
        let b: Double = Swift.max(a + 1, (map.beat(Double(frames)) + 1).rounded(.up))
        return (a, b)
    }

    init(map: WarpMap, frames: Int, range: (Double, Double)) {
        self.map = map
        self.frames = frames
        b0 = range.0
        b1 = range.1
    }

    func beat(_ f: Double) -> Double {
        return b0 + f * (b1 - b0)
    }

    func frac(beat b: Double) -> Double {
        return (b - b0) / Swift.max(1e-9, b1 - b0)
    }

    /// Доля окна для доли длины сэмпла s.
    func frac(sample s: Double) -> Double {
        return frac(beat: map.beat(s * Double(frames)))
    }

    /// Доля длины сэмпла для доли окна f.
    func sample(_ f: Double) -> Double {
        return map.position(beat(f)) / Double(Swift.max(1, frames))
    }

    /// Такт.доля(.шестнадцатая) от начала сэмпла (4/4).
    static func label(_ b: Double) -> String {
        let q: Double = (b * 4).rounded() / 4
        let bar: Int = Int((q / 4).rounded(.down)) + 1
        let inBar: Double = q - Double(bar - 1) * 4
        let beat: Int = Int(inBar.rounded(.down)) + 1
        let six: Int = Int(((inBar - inBar.rounded(.down)) * 4).rounded()) + 1
        return six > 1 ? "\(bar).\(beat).\(six)" : "\(bar).\(beat)"
    }
}

/// Форма волны по карте: столбец экрана — отрезок сэмпла между отсчётами его краёв (кэш по подписи).
final class WarpPeakCache {
    private var sig: String = ""
    private var lanes: [[(Float, Float)]] = []

    func lanes(_ s: SampleData, key: String, width w: Int, view: EditorWindow, wv: WarpView) -> [[(Float, Float)]] {
        let ps: [String] = wv.map.pos.map { String(Int($0)) }
        let bs: [String] = wv.map.beats.map { String($0) }
        let head: String = "\(key)|\(s.frames)|\(w)|\(view.a)|\(view.span)|\(wv.b0)|\(wv.b1)|\(wv.map.perBeat)|"
        let sg: String = head + ps.joined(separator: ",") + "|" + bs.joined(separator: ",")
        if sg == sig { return lanes }
        sig = sg
        var bounds: [Double] = []
        bounds.reserveCapacity(w + 1)
        for k in 0...w {
            let f: Double = view.a + view.span * Double(k) / Double(Swift.max(1, w))
            bounds.append(wv.map.position(wv.beat(f)))
        }
        lanes = (0..<s.channels).map { c in SampleEdit.peaks(s, channel: c, bounds: bounds) }
        return lanes
    }
}

/// Строка WARP (вместо LOAD…CLEAR): ▶, BPM файла (двойной тап — ввод числом), GRID, AUTO WARP, CLEAR WARP.
struct WarpBar: View {
    let model: AppModel
    let data: SampleData?
    /// ▶ в строке (false — его ставит строка редактора под PLAY верхней панели).
    var showPlay: Bool = true
    @State private var input: Bool = false
    @State private var text: String = ""
    @State private var lastTap: Date = .distantPast
    /// Палец по BPM: BPM в начале жеста, сдвинули ли (вверх-вниз — 4 px на 1 BPM, как BPM проекта).
    @State private var dragStart: Double? = nil
    @State private var dragMoved: Bool = false
    @Environment(\.theme) private var theme

    static let grids: [(String, Double)] = [("1/16", 0.25), ("1/8", 0.5), ("1/4", 1)]

    var body: some View {
        let has: Bool = data != nil
        let marks: Int = model.editorWarpInfo.marks.count
        // Group — кнопки встают в строку редактора наравне с остальными (равной ширины).
        return Group {
            if showPlay {
                PlayToolButton(on: model.previewOn, enabled: has) { model.toggleWarpPreview() }
            }
            bpmButton(has)
                .alert("FILE BPM", isPresented: $input) {
                    TextField("BPM", text: $text).keyboardType(.decimalPad)
                    Button("OK") { enter() }
                    Button("AUTO") { model.setWarpBpm(nil) }
                    Button("Cancel", role: .cancel) {}
                }
            ForEach(0..<WarpBar.grids.count, id: \.self) { i in
                let g: (String, Double) = WarpBar.grids[i]
                ToolButton(title: g.0, lit: model.warpGrid == g.1, width: nil) { model.warpGrid = g.1 }
            }
            ToolButton(title: "AUTO WARP", enabled: has, width: nil) { model.autoWarp() }
            ToolButton(title: "CLEAR WARP", enabled: has && marks > 0, width: nil) { model.clearWarp() }
        }
    }

    /// BPM файла: палец вверх-вниз — 4 px на 1 BPM (одна запись UNDO), двойной тап — ввод числом.
    private func bpmButton(_ has: Bool) -> some View {
        Text(bpmText).font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(has ? theme.text : theme.off)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dragStart != nil ? theme.panel : theme.panel2, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard has, let d = data else { return }
                    if dragStart == nil {
                        model.beginGesture()
                        dragStart = model.warpBpm(d)
                        dragMoved = false
                    }
                    let dy: CGFloat = g.translation.height
                    if abs(dy) > 10 { dragMoved = true }
                    if dragMoved, let s = dragStart {
                        model.setWarpBpm((s - Double(dy) / 4).rounded())
                    }
                }
                .onEnded { _ in
                    if dragStart == nil { return }
                    dragStart = nil
                    model.endGesture()
                    if !dragMoved { bpmTap() }
                })
    }

    private var bpmText: String {
        guard let d = data else { return "BPM" }
        let v: Double = model.warpBpm(d)
        let s: String = v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
        return s + " BPM"
    }

    /// Двойной тап — ввод числом (AUTO — определённый сам).
    private func bpmTap() {
        let now = Date()
        if now.timeIntervalSince(lastTap) < EqPlot.doubleTap, let d = data {
            lastTap = .distantPast
            let v: Double = model.warpBpm(d)
            text = v == v.rounded() ? "\(Int(v))" : String(format: "%.2f", v)
            input = true
        } else {
            lastTap = now
        }
    }

    private func enter() {
        if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 { model.setWarpBpm(v) }
    }
}

/// Рисование WARP: сетка долей, номера тактов, флажки меток (в полосе снизу).
enum EditorWarpDraw {
    static let strip: CGFloat = 30

    /// Флажки меток — одного размера сверху и снизу (нижний — с подписью внутри).
    static let flagW: CGFloat = 36

    static func flagRect(_ x: CGFloat, _ label: String, _ h: CGFloat) -> CGRect {
        let w: CGFloat = flagW
        return CGRect(x: x - w / 2, y: h - SampleEditor.flagH - 4, width: w, height: SampleEditor.flagH)
    }

    /// Полоса флажков снизу; сетка: шаг GRID (реже, если тесно), доли и такты ярче; номера тактов в полосе сверху.
    static func grid(_ ctx: GraphicsContext, _ g: EditorGeometry, _ wv: WarpView, _ step0: Double, _ c: EditorColors) {
        let top: CGFloat = SampleEditor.top
        let w: CGFloat = g.size.width
        let h: CGFloat = g.size.height
        ctx.fill(Path(CGRect(x: 0, y: h - strip, width: w, height: strip)), with: .color(c.track.opacity(0.35)))
        let ba: Double = wv.beat(g.view.a)
        let bb: Double = wv.beat(g.view.a + g.view.span)
        let pxPerBeat: Double = Double(w) / Swift.max(1e-9, bb - ba)
        var step: Double = step0
        while step * pxPerBeat < 8 { step *= 2 }
        var b: Double = (ba / step).rounded(.down) * step
        while b <= bb {
            let x: CGFloat = g.x(wv.frac(beat: b))
            let bar: Bool = abs(b / 4 - (b / 4).rounded()) < 1e-6
            let whole: Bool = abs(b - b.rounded()) < 1e-6
            let col: Color = bar ? c.dim : (whole ? c.line : c.line.opacity(0.5))
            ctx.fill(Path(CGRect(x: x.rounded(), y: top, width: 1, height: h - top - strip)), with: .color(col))
            if bar && 4 * pxPerBeat > 24 {
                let n: Int = Int((b / 4).rounded()) + 1
                ctx.draw(Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundColor(c.dim),
                         at: CGPoint(x: x + 8, y: top / 2), anchor: .leading)
            }
            b += step
        }
    }

    /// Метки: линия во всю высоту и флажок острием вверх с тактом.долей; выделенная (sel) и та, что тянут, — жёлтые.
    /// Нет метки начала — у начала сэмпла серый флажок START (потянуть — метка начала).
    /// Сверху у каждой метки (кроме метки начала) — флажок без подписи острием вниз; moving — метку тянут за него:
    /// линия и флажки — у пальца (x).
    static func flags(_ ctx: GraphicsContext, _ g: EditorGeometry, _ wv: WarpView, _ sel: Int,
                      _ moving: (idx: Int, x: CGFloat)?, _ c: EditorColors) {
        let h: CGFloat = g.size.height
        if let s = startX(g, wv) { flag(ctx, s, "START", h, c.dim, c) }
        for (k, b) in wv.map.beats.enumerated() {
            var x: CGFloat = g.x(wv.frac(beat: b))
            if let m = moving, m.idx == k { x = m.x }
            if x < -60 || x > g.size.width + 60 { continue }
            let col: Color = sel == k ? c.accent : c.ink
            if wv.map.pos[k] >= WarpMap.minFrames { topFlag(ctx, x, col) }
            flag(ctx, x, WarpView.label(b), h, col, c)
        }
    }

    /// Верхний флажок: по центру линии метки, острием вниз, к верху формы волны.
    static func topRect(_ x: CGFloat) -> CGRect {
        let w: CGFloat = flagW
        return CGRect(x: x - w / 2, y: SampleEditor.flagY, width: w, height: SampleEditor.flagH)
    }

    private static func topFlag(_ ctx: GraphicsContext, _ x: CGFloat, _ col: Color) {
        let r = topRect(x)
        let tipY: CGFloat = SampleEditor.top - 2
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: x + 0.5, y: tipY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        ctx.fill(p, with: .color(col))
        ctx.fill(Path(CGRect(x: x.rounded(), y: tipY, width: 1, height: SampleEditor.top - tipY)), with: .color(col))
    }

    /// Флажок START (нет метки у начала сэмпла): место по карте; nil — метка начала есть.
    static func startX(_ g: EditorGeometry, _ wv: WarpView) -> CGFloat? {
        if let p = wv.map.pos.first, p < WarpMap.minFrames { return nil }
        return g.x(wv.frac(sample: 0))
    }

    /// Обычный режим (маркеры нарезки): метки варпинга снизу — только для ориентира (серые, не выделяются); положение —
    /// доля длины сэмпла.
    static func ghosts(_ ctx: GraphicsContext, _ g: EditorGeometry, _ marks: [WarpMark], _ c: EditorColors) {
        let h: CGFloat = g.size.height
        for m in marks {
            let x: CGFloat = g.x(m.at)
            if x < -60 || x > g.size.width + 60 { continue }
            flag(ctx, x, WarpView.label(m.beat), h, c.dim.opacity(0.7), c)
        }
    }

    private static func flag(_ ctx: GraphicsContext, _ x: CGFloat, _ label: String, _ h: CGFloat, _ col: Color,
                             _ c: EditorColors) {
        let top: CGFloat = SampleEditor.top
        let r = flagRect(x, label, h)
        // Остриё — как у верхнего флажка (от тела до верха формы волны — 12 pt).
        let tipY: CGFloat = r.minY - (SampleEditor.top - 2 - SampleEditor.flagY - SampleEditor.flagH)
        ctx.fill(Path(CGRect(x: x.rounded(), y: top, width: 1, height: tipY - top)), with: .color(col))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: x + 0.5, y: tipY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        ctx.fill(p, with: .color(col))
        ctx.draw(Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(c.bg),
                 at: CGPoint(x: x + 0.5, y: r.midY))
    }

    /// Полосы воспроизведения (доли длины сэмпла) — на месте по карте.
    static func heads(_ ctx: GraphicsContext, _ g: EditorGeometry, _ wv: WarpView, _ heads: [(f: Double, a: Double)],
                      _ c: EditorColors) {
        let top: CGFloat = SampleEditor.top
        for hd in heads {
            let x: CGFloat = g.x(wv.frac(sample: hd.f))
            if x < 0 || x > g.size.width { continue }
            ctx.fill(Path(CGRect(x: x.rounded() - 1, y: top, width: 2, height: g.size.height - top - strip)),
                     with: .color(c.accent.opacity(hd.a)))
        }
    }
}
