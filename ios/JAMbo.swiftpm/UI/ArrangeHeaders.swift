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
                               tracks: p.tracks.count, end: p.arrangeEnd, expanded: model.settings.arrangeExpanded,
                           inset: model.arrInset, ref: model.arrRefShown)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    // Все строки — одним столбцом с одним сдвигом (прокрутка — без отставания строк от таймлайна).
                    VStack(spacing: ArrMetrics.gap) {
                        ForEach(0..<p.tracks.count, id: \.self) { t in
                            ArrHeaderRow(model: model, index: t, rowH: m.rowH)
                                .frame(width: geo.size.width, height: m.rowH)
                                .allowsHitTesting(m.tappable(m.rowY(t)))
                        }
                    }
                    .offset(x: 0, y: m.rowY(0))
                    .transaction { $0.animation = nil }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                // Строки — только под линейкой таймлайна (и строкой REF) и в пределах окна.
                .mask(VStack(spacing: 0) {
                    Color.clear.frame(height: m.body)
                    Color.black
                })
                // Строка REF (S15g) — над дорожками, не прокручивается.
                if m.refRow {
                    ArrRefHeader(model: model)
                        .frame(width: geo.size.width, height: m.rowH)
                        .offset(x: 0, y: ArrMetrics.top)
                }
            }
        }
    }
}

/// Строка заголовка: сверху регулятор громкости, снизу имя слева (тап — выбор, двойной тап — меню дорожки) и M, S
/// справа в строку (решение пользователя: без метров).
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
        // Отступ от краёв — один со всех сторон; сверху регулятор громкости, снизу имя слева и M, S в строку справа
        // (решение пользователя).
        let pad: CGFloat = 8
        // Низкая строка (COMPACT) — без регулятора.
        let vol: Bool = rowH >= 44
        let side: CGFloat = max(10, min(24, rowH - 2 * pad - (vol ? ArrVolume.height + 6 : 0)))
        return VStack(spacing: 6) {
            if vol { ArrVolume(model: model, channel: index) }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 5) {
                Text(t.name)
                    .font(.system(size: 12, weight: selected ? .heavy : .semibold))
                    .lineLimit(1)
                    .foregroundStyle(fg)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                HStack(spacing: 4) {
                    ArrToggle(title: "M", on: t.mute, color: theme.rec, side: side) { model.toggleMute(index) }
                    ArrToggle(title: "S", on: t.solo, color: theme.accent, side: side) { model.toggleSolo(index) }
                }
            }
        }
        .padding(pad)
        // Заголовок — на всю высоту строки дорожки (как блоки).
        .frame(maxHeight: .infinity)
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

/// Заголовок строки REF: сверху регулятор громкости REF; ниже две строки (решение пользователя): REF и темп файла
/// (TempoDetect), ниже — имя файла;
/// двойной тап — меню REF (LOAD, DELETE).
struct ArrRefHeader: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let name: String = model.project.arrange.ref?.name ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            // Громкость REF — регулятор сверху, как у дорожек (измерителя справа в аранжировщике нет).
            ArrVolume(model: model, channel: Levels.ref).padding(.bottom, 4)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text("REF").font(.system(size: 12, weight: .heavy)).foregroundStyle(theme.text)
                Spacer(minLength: 0)
                Text(model.refBpmText).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(theme.text)
            }
            Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.dim).lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(theme.trackBg, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6,
                                                              bottomTrailingRadius: 0, topTrailingRadius: 0))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.arrMenu = .ref }
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

/// Регулятор громкости в заголовке (вместо измерителя справа — решение пользователя, на пробу): дорожка — как
/// регулятор измерителя (SETTINGS → LEVEL: ABSOLUTE — громкость MIX, RELATIVE — подстройка), REF — громкость
/// референса; −∞…0 dB, палец вбок на всю ширину — вся шкала; справа — громкость в dB.
struct ArrVolume: View {
    let model: AppModel
    let channel: Int
    @State private var start: Double? = nil
    @Environment(\.theme) private var theme
    static let height: CGFloat = 16

    var body: some View {
        let v: Double = model.meterVol(channel)
        let f: CGFloat = CGFloat(max(0, min(1, (v - Params.volMin) / -Params.volMin)))
        return HStack(spacing: 6) {
            GeometryReader { geo in
                let w: CGFloat = geo.size.width
                let thumbW: CGFloat = 8
                let x: CGFloat = thumbW / 2 + f * (w - thumbW)
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.meterTrack).frame(height: 4)
                    Capsule().fill(theme.accent).frame(width: x, height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.text)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.bg, lineWidth: 1.5))
                        .frame(width: thumbW, height: ArrVolume.height)
                        .shadow(color: Color.black.opacity(0.4), radius: 2, y: 1)
                        .position(x: x, y: ArrVolume.height / 2)
                }
                .frame(width: w, height: ArrVolume.height)
                .contentShape(Rectangle())
                .gesture(drag(w))
            }
            Text(MeterColumn.fmtVol(v))
                .font(.system(size: 9)).monospacedDigit()
                .foregroundStyle(theme.dim)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: ArrVolume.height)
    }

    private func drag(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil {
                    start = model.meterVol(channel)
                    model.beginGesture()
                }
                let dx: Double = Double(g.translation.width / max(1, w))
                model.setMeterVol(channel, (start ?? 0) + dx * -Params.volMin)
            }
            .onEnded { _ in
                guard start != nil else { return }
                start = nil
                model.endGesture()
            }
    }
}
