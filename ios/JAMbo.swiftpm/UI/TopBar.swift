import SwiftUI

/// Верхняя панель: меню, BPM, метроном | SCALE, ROOT, UNDO, PLAY, REC, REDO, пианоролл, EQ | PATTERNS, ARRANGE, CPU.
/// ARRANGE — серая (позже); пианоролл (S8) — на месте AUTO (автоматизация — S13, место решим позже).
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
            BpmField(model: model).midiTarget(model, MidiButtons.bpm)
            MetronomeButton(model: model).frame(width: 52).midiTarget(model, "METRONOME")
        }
        .frame(width: Layout.leftColumn)
    }

    private var middle: some View {
        let half: CGFloat = (Layout.topButton - Layout.gap) / 2
        return HStack(spacing: Layout.gap) {
            ScaleField(model: model).frame(width: Layout.topButton)
            RootField(model: model)
            HistoryButton(symbol: "arrow.uturn.backward", enabled: model.canUndo || model.morphHeld) { model.undoTapped() }
                .frame(width: Layout.topButton)
                .midiTarget(model, "UNDO")
            PlayButton(model: model).frame(width: half)
                .midiTarget(model, "PLAY")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { model.sampleRec.playFrame = $0 }
            RecButton(model: model).frame(width: half).midiTarget(model, "REC")
            HistoryButton(symbol: "arrow.uturn.forward", enabled: model.canRedo) { model.redo() }
                .frame(width: Layout.topButton)
            RollButton(model: model).midiTarget(model, "ROLL")
            ViewButton(title: "EQ", on: model.eqView) { model.toggleEqView() }.frame(width: Layout.topButton)
                .midiTarget(model, "EQ")
        }
    }

    private var rightGroup: some View {
        HStack(spacing: Layout.gap) {
            PatternsButton(model: model).frame(width: Layout.topButton).midiTarget(model, "PATTERNS")
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

/// SCALE: палец вверх-вниз — 24 px на гамму; тап — меню (3 столбца).
struct ScaleField: View {
    let model: AppModel

    var body: some View {
        let names: [String] = Scales.all.map { $0.name }
        let i: Int = model.project.scale
        return DragField(label: "SCALE", value: names[i], pxPerUnit: 24,
                         get: { Double(model.project.scale) }, set: { model.setScale(Int($0)) },
                         tap: { frame in model.choice = ChoiceState(options: names, columns: 3, current: i, anchor: frame,
                                                                     pick: { model.setScale($0) }) },
                         model: model)
    }
}

/// ROOT: палец вверх-вниз — 24 px на полутон; тап — меню (4 столбца).
struct RootField: View {
    let model: AppModel

    var body: some View {
        let i: Int = model.project.root
        return DragField(label: "ROOT", value: Params.noteNames[i], pxPerUnit: 24,
                         get: { Double(model.project.root) }, set: { model.setRoot(Int($0)) },
                         tap: { frame in model.choice = ChoiceState(options: Params.noteNames, columns: 4, current: i, anchor: frame,
                                                                     pick: { model.setRoot($0) }) },
                         model: model)
    }
}

/// REC: красная точка, красная окантовка; включена — горит красным.
struct RecButton: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.recOn
        return Image(systemName: "circle.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(on ? Color.white : theme.rec)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.rec : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.rec, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleRec() }
    }
}

/// PATTERNS: сетка паттернов на месте центра; горит, пока открыта.
struct PatternsButton: View {
    let model: AppModel

    var body: some View {
        ViewButton(title: "PATTERNS", on: model.patternView) { model.togglePatterns() }
    }
}

/// Кнопка вида на месте центра (PATTERNS, EQ): горит, пока вид открыт.
struct ViewButton: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(on ? theme.bg : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.text : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
