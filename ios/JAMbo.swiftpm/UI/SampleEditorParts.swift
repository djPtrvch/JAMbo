import SwiftUI

/// Строка редактора сэмпла: имя и длина, REC (S11), ▶, LOAD и SAVE (браузер библиотеки, S11b), TRIM, NORMALIZE, MONO, CLEAR, ✕.
struct EditorBar: View {
    let model: AppModel
    let key: String
    let data: SampleData?
    let sel: EditorSelection
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Layout.gap) {
            Text(info)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            recButton
            ToolButton(title: "▶", enabled: data != nil, lit: model.previewOn, width: 48) {
                model.togglePreview(sel.a, sel.b)
            }
            ToolButton(title: "LOAD", width: 76) { model.openBrowser(.load(steps: [])) }
            ToolButton(title: "SAVE", enabled: data != nil, width: 76) { model.openBrowser(.saveSample(key)) }
            ToolButton(title: "TRIM", enabled: data != nil && !sel.full, width: 76) { model.trimSample(sel.a, sel.b) }
            ToolButton(title: "NORMALIZE", enabled: data != nil, width: 104) { model.normalizeSample() }
            ToolButton(title: "MONO", enabled: (data?.channels ?? 1) == 2, width: 76) { model.monoSample() }
            ToolButton(title: "CLEAR", enabled: data != nil, width: 76) { model.clearSample() }
            ToolButton(title: "✕", width: 48) { model.closeEditor() }
        }
    }

    private var info: String {
        guard let d = data else { return "SAMPLE\nEDITOR" }
        let dur: Double = d.duration
        let len: String = sel.full ? EditorDraw.time(dur) : EditorDraw.time((sel.b - sel.a) * dur) + " of " + EditorDraw.time(dur)
        return model.sampleName(key) + "\n" + len + (d.channels == 2 ? " · ST" : " · M")
    }

    /// REC (запись сэмпла — S11): красная точка и красный текст, пока неактивна — серая.
    private var recButton: some View {
        HStack(spacing: 6) {
            Circle().fill(theme.off).frame(width: 10, height: 10)
            Text("REC").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.off)
        }
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(theme.panel2, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Кнопка строки окна (как кнопки EQ): тап — действие; неактивная — серая; lit — жёлтая.
struct ToolButton: View {
    let title: String
    var enabled: Bool = true
    var lit: Bool = false
    var width: CGFloat = 76
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let fg: Color = !enabled ? theme.off : (lit ? theme.onAccent : theme.text)
        return Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(fg)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(lit ? theme.accent : theme.panel2, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Цвета темы для Canvas редактора.
struct EditorColors {
    let ink: Color
    let line: Color
    let dim: Color
    let accent: Color
    let rec: Color
    let track: Color
    let scrim: Color
    let bg: Color

    init(theme: Theme) {
        ink = theme.text
        line = theme.line
        dim = theme.dim
        accent = theme.accent
        rec = theme.rec
        track = theme.meterTrack
        scrim = theme.bg.opacity(0.6)
        bg = theme.bg
    }
}

/// Рисование редактора: каналы, обрезка, флажки нарезки, полосы воспроизведения, полоса прокрутки.
enum EditorDraw {
    static func time(_ s: Double) -> String {
        return s < 10 ? String(format: "%.3f s", s) : String(format: "%.2f s", s)
    }

    /// Тело флажка — по центру линии маркера.
    static func flagRect(_ x: CGFloat, _ label: String) -> CGRect {
        let w: CGFloat = max(30, CGFloat(label.count) * 8 + 10)
        return CGRect(x: x - w / 2, y: SampleEditor.flagY, width: w, height: SampleEditor.flagH)
    }

    static func lanes(_ ctx: GraphicsContext, _ g: EditorGeometry, _ lanes: [[(Float, Float)]], _ c: EditorColors) {
        let top: CGFloat = SampleEditor.top
        let w: CGFloat = g.size.width
        let h: CGFloat = g.size.height
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: top)), with: .color(c.track.opacity(0.35)))
        if lanes.isEmpty { return }
        let lh: CGFloat = (h - top) / CGFloat(lanes.count)
        for (k, lane) in lanes.enumerated() {
            let mid: CGFloat = top + lh * CGFloat(k) + lh / 2
            let amp: CGFloat = lh / 2 - 6
            var path = Path()
            let n: Int = lane.count
            for (i, v) in lane.enumerated() {
                let x: CGFloat = CGFloat(i) / CGFloat(max(1, n)) * w
                let y0: CGFloat = mid - CGFloat(v.1) * amp
                let y1: CGFloat = mid - CGFloat(v.0) * amp
                path.addRect(CGRect(x: x, y: y0, width: 1, height: max(1, y1 - y0)))
            }
            ctx.fill(path, with: .color(c.ink))
            ctx.fill(Path(CGRect(x: 0, y: mid, width: w, height: 1)), with: .color(c.line))
            if lanes.count > 1 {
                ctx.draw(Text(k == 0 ? "L" : "R").font(.system(size: 11)).foregroundColor(c.dim),
                         at: CGPoint(x: 12, y: top + lh * CGFloat(k) + 14))
            }
        }
    }

    /// Отрезаемое — затемнено; маркеры обрезки — жёлтые линии с ручками внизу.
    static func trim(_ ctx: GraphicsContext, _ g: EditorGeometry, _ s: EditorSelection, _ c: EditorColors) {
        let top: CGFloat = SampleEditor.top
        let w: CGFloat = g.size.width
        let h: CGFloat = g.size.height
        let hd: CGFloat = SampleEditor.handle
        let xa: CGFloat = g.x(s.a)
        let xb: CGFloat = g.x(s.b)
        if xa > 0 { ctx.fill(Path(CGRect(x: 0, y: top, width: min(w, xa), height: h - top)), with: .color(c.scrim)) }
        if xb < w {
            let x0: CGFloat = max(0, xb)
            ctx.fill(Path(CGRect(x: x0, y: top, width: w - x0, height: h - top)), with: .color(c.scrim))
        }
        for (x, right) in [(xa, false), (xb, true)] {
            if x < -hd || x > w + hd { continue }
            ctx.fill(Path(CGRect(x: x.rounded() - 1, y: top, width: 2, height: h - top)), with: .color(c.accent))
            ctx.fill(Path(CGRect(x: right ? x - hd : x, y: h - hd, width: hd, height: hd)), with: .color(c.accent))
        }
    }

    /// Маркеры нарезки: линия и флажок-пятиугольник острием вниз с нотой; тянут или держат — жёлтый, отказ — красный.
    static func flags(_ ctx: GraphicsContext, _ g: EditorGeometry, _ marks: [SliceMark], _ notes: [Int], _ held: Set<Int>,
                      _ refused: Int, _ c: EditorColors) {
        let tipY: CGFloat = SampleEditor.top - 2
        let h: CGFloat = g.size.height
        for (k, m) in marks.enumerated() where k < notes.count {
            let x: CGFloat = g.x(m.at)
            if x < -60 || x > g.size.width + 60 { continue }
            let label: String = Params.noteName(notes[k])
            let r = flagRect(x, label)
            let col: Color = refused == k ? c.rec : (held.contains(k) ? c.accent : c.ink)
            ctx.fill(Path(CGRect(x: x.rounded(), y: tipY, width: 1, height: h - tipY)), with: .color(col))
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: x + 0.5, y: tipY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            ctx.fill(p, with: .color(col))
            ctx.draw(Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(c.bg),
                     at: CGPoint(x: x + 0.5, y: r.midY + 1))
        }
    }

    static func heads(_ ctx: GraphicsContext, _ g: EditorGeometry, _ heads: [(f: Double, a: Double)], _ c: EditorColors) {
        let top: CGFloat = SampleEditor.top
        for hd in heads {
            let x: CGFloat = g.x(hd.f)
            if x < 0 || x > g.size.width { continue }
            ctx.fill(Path(CGRect(x: x.rounded() - 1, y: top, width: 2, height: g.size.height - top)),
                     with: .color(c.accent.opacity(hd.a)))
        }
    }

    /// Полоса прокрутки (при увеличении): видимая часть сэмпла — жёлтым, у верхнего края.
    static func scrollbar(_ ctx: GraphicsContext, _ g: EditorGeometry, _ c: EditorColors) {
        if g.view.span >= 1 { return }
        let w: CGFloat = g.size.width
        ctx.fill(Path(CGRect(x: 0, y: 1, width: w, height: 3)), with: .color(c.track))
        let x: CGFloat = CGFloat(g.view.a) * w
        ctx.fill(Path(CGRect(x: x, y: 1, width: max(6, CGFloat(g.view.span) * w), height: 3)), with: .color(c.accent))
    }
}
