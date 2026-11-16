import SwiftUI

/// Окно микшера при MIX (16.11, решение пользователя): тап по окну полос слева открывает, двойной тап по кнопке MIX закрывает (крестика нет).
/// На месте центра (окно полос, сетка ручек, правая колонка; справа остаётся измеритель — фейдер мастера). Над каждой
/// дорожкой строки дорожек — фейдер, как измеритель справа: сверху громкость фейдера (число; подпись VOL — одна, над шкалой, на той же строке), метка клиппинга, полосы (стерео — две, моно — одна, пик-холд, выше 0 dB —
/// красные, заглушённая — серая, Duck — оранжевым сверху) с белой планкой громкости, снизу наибольший пик (число; тап —
/// сброс). Палец вверх-вниз — громкость (как регулятор справа, тот же ход); несколько
/// фейдеров сразу. Все полосы рисует один холст, касания — прозрачные места фейдеров.
struct MixerWindow: View {
    let model: AppModel
    let layout: Layout
    @State private var frame: CGRect = .zero
    /// Высота подписи сверху и снизу (две строки 9 px), метка клиппинга и зазоры — как у измерителя справа.
    static let labelH: CGFloat = 24
    static let clipH: CGFloat = 4
    static let gap: CGFloat = 4

    var body: some View {
        let xs: [CGFloat] = centers()
        // Шкала — по центру места MIX.
        let sx: CGFloat = model.tracksFrame.minX + layout.step / 2 - frame.minX
        return ZStack(alignment: .topTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
                ScopeCanvas(now: tl.date) { ctx, size in draw(ctx, size, xs, sx, tl.date.timeIntervalSinceReferenceDate) }
            }
            touches(xs)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
    }

    /// Середины дорожек строки дорожек (MIX | 1…N | MST, равные места) в координатах окна.
    private func centers() -> [CGFloat] {
        let n: Int = min(model.project.tracks.count, TrackTaps.tracks)
        let row: CGRect = model.tracksFrame
        if n == 0 || row == .zero || frame == .zero { return [] }
        let g: CGFloat = Layout.gap
        let side: CGFloat = layout.step
        let w: CGFloat = (row.width - 2 * side - CGFloat(n + 1) * g) / CGFloat(n)
        var xs: [CGFloat] = []
        for i in 0..<n {
            let x: CGFloat = row.minX + side + g + CGFloat(i) * (w + g) + w / 2
            xs.append(x - frame.minX)
        }
        return xs
    }

    /// Место полос по вертикали: под подписью и меткой клиппинга, над нижней подписью.
    private static func barsRect(_ h: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let top: CGFloat = labelH + gap + clipH + gap
        return (top, max(1, h - top - gap - labelH))
    }

    private func touches(_ xs: [CGFloat]) -> some View {
        GeometryReader { geo in
            let r = MixerWindow.barsRect(geo.size.height)
            ForEach(0..<xs.count, id: \.self) { i in
                FaderTouch(model: model, ch: i, labelTop: r.height + MixerWindow.gap)
                    .frame(width: 44, height: r.height + MixerWindow.gap + MixerWindow.labelH)
                    .position(x: xs[i], y: r.top + (r.height + MixerWindow.gap + MixerWindow.labelH) / 2)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ xs: [CGFloat], _ sx: CGFloat, _ now: Double) {
        let r = MixerWindow.barsRect(size.height)
        if !xs.isEmpty { scale(ctx, sx, r.top, r.height) }
        let m: MeterState = model.meters
        for i in 0..<xs.count where i < model.project.tracks.count {
            let x: CGFloat = xs[i]
            let stereo: Bool = model.trackStereo(i)
            let data: [(level: Float, hold: Float)] = m.bars(i, stereo: stereo)
            let w: CGFloat = MeterBars.span(data.count)
            let duck: Float = m.duckDb(i)
            let gr: CGFloat = duck <= -0.1 ? CGFloat(-duck / 24) : 0
            let bars = CGRect(x: x - w / 2, y: r.top, width: w, height: r.height)
            MeterBars.draw(ctx, bars, data, theme: theme, muted: !model.project.audible(i), gr: gr)
            let clip: Bool = m.clip(i, now: now)
            let mark = CGRect(x: x - 10.5, y: MixerWindow.labelH + MixerWindow.gap, width: 21, height: MixerWindow.clipH)
            ctx.fill(Path(roundedRect: mark, cornerRadius: 2), with: .color(clip ? theme.rec : theme.off))
            thumb(ctx, x, bars, model.meterVol(i))
            // Сверху — громкость фейдера (ярче, на строке VOL), снизу — наибольший пик: только числа.
            volText(ctx, MeterColumn.fmtVol(model.meterVol(i)), x)
            // Пик — посередине между низом полос и верхом строки дорожек (как строка VOL сверху).
            let pk = Text(MeterColumn.fmtDb(m.maxPeak[i])).font(.system(size: 9)).monospacedDigit().foregroundColor(theme.dim)
            ctx.draw(pk, at: CGPoint(x: x, y: (bars.maxY + size.height + Layout.gap) / 2), anchor: .center)
        }
        if !xs.isEmpty {
            volText(ctx, "VOL", sx)
            // Под шкалой — подпись строки пиков (тем же цветом, на той же высоте).
            let pk = Text("PEAK").font(.system(size: 9)).foregroundColor(theme.dim)
            ctx.draw(pk, at: CGPoint(x: sx, y: (r.top + r.height + size.height + Layout.gap) / 2), anchor: .center)
        }
    }

    /// Строка VOL (16.11, решение пользователя): подпись над шкалой и громкости над дорожками — на одной высоте,
    /// посередине между низом кнопок верхней панели и верхом полос; 9 px, ярче подписей (--text 75 %).
    private func volText(_ ctx: GraphicsContext, _ s: String, _ x: CGFloat) {
        let t = Text(s).font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundColor(theme.text.opacity(0.75))
        ctx.draw(t, at: CGPoint(x: x, y: 14), anchor: .center)
    }

    /// Шкала dB слева (над MIX, по центру его места; 16.11): 0…−60 через 6 dB — шкала полос и планок; подпись
    /// 9 px --dim и справа от неё короткая черта.
    private func scale(_ ctx: GraphicsContext, _ mid: CGFloat, _ top: CGFloat, _ h: CGFloat) {
        var ticks = Path()
        var db: Int = 0
        while db >= -60 {
            let y: CGFloat = top + h * CGFloat(-db) / 60
            ticks.move(to: CGPoint(x: mid + 6, y: y))
            ticks.addLine(to: CGPoint(x: mid + 14, y: y))
            let s: String = db == 0 ? "0" : "−\(-db)"
            let t = Text(s).font(.system(size: 9)).monospacedDigit().foregroundColor(theme.dim)
            ctx.draw(t, at: CGPoint(x: mid + 2, y: y), anchor: .trailing)
            db -= 6
        }
        ctx.stroke(ticks, with: .color(theme.gridStrong), lineWidth: 1)
    }

    /// Планка громкости — как у измерителя справа (30 × 8, цвет текста, обводка фоном, тень).
    private func thumb(_ ctx: GraphicsContext, _ x: CGFloat, _ bars: CGRect, _ vol: Double) {
        let f: CGFloat = CGFloat((vol - Params.volMin) / -Params.volMin)
        let y: CGFloat = bars.maxY - bars.height * max(0, min(1, f))
        let rect = CGRect(x: x - 15, y: y - 4, width: 30, height: 8)
        let shape = Path(roundedRect: rect, cornerRadius: 3)
        var sc = ctx
        sc.addFilter(.shadow(color: Color.black.opacity(0.4), radius: 2, y: 1))
        sc.fill(shape, with: .color(theme.text))
        ctx.stroke(shape, with: .color(theme.bg), lineWidth: 1.5)
    }
}

/// Место касания фейдера (полосы и нижняя подпись): палец вверх-вниз — громкость дорожки (ход — как у регулятора
/// справа); тап по нижней подписи (ниже labelTop) — сброс пика.
struct FaderTouch: View {
    let model: AppModel
    let ch: Int
    let labelTop: CGFloat
    @State private var start: Double? = nil

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil {
                    start = model.meterVol(ch)
                    model.beginGesture()
                }
                let dy: Double = Double(-g.translation.height / MeterColumn.travel)
                model.setMeterVol(ch, (start ?? 0) + dy * -Params.volMin)
            }
            .onEnded { g in
                guard start != nil else { return }
                start = nil
                model.endGesture()
                let still: Bool = abs(g.translation.height) < 4 && abs(g.translation.width) < 4
                if still && g.startLocation.y >= labelTop { model.meters.resetPeak(ch) }
            }
    }
}
