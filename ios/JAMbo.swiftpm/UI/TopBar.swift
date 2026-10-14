import SwiftUI

/// Верхняя панель: меню, BPM, метроном | SCALE, ROOT, UNDO, PLAY, REC, REDO, AUTO, EQ | PATTERNS, ARRANGE, CPU.
/// Работают меню, BPM, метроном, UNDO, PLAY, REDO; остальные — на своих местах, серые (S1c–S5).
struct TopBar: View {
    let model: AppModel
    @Binding var menuOpen: Bool

    var body: some View {
        HStack(spacing: Layout.gap) {
            leftGroup
            middle
            rightGroup
        }
        .frame(height: Layout.topHeight)
    }

    private var leftGroup: some View {
        HStack(spacing: Layout.gap) {
            BurgerButton { menuOpen.toggle() }.frame(width: 52)
            BpmField(model: model)
            MetronomeButton(model: model).frame(width: 52)
        }
        .frame(width: Layout.leftColumn)
    }

    private var middle: some View {
        let half: CGFloat = (Layout.topButton - Layout.gap) / 2
        return HStack(spacing: Layout.gap) {
            TopField(label: "SCALE", value: "Min").frame(width: Layout.topButton)
            TopField(label: "ROOT", value: "C")
            HistoryButton(symbol: "arrow.uturn.backward", enabled: model.canUndo) { model.undo() }
                .frame(width: Layout.topButton)
            PlayButton(model: model).frame(width: half)
            TopIcon(symbol: "circle.fill", tint: .rec).frame(width: half)
            HistoryButton(symbol: "arrow.uturn.forward", enabled: model.canRedo) { model.redo() }
                .frame(width: Layout.topButton)
            TopIcon(symbol: "waveform.path")
            TopText(title: "EQ").frame(width: Layout.topButton)
        }
    }

    private var rightGroup: some View {
        HStack(spacing: Layout.gap) {
            TopText(title: "PATTERNS").frame(width: Layout.topButton)
            TopText(title: "ARRANGE").frame(width: Layout.topButton)
            CPUIndicator(meter: model.audio.core.cpu).frame(width: Layout.meterWidth)
        }
    }
}

/// Неактивная пока кнопка-значок верхней панели.
struct TopIcon: View {
    enum Tint { case normal, rec }
    let symbol: String
    var tint: Tint = .normal
    @Environment(\.theme) private var theme

    var body: some View {
        let color: Color = tint == .rec ? theme.rec : theme.off
        return Image(systemName: symbol)
            .font(.system(size: tint == .rec ? 12 : 18, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(tint == .rec ? theme.rec : Color.clear, lineWidth: 1))
    }
}

/// Неактивная пока кнопка-надпись верхней панели.
struct TopText: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(theme.off)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
    }
}

/// Поле с подписью над значением (SCALE, ROOT; пока не меняются — S1c).
struct TopField: View {
    let label: String
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 9)).tracking(0.8).foregroundStyle(theme.dim)
            Text(value).font(.system(size: 15)).foregroundStyle(theme.off)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
    }
}

/// PLAY: жёлтая окантовка, при игре горит жёлтым; срабатывает в момент касания.
struct PlayButton: View {
    let model: AppModel
    @State private var down: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.playing
        return Image(systemName: "play.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(on ? theme.onAccent : theme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.accent : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.accent, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(touchDown)
    }

    private var touchDown: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if down { return }
                down = true
                model.togglePlay()
            }
            .onEnded { _ in down = false }
    }
}

/// Метроном: тап включает; при игре мигает на долях (акцент — жёлтым).
struct MetronomeButton: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.metronome
        let live: LiveState = model.live
        let bg: Color = live.beatFlash ? (live.beatAccent ? theme.accentSoft : theme.panel2) : theme.panel
        return Image(systemName: "metronome")
            .font(.system(size: 20))
            .foregroundStyle(on ? theme.text : theme.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(on ? theme.text : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleMetronome() }
    }
}

/// UNDO / REDO: закруглённая стрелка; нечего отменять или возвращать — серая.
struct HistoryButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(enabled ? theme.text : theme.off)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
