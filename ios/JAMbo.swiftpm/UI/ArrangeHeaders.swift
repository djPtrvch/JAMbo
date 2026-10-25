import SwiftUI

/// Заголовки дорожек аранжировщика (S15c): по строке на дорожку, прокрутка и высота — как у таймлайна. Двойной тап —
/// меню дорожки (COPY, PASTE, DUPLICATE, цвет).
struct ArrHeaders: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let p: Project = model.project
        let port: ArrPort = model.arrPort
        return GeometryReader { geo in
            let m = ArrMetrics(size: CGSize(width: geo.size.width, height: geo.size.height), port: port,
                               tracks: p.tracks.count, end: p.arrangeEnd, expanded: model.settings.arrangeExpanded)
            ZStack(alignment: .topLeading) {
                ForEach(0..<p.tracks.count, id: \.self) { t in
                    ArrHeaderRow(model: model, index: t)
                        .frame(width: geo.size.width, height: m.rowH - 2)
                        .offset(x: 0, y: rowTop(t, port, geo.size))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // Строки — только под линейкой таймлайна и в пределах окна.
            .mask(VStack(spacing: 0) {
                Color.clear.frame(height: ArrMetrics.top)
                Color.black
            })
        }
    }

    /// Верх строки t — как у таймлайна (прокрутка по Y — из вида с той же шириной таймлайна не зависит).
    private func rowTop(_ t: Int, _ port: ArrPort, _ size: CGSize) -> CGFloat {
        let m = ArrMetrics(size: size, port: port, tracks: model.project.tracks.count, end: 0, expanded: model.settings.arrangeExpanded)
        return m.rowY(t) + 1
    }
}

/// Строка заголовка: цвет дорожки, имя (тап — выбор), возврат к таймлайну, M, S, измеритель, мини-фейдер.
struct ArrHeaderRow: View {
    let model: AppModel
    let index: Int
    @State private var lastTap: Date? = nil
    @State private var touching: Bool = false
    @State private var scrolled: Bool = false
    @State private var baseY: CGFloat = 0
    @Environment(\.theme) private var theme

    var body: some View {
        if index < model.project.tracks.count {
            row(model.project.tracks[index])
        } else {
            Color.clear
        }
    }

    private func row(_ t: Track) -> some View {
        let selected: Bool = model.channel == .track && model.selectedTrack == index
        // Цвет по умолчанию — заголовок как строка дорожек; свой цвет (меню дорожки) — заголовок целиком этим цветом.
        let own: Bool = t.color != ArrPalette.defaultColor
        let bg: Color = own ? ArrColors.color(t.color) : theme.trackBg
        let fg: Color = own ? ArrColors.text : theme.text
        return HStack(spacing: 5) {
            Text(t.name)
                .font(.system(size: 12, weight: selected ? .heavy : .semibold))
                .lineLimit(1)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
            ArrToggle(title: "M", on: t.mute, color: theme.rec) { model.toggleMute(index) }
            ArrToggle(title: "S", on: t.solo, color: theme.accent) { model.toggleSolo(index) }
            ArrMeter(model: model, track: index).frame(width: MeterBars.width)
            ArrFader(model: model, track: index).frame(width: 26)
        }
        .padding(.horizontal, 6)
        .background(bg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? theme.accent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(touch)
    }

    /// Палец вверх-вниз — прокрутка дорожек (EXPANDED; свайпов mute и solo нет — решение пользователя); без сдвига — тап.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !touching {
                    touching = true
                    scrolled = false
                    baseY = model.arrPort.y
                }
                let dy: CGFloat = g.translation.height
                if !scrolled && abs(dy) >= 8 { scrolled = true }
                if scrolled && model.settings.arrangeExpanded { model.arrPort.y = max(0, baseY - dy) }
            }
            .onEnded { _ in
                touching = false
                if !scrolled { tapped() }
            }
    }

    /// Тап — выбор дорожки; второй тап за 0,3 с — меню дорожки.
    private func tapped() {
        let now = Date()
        if let l = lastTap, now.timeIntervalSince(l) < 0.3 {
            lastTap = nil
            model.arrMenu = .track(track: index, anchor: .zero)
            return
        }
        lastTap = now
        model.select(track: index)
    }
}

/// Кнопка M или S: окантовка цветом, включённая — горит (как в MIX).
struct ArrToggle: View {
    let title: String
    let on: Bool
    let color: Color
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(on ? (title == "M" ? Color.white : theme.onAccent) : color)
            .frame(width: 22, height: 20)
            .background(on ? color : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}

/// Измеритель дорожки — те же полосы, что у измерителя справа (моно, 9 px).
struct ArrMeter: View {
    let model: AppModel
    let track: Int
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let data = model.meters.bars(track, stereo: false)
            let muted: Bool = track < model.project.tracks.count && !model.project.audible(track)
            Canvas { ctx, size in
                MeterBars.draw(ctx, CGRect(x: 0, y: 3, width: size.width, height: max(4, size.height - 6)), data,
                               theme: theme, muted: muted)
            }
        }
    }
}

/// Регулятор громкости — круглый (пока; решение пользователя): тот же регулятор, что справа у дорожки (SETTINGS →
/// LEVEL: ABSOLUTE — громкость MIX, RELATIVE — подстройка); палец вверх-вниз — 120 pt на всю шкалу; одна запись UNDO.
struct ArrFader: View {
    let model: AppModel
    let track: Int
    @State private var start: Double? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let v: Double = model.meterVol(track)
        let range: Double = -Params.volMin
        let f: Double = max(0, min(1, (v - Params.volMin) / range))
        return Canvas { ctx, size in
            let d: CGFloat = min(size.width, size.height) - 4
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = d / 2
            let a0: Double = 135
            let a1: Double = a0 + 270 * f
            var track = Path()
            track.addArc(center: c, radius: r, startAngle: .degrees(a0), endAngle: .degrees(405), clockwise: false)
            ctx.stroke(track, with: .color(theme.meterTrack), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
            ctx.stroke(arc, with: .color(theme.text), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            let rad: Double = a1 * Double.pi / 180
            let px: CGFloat = c.x + CGFloat(cos(rad)) * (r - 4)
            let py: CGFloat = c.y + CGFloat(sin(rad)) * (r - 4)
            var tick = Path()
            tick.move(to: c)
            tick.addLine(to: CGPoint(x: px, y: py))
            ctx.stroke(tick, with: .color(theme.text), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil {
                    start = model.meterVol(track)
                    model.beginGesture()
                }
                let dy: Double = Double(-g.translation.height / 120)
                let s: Double = start ?? 0
                let range: Double = -Params.volMin
                model.setMeterVol(track, s + dy * range)
            }
            .onEnded { _ in
                guard start != nil else { return }
                start = nil
                model.endGesture()
            }
    }
}
