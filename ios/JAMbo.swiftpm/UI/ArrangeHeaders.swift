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
                    ArrHeaderRow(model: model, index: t, rowH: m.rowH)
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
    let rowH: CGFloat
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
            // M над S; в COMPACT (низкие строки) — меньше.
            let side: CGFloat = max(10, min(20, (rowH - 8) / 2))
            VStack(spacing: 2) {
                ArrToggle(title: "M", on: t.mute, color: theme.rec, side: side) { model.toggleMute(index) }
                ArrToggle(title: "S", on: t.solo, color: theme.accent, side: side) { model.toggleSolo(index) }
            }
            ArrMeter(model: model, track: index).frame(width: MeterBars.width)
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
    var side: CGFloat = 20
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: max(7, side / 2), weight: .bold))
            .foregroundStyle(on ? (title == "M" ? Color.white : theme.onAccent) : color)
            .frame(width: side + 2, height: side)
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
