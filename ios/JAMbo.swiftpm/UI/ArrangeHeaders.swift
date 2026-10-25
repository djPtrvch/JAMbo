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
                // Все строки — одним столбцом с одним сдвигом (прокрутка — без отставания строк от таймлайна).
                VStack(spacing: 0) {
                    ForEach(0..<p.tracks.count, id: \.self) { t in
                        ArrHeaderRow(model: model, index: t, rowH: m.rowH)
                            .padding(.vertical, 1)
                            .frame(width: geo.size.width, height: m.rowH)
                            .allowsHitTesting(m.tappable(m.rowY(t)))
                    }
                }
                .offset(x: 0, y: m.rowY(0))
                .transaction { $0.animation = nil }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // Строки — только под линейкой таймлайна и в пределах окна.
            .mask(VStack(spacing: 0) {
                Color.clear.frame(height: ArrMetrics.top)
                Color.black
            })
        }
    }
}

/// Строка заголовка: имя (тап — выбор, двойной тап — меню дорожки), M и S рядом (решение пользователя: без метров).
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
        // Цвет дорожки (меню дорожки) — только у блоков; заголовок — как строка дорожек (решение пользователя).
        let bg: Color = theme.trackBg
        let fg: Color = theme.text
        return HStack(spacing: 5) {
            Text(t.name)
                .font(.system(size: 12, weight: selected ? .heavy : .semibold))
                .lineLimit(1)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
            // M и S рядом; в низких строках (COMPACT) — меньше.
            let side: CGFloat = max(14, min(28, rowH - 12))
            HStack(spacing: 4) {
                ArrToggle(title: "M", on: t.mute, color: theme.rec, side: side) { model.toggleMute(index) }
                ArrToggle(title: "S", on: t.solo, color: theme.accent, side: side) { model.toggleSolo(index) }
            }
        }
        .padding(.horizontal, 6)
        .background(bg, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 0,
                                                    topTrailingRadius: 0))
        // Выбранная — две жёлтые линии сверху и снизу (продолжаются по всей строке таймлайна).
        .overlay(alignment: .top) { Rectangle().fill(selected ? theme.accent : Color.clear).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(selected ? theme.accent : Color.clear).frame(height: 1) }
        .contentShape(Rectangle())
        .gesture(touch)
    }

    /// Палец вверх-вниз — прокрутка дорожек (EXPANDED; свайпов mute и solo нет — решение пользователя); без сдвига — тап.
    /// Сдвиг — в координатах экрана: строка сама едет при прокрутке, в своих координатах палец «дёргался».
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
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
