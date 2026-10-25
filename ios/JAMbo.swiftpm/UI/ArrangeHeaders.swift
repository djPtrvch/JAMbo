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
                               tracks: p.tracks.count, end: p.arrangeEnd)
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
        let m = ArrMetrics(size: size, port: port, tracks: model.project.tracks.count, end: 0)
        return m.rowY(t) + 1
    }
}

/// Строка заголовка: цвет дорожки, имя (тап — выбор), возврат к таймлайну, M, S, измеритель, мини-фейдер.
struct ArrHeaderRow: View {
    let model: AppModel
    let index: Int
    @State private var lastTap: Date? = nil
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
        return HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(ArrColors.color(t.color)).frame(width: 5).padding(.vertical, 4)
            Text(t.name)
                .font(.system(size: 12, weight: selected ? .heavy : .semibold))
                .lineLimit(1)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            ArrReturnButton(model: model, track: index)
            ArrToggle(title: "M", on: t.mute, color: theme.rec) { model.toggleMute(index) }
            ArrToggle(title: "S", on: t.solo, color: theme.accent) { model.toggleSolo(index) }
            ArrMeter(model: model, track: index).frame(width: MeterBars.width)
            ArrFader(model: model, track: index).frame(width: 46)
        }
        .padding(.horizontal, 6)
        .background(theme.trackBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? theme.accent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { tapped() }
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

/// Возврат дорожки к таймлайну: активна при игре, когда дорожка играет сетку (жёлтая), иначе — серая.
struct ArrReturnButton: View {
    let model: AppModel
    let track: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let off: Bool = model.playing && !model.arrFollowing(track)
        return Image(systemName: "arrow.uturn.backward")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(off ? theme.onAccent : theme.off)
            .frame(width: 22, height: 20)
            .background(off ? theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { model.returnToArrange(track) }
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

/// Мини-фейдер: тот же регулятор, что справа у дорожки (SETTINGS → LEVEL: ABSOLUTE — громкость MIX, RELATIVE —
/// подстройка); палец вбок — 120 pt на всю шкалу; одна запись UNDO на жест.
struct ArrFader: View {
    let model: AppModel
    let track: Int
    @State private var start: Double? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let v: Double = model.meterVol(track)
        let range: Double = -Params.volMin
        let f: CGFloat = CGFloat((v - Params.volMin) / range)
        return GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let fill: CGFloat = max(0, f * w)
            let knob: CGFloat = max(0, min(w - 6, fill - 3))
            ZStack(alignment: .leading) {
                Capsule().fill(theme.meterTrack).frame(height: 4)
                Capsule().fill(theme.text.opacity(0.5)).frame(width: fill, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(theme.text).frame(width: 6, height: 16).offset(x: knob)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(drag)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil {
                    start = model.meterVol(track)
                    model.beginGesture()
                }
                let dx: Double = Double(g.translation.width / 120)
                let s: Double = start ?? 0
                let range: Double = -Params.volMin
                model.setMeterVol(track, s + dx * range)
            }
            .onEnded { _ in
                guard start != nil else { return }
                start = nil
                model.endGesture()
            }
    }
}
