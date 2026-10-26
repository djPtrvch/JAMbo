import SwiftUI

/// Строка дорожек: MIX | 1…N | MST. Тап — выбор; свайп вниз — mute, вверх — solo (срабатывает на ~24 px).
struct TrackRow: View {
    let model: AppModel
    let layout: Layout

    var body: some View {
        let _ = RedrawMeter.hit(.tracks)
        HStack(spacing: Layout.gap) {
            ChannelCell(model: model, title: "MIX", channel: .mix).frame(width: layout.step).midiTarget(model, "MIX")
            ForEach(0..<model.project.tracks.count, id: \.self) { i in
                TrackCell(model: model, index: i).midiTarget(model, "T\(i + 1)")
            }
            ChannelCell(model: model, title: "MST", channel: .master).frame(width: layout.step).midiTarget(model, "MST")
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
            // Жирность — как у дорожек: выбранная heavy, остальные semibold.
            .font(.system(size: 12, weight: selected ? .heavy : .semibold))
            .tracking(0.7)
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if channel == .master { StemRecDot(model: model, channel: StemRing.master) }
            }
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

    /// Ход игры (мигание) пересчитывает все ячейки, рисуется только дорожка, у которой что-то изменилось (S14c).
    private func cell(_ t: Track) -> some View {
        let selected: Bool = model.channel == .track && model.selectedTrack == index
        let flash: Bool = index < model.live.flashing.count && model.live.flashing[index] && !t.mute
        let face = TrackFace(name: t.name, selected: selected, mute: t.mute, solo: t.solo, flash: flash)
        return face.equatable()
            .overlay(alignment: .topLeading) { morphDot(t) }
            .contentShape(Rectangle())
            .gesture(touch)
    }

    /// Жёлтая точка: параметры дорожки меняли в режиме MORPH; красная мигающая — пишется стем (жёлтая — правее).
    private func morphDot(_ t: Track) -> some View {
        HStack(spacing: 4) {
            StemRecDot(model: model, channel: index)
            if t.morphEdited {
                Circle().fill(theme.accent).frame(width: 6, height: 6).padding(.leading, 7).padding(.top, 6)
            }
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

/// Картинка дорожки: имя, M / S, заливка (мигание, mute, solo), рамка; точки MORPH и стема — поверх, в TrackCell.
struct TrackFace: View, Equatable {
    let name: String
    let selected: Bool
    let mute: Bool
    let solo: Bool
    let flash: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = RedrawMeter.hit(.trackCell)
        // Как в вебе: выбранная — жёлтый контур, заглушённая — красный (перекрывает выбор) и красная заливка.
        let border: Color = mute ? theme.rec : (selected ? theme.accent : Color.clear)
        ZStack(alignment: .topTrailing) {
            // Выбранная дорожка — имя крупнее и жирнее; невыбранные — как MIX и MST (12, semibold, разрядка); цвет — белый.
            Text(name)
                .font(.system(size: selected ? 15 : 12, weight: selected ? .heavy : .semibold))
                .tracking(selected ? 0 : 0.7)
                .lineLimit(1)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            stateLetter
        }
        .background(background, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(border, lineWidth: 1))
    }

    private var background: Color {
        let base: Color = flash ? theme.flash : theme.trackBg
        // Mute — красная заливка, solo — жёлтая (35 % поверх фона дорожки, при мигании solo — 55 %).
        if mute { return theme.rec.opacity(0.35) }
        return solo ? theme.accent.opacity(flash ? 0.55 : 0.35) : base
    }

    @ViewBuilder
    private var stateLetter: some View {
        if mute || solo {
            Text(mute ? "M" : "S")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(mute ? theme.rec : theme.accent)
                .padding(.top, 3)
                .padding(.trailing, 7)
        }
    }
}

/// Мигающая красная точка в левом верхнем углу дорожки (MST — запись мастера): идёт запись; за 5 с до конца — чаще.
struct StemRecDot: View {
    let model: AppModel
    let channel: Int
    @Environment(\.theme) private var theme

    var body: some View {
        if model.stemRecording.contains(channel) {
            TimelineView(.periodic(from: .now, by: 0.05)) { tl in
                let dot = model.stemDot(channel)
                let period: Double = dot.ending ? 0.3 : 1
                let phase: Double = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                Circle().fill(theme.rec).frame(width: 6, height: 6)
                    .opacity(phase < period / 2 ? 1 : 0)
                    .padding(.leading, 7).padding(.top, 6)
            }
            .allowsHitTesting(false)
        }
    }
}
