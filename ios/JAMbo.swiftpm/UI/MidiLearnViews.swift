import SwiftUI

/// Голубая рамка цели в режиме LEARN (как в вебе).
let learnBlue = Color(red: 0.25, green: 0.62, blue: 1.0)

/// Полоса MIDI LEARN (S13b, как ui/learn.ts веба): внизу экрана по центру, поверх клавиатуры; цель и её источники,
/// TURN / PRESS (что выбирает тап по ручке), UNMAP, DONE.
struct LearnBar: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(describe)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.accentText)
                .lineLimit(1)
                .truncationMode(.tail)
            MenuItem(title: "TURN", current: !model.midiLearn.press) { model.midiLearn.press = false }.frame(width: 64)
            MenuItem(title: "PRESS", current: model.midiLearn.press) { model.midiLearn.press = true }.frame(width: 64)
            MenuItem(title: "UNMAP", enabled: unmapEnabled) { model.learnUnmap() }.frame(width: 72)
            MenuItem(title: "DONE") { model.setLearn(false) }.frame(width: 64)
        }
        .padding(.leading, 14)
        .padding(6)
        .frame(height: 48)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.accent, lineWidth: 2))
    }

    private var unmapEnabled: Bool {
        guard let t = model.midiLearn.target else { return false }
        return model.midiMapping(t) != nil
    }

    private var describe: String {
        guard let t = model.midiLearn.target else { return "MIDI LEARN · Tap a knob or button on screen" }
        guard let m = model.midiMapping(t) else { return t.label + " · Move a control on your MIDI device" }
        let hint: String = model.midiLearn.last.isEmpty ? " · Move a control to remap" : ""
        return t.label + "  ←  " + m.src.label + hint
    }
}

/// Метки целей в режиме LEARN: голубая рамка у выбранной, полупрозрачная жёлтая заливка у назначенных и в правом
/// верхнем углу — источник («CC 20», «N 36»; нажатие ручки — «P 36»).
struct MidiMark: View {
    let model: AppModel
    let targets: [MidiTarget]
    @Environment(\.theme) private var theme

    var body: some View {
        let maps: [MidiMapping] = targets.compactMap { model.midiMapping($0) }
        let picked: Bool = model.midiLearn.target.map { targets.contains($0) } ?? false
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: Layout.radius)
                .fill(maps.isEmpty ? Color.clear : theme.accent.opacity(0.22))
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(0..<maps.count, id: \.self) { i in
                    Text(MidiMark.short(maps[i]))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.text)
                }
            }
            .padding(4)
        }
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(picked ? learnBlue : Color.clear, lineWidth: 2))
    }

    static func short(_ m: MidiMapping) -> String {
        if case .press = m.target { return "P \(m.src.num)" }
        return m.src.short
    }
}

/// Кнопка — цель MIDI: в режиме LEARN поверх неё метки, тап выбирает цель (действие кнопки не выполняется).
struct MidiTargetModifier: ViewModifier {
    let model: AppModel
    let target: MidiTarget

    func body(content: Content) -> some View {
        content.overlay {
            if model.midiLearn.on {
                MidiMark(model: model, targets: [target])
                    .contentShape(Rectangle())
                    .onTapGesture { model.learnTap(target) }
            }
        }
    }
}

extension View {
    func midiTarget(_ model: AppModel, _ name: String) -> some View {
        return modifier(MidiTargetModifier(model: model, target: .button(name)))
    }

    /// Метки на элементе, который сам перехватывает касания в LEARN (ручки, клавиши, шаги, ячейки).
    func midiMarks(_ model: AppModel, _ targets: [MidiTarget]) -> some View {
        return overlay {
            if model.midiLearn.on { MidiMark(model: model, targets: targets).allowsHitTesting(false) }
        }
    }
}

/// Метка маленькой кнопки (M, S, ● в MIX) в режиме LEARN: заливка и рамка — на кнопке, источник — справа, рядом
/// с кнопкой (как в вебе). Касания не принимает — цель выбирает сетка ручек.
struct MidiSmallMark: View {
    let model: AppModel
    let target: MidiTarget
    let frame: CGRect
    @Environment(\.theme) private var theme

    var body: some View {
        let m: MidiMapping? = model.midiMapping(target)
        let picked: Bool = model.midiLearn.target == target
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(m == nil ? Color.clear : theme.accent.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(picked ? learnBlue : Color.clear, lineWidth: 2))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            if let m = m {
                Text(MidiMark.short(m))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .fixedSize()
                    .offset(x: frame.maxX + 3, y: frame.midY - 6)
            }
        }
        .allowsHitTesting(false)
    }
}
