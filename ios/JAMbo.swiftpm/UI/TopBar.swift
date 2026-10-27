import SwiftUI

/// Верхняя панель: меню, BPM, метроном | SCALE, ROOT, UNDO, PLAY, REC, REDO, пианоролл, EQ | PATTERNS, ARRANGE, CPU.
/// ARRANGE (S15) — аранжировщик на месте центра; пианоролл (S8) — на месте AUTO (AUTO — во второй строке аранжировщика).
struct TopBar: View {
    let model: AppModel
    @Binding var menuOpen: Bool

    var body: some View {
        let _ = RedrawMeter.hit(.topBar)
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
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { model.sampleRec.scaleFrame = $0 }
                .topFrame(model, \.scale)
            RootField(model: model).topFrame(model, \.root)
            HistoryButton(symbol: "arrow.turn.up.left", enabled: model.canUndo || model.morphHeld) { model.undoTapped() }
                .frame(width: Layout.topButton)
                .topFrame(model, \.undo)
                .midiTarget(model, "UNDO")
            PlayButton(model: model).frame(width: half)
                .midiTarget(model, "PLAY")
            RecButton(model: model).frame(width: half).midiTarget(model, "REC")
            HistoryButton(symbol: "arrow.turn.up.right", enabled: model.canRedo) { model.redo() }
                .frame(width: Layout.topButton)
                .topFrame(model, \.redo)
                .midiTarget(model, "REDO")
            RollButton(model: model).midiTarget(model, "ROLL")
            ViewButton(title: "EQ", on: model.eqView) { model.toggleEqView() }.frame(width: Layout.topButton)
                .topFrame(model, \.eq)
                .midiTarget(model, "EQ")
        }
    }

    private var rightGroup: some View {
        HStack(spacing: Layout.gap) {
            PatternsButton(model: model).frame(width: Layout.topButton).topFrame(model, \.patterns)
                .midiTarget(model, "PATTERNS")
            // Запись аранжировки при закрытом окне — красный контур.
            ViewButton(title: "ARRANGE", on: model.arrangeView, ring: model.arrRecording && !model.arrangeView) {
                model.toggleArrange()
            }
            .frame(width: Layout.topButton)
            // Клип из сетки, принесённый на ARRANGE, открывает аранжировщик (AppModelCarry).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { model.arrangeButtonFrame = $0 }
            .topFrame(model, \.arrange)
                .midiTarget(model, "ARRANGE")
            CPUIndicator(meter: model.audio.core.cpu).frame(width: Layout.meterWidth)
        }
    }
}

/// Рамки кнопок верхней панели (координаты «root»): SCALE, ROOT, UNDO, REDO, EQ, PATTERNS, ARRANGE.
struct TopFrames: Equatable {
    var scale: CGRect = .zero
    var root: CGRect = .zero
    var undo: CGRect = .zero
    var redo: CGRect = .zero
    var eq: CGRect = .zero
    var patterns: CGRect = .zero
    var arrange: CGRect = .zero

    /// Все рамки уже известны.
    var ready: Bool {
        let a: Bool = scale.width > 0 && root.width > 0 && undo.width > 0 && redo.width > 0
        return a && eq.width > 0 && patterns.width > 0 && arrange.width > 0
    }
}

extension View {
    /// Запомнить рамку кнопки верхней панели (только при изменении).
    func topFrame(_ model: AppModel, _ key: WritableKeyPath<TopFrames, CGRect>) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { r in
            if model.topFrames[keyPath: key] != r { model.topFrames[keyPath: key] = r }
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

/// UNDO / REDO: стрелка с поворотом (arrow.turn.up — в одном стиле с repeat у LOOP ROW сетки паттернов); нечего
/// отменять или возвращать — серая.
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

/// ROOT: палец вверх-вниз — 24 px на полутон; тап — меню (4 столбца) от левого края ROOT до правого края REDO
/// (справа от ROOT: UNDO, PLAY и REC по половине, REDO — 3 кнопки и 3 зазора).
struct RootField: View {
    let model: AppModel

    var body: some View {
        let i: Int = model.project.root
        return DragField(label: "ROOT", value: Params.noteNames[i], pxPerUnit: 24,
                         get: { Double(model.project.root) }, set: { model.setRoot(Int($0)) },
                         tap: { frame in
                             let w: CGFloat = frame.width + 3 * Layout.gap + 3 * Layout.topButton
                             model.choice = ChoiceState(options: Params.noteNames, columns: 4, current: i, anchor: frame,
                                                        pick: { model.setRoot($0) }, width: w)
                         },
                         model: model)
    }
}

/// REC: красная точка, красная окантовка; включена — горит красным. SHIFT + тап — запись мастера (как ● MASTER при MIX,
/// общее состояние): готова — точка крупнее, пишет — она мигает, как точка на MST.
struct RecButton: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.recOn
        let master: Bool = model.stemLit(StemRing.master)
        return ZStack {
            if master {
                MasterRecDot(model: model, color: on ? Color.white : theme.rec)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(on ? Color.white : theme.rec)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(on ? theme.rec : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.rec, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if model.shiftHeld { model.stemTap(StemRing.master) } else { model.toggleRec() }
        }
    }
}

/// Крупная точка REC — запись мастера: готова — горит, пишет — мигает (за 5 с до конца — чаще), как StemRecDot.
struct MasterRecDot: View {
    let model: AppModel
    let color: Color

    var body: some View {
        if model.stemRecording.contains(StemRing.master) {
            TimelineView(.periodic(from: .now, by: 0.05)) { tl in
                let period: Double = model.stemDot(StemRing.master).ending ? 0.3 : 1
                let phase: Double = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                dot.opacity(phase < period / 2 ? 1 : 0)
            }
        } else {
            dot
        }
    }

    private var dot: some View {
        Circle().fill(color).frame(width: 20, height: 20)
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
    var ring: Bool = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(on ? theme.bg : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.text : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(ring ? theme.rec : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
