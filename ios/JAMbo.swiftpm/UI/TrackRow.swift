import SwiftUI

/// Строка дорожек: MIX | 1…N | MST. Тап — выбор; свайп вниз — mute, вверх — solo (срабатывает на ~24 px).
struct TrackRow: View {
    let model: AppModel
    let layout: Layout

    var body: some View {
        HStack(spacing: Layout.gap) {
            ChannelCell(model: model, title: "MIX", channel: .mix).frame(width: layout.step)
            ForEach(0..<model.project.tracks.count, id: \.self) { i in
                TrackCell(model: model, index: i)
            }
            ChannelCell(model: model, title: "MST", channel: .master).frame(width: layout.step)
        }
        .frame(height: Layout.trackHeight)
    }
}

struct ChannelCell: View {
    let model: AppModel
    let title: String
    let channel: Channel
    @Environment(\.theme) private var theme

    var body: some View {
        let selected: Bool = model.channel == channel
        return Text(title)
            .font(.system(size: 12, weight: selected ? .heavy : .bold))
            .tracking(0.7)
            .foregroundStyle(selected ? theme.text : theme.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.trackBg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(selected ? theme.accent : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { model.select(channel: channel) }
    }
}

struct TrackCell: View {
    let model: AppModel
    let index: Int
    @State private var swiped: Bool = false
    @State private var touching: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        // Дорожку могли только что удалить, а ячейка ещё не убрана — пусто вместо падения.
        if index < model.project.tracks.count {
            cell(model.project.tracks[index])
        } else {
            Color.clear
        }
    }

    private func cell(_ t: Track) -> some View {
        let selected: Bool = model.channel == .track && model.selectedTrack == index
        // Выбранная — всегда жёлтая рамка (и заглушённая: о mute говорит красная M), остальные заглушённые — красная.
        let border: Color = selected ? theme.accent : (t.mute ? theme.rec : Color.clear)
        return ZStack(alignment: .topTrailing) {
            // Выбранная дорожка — имя заметно жирнее.
            Text(t.name)
                .font(.system(size: 15, weight: selected ? .heavy : .semibold))
                .lineLimit(1)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            stateLetter(t)
        }
        .overlay(alignment: .topLeading) { morphDot(t) }
        .background(background(t), in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(border, lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(touch)
    }

    private func background(_ t: Track) -> Color {
        let flash: Bool = model.live.flashing[index] && !t.mute
        let base: Color = flash ? theme.flash : theme.trackBg
        return t.solo ? theme.accent.opacity(flash ? 0.55 : 0.35) : base
    }

    /// Жёлтая точка: параметры дорожки меняли в режиме MORPH.
    @ViewBuilder
    private func morphDot(_ t: Track) -> some View {
        if t.morphEdited {
            Circle().fill(theme.accent).frame(width: 6, height: 6).padding(.leading, 7).padding(.top, 6)
        }
    }

    @ViewBuilder
    private func stateLetter(_ t: Track) -> some View {
        if t.mute || t.solo {
            Text(t.mute ? "M" : "S")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(t.mute ? theme.rec : theme.accent)
                .padding(.top, 3)
                .padding(.trailing, 7)
        }
    }

    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !touching {
                    touching = true
                    swiped = false
                    model.ensureAudio()
                }
                let dy: CGFloat = g.translation.height
                if !swiped && abs(dy) >= 24 {
                    swiped = true
                    model.swipe(track: index, down: dy > 0)
                }
            }
            .onEnded { _ in
                touching = false
                // Выбор дорожки — тапом; свайп (mute/solo) выбор не меняет: окно MIX и выбранная дорожка остаются.
                if !swiped { model.select(track: index) }
            }
    }
}
