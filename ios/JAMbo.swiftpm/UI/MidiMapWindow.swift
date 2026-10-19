import SwiftUI

/// Окно MIDI MAP (S13c, как в Drambo и ui/mapedit.ts веба): плавающее, не закрывает экран, перетаскивается за
/// заголовок (положение — до перезапуска). В заголовке слева Unmap (на страницах выбора — «‹»), по центру цель,
/// справа ✕. Строка с «›» открывает выбор на месте списка. Движение контроллера, пока окно открыто, задаёт Number,
/// Channel, Event type и Input port.
struct MidiMapWindow: View {
    let model: AppModel
    let screen: CGSize
    @State private var dragFrom: CGPoint? = nil
    @Environment(\.theme) private var theme

    static let width: CGFloat = 340

    var body: some View {
        let p: CGPoint = position
        return VStack(spacing: 0) {
            header
            Divider().overlay(theme.line)
            MenuScroll { MidiMapBody(model: model).padding(12) }
        }
        .frame(width: MidiMapWindow.width, height: max(160, min(520, screen.height - p.y - 16)))
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 4)
        .offset(x: p.x, y: p.y)
        .modifier(MidiPresetAlert(model: model))
    }

    /// Левый верхний угол: перетащенный или по центру над полосой LEARN; в пределах экрана.
    private var position: CGPoint {
        let w: CGFloat = MidiMapWindow.width
        let p: CGPoint = model.midiLearn.mapPos ?? CGPoint(x: (screen.width - w) / 2, y: max(8, screen.height / 2 - 260))
        let x: CGFloat = min(screen.width - w - 8, max(8, p.x))
        let y: CGFloat = min(screen.height - 52, max(8, p.y))
        return CGPoint(x: x, y: y)
    }

    private var header: some View {
        let page: MidiMapPage = model.midiLearn.mapPage
        let title: String = page == .main ? (model.midiLearn.mapTarget?.label ?? "") : page.title
        return HStack(spacing: 6) {
            if page == .main {
                MenuItem(title: "Unmap", enabled: model.mapMapped, red: model.mapMapped) { model.mapUnmap() }.frame(width: 76)
            } else {
                MenuItem(title: "‹") { model.midiLearn.mapPage = .main }.frame(width: 44)
            }
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            MenuItem(title: "✕") { model.closeMap() }.frame(width: 44)
        }
        .padding(6)
        .frame(height: 50)
        .contentShape(Rectangle())
        .gesture(dragHeader)
    }

    private var dragHeader: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { g in
                if dragFrom == nil { dragFrom = position }
                let o: CGPoint = dragFrom ?? .zero
                model.midiLearn.mapPos = CGPoint(x: o.x + g.translation.width, y: o.y + g.translation.height)
            }
            .onEnded { _ in dragFrom = nil }
    }
}

/// Содержимое окна: главная страница или выбор.
struct MidiMapBody: View {
    let model: AppModel

    var body: some View {
        if let m = model.mapCurrent {
            switch model.midiLearn.mapPage {
            case .main: MidiMapMain(model: model, m: m)
            case .range: MidiRangeEditor(model: model, m: m)
            case .preset: MidiPresetPage(model: model)
            default: MidiMapOptions(model: model, m: m)
            }
        }
    }
}

/// Строка окна: подпись, значение и «›» (тап — страница выбора).
struct MidiMapLine: View {
    let label: String
    let value: String
    var go: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13)).foregroundStyle(theme.dim).lineLimit(1)
            if go != nil { Text("›").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.dim) }
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { go?() }
    }
}

/// Главная страница: Preset, пояснение; Number, Channel, Event type, Control type, Encoder, Range, Action, Condition;
/// ниже — порты: Input port и Feedback port.
struct MidiMapMain: View {
    let model: AppModel
    let m: MidiMapping
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line("Preset", presetName, .preset)
            SettingsNote(text: model.mapMapped ? "Move a control to remap."
                : "Not mapped yet — move a control on your MIDI device or set the fields.").padding(.vertical, 6)
            MidiNumberLine(model: model, m: m)
            line("Channel", "\(m.src.ch + 1)", .channel)
            line("Event type", m.src.type == .cc ? "CC" : "Note", .event)
            line("Control type", m.control.title, .control)
            if continuous && m.control == .rel { line("Encoder", MidiMapOptions.encName(m.enc), .encoder) }
            if showsRange { line("Range", "\(pct(m.min)) – \(pct(m.max)) %", .range) }
            if case .press = m.target { actionLine }
            line("Condition", MidiMapOptions.condName(m), .cond)
            Divider().overlay(theme.line).padding(.vertical, 6)
            line("Input port", model.midiPortName(m.input, inputs: true, none: "Any"), .port)
            line("Feedback port", feedbackName, .feedback)
        }
    }

    private var continuous: Bool { return model.midiContinuous(m.target) }

    /// Action нажатия ручки; при KNOB PRESS = TOUCH (MIDI → MAPPING) — как палец, без выбора.
    @ViewBuilder
    private var actionLine: some View {
        if model.settings.midi.pressTouch {
            MidiMapLine(label: "Action", value: "Touch (tap, double tap)")
        } else {
            line("Action", MidiMapOptions.actionName(m.press), .action)
        }
    }

    /// Range — у ручек и регуляторов, у нажатия ручки — с действием PARAM.
    private var showsRange: Bool {
        if case .press = m.target { return m.press == .param && !model.settings.midi.pressTouch }
        return continuous
    }

    private var presetName: String {
        let p: String = model.settings.midi.preset
        if p.isEmpty { return "None" }
        return model.presetModified ? p + " *" : p
    }

    private var feedbackName: String {
        let def: String = model.midiPortName(model.settings.midi.feedback, inputs: false, none: "None")
        switch m.port {
        case .standard: return "Default (\(def))"
        case .none: return "None"
        case .device(let id): return model.midiPortName(id, inputs: false, none: "None")
        }
    }

    private func pct(_ n: Double) -> Int { return Int((n * 100).rounded()) }

    private func line(_ label: String, _ value: String, _ go: MidiMapPage) -> some View {
        MidiMapLine(label: label, value: value) { model.midiLearn.mapPage = go }
    }
}

/// Number: ввод числом 0–127 (× очищает); занятый другой целью номер — жёлтое «used by …» (при записи маппинг
/// переходит сюда).
struct MidiNumberLine: View {
    let model: AppModel
    let m: MidiMapping
    @State private var text: String = ""
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text("Number").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
            Spacer(minLength: 8)
            if let w = warning { Text("used by " + w).font(.system(size: 11)).foregroundStyle(theme.accent).lineLimit(1) }
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13).monospacedDigit())
                .frame(width: 48)
                .focused($focused)
                .tint(theme.text)
                .onSubmit { commit() }
            Text("×").font(.system(size: 16)).foregroundStyle(theme.dim)
                .onTapGesture {
                    text = ""
                    focused = true
                }
        }
        .frame(height: 40)
        .onAppear { text = "\(m.src.num)" }
        .onChange(of: m.src.num) { _, n in if !focused { text = "\(n)" } }
        .onChange(of: focused) { _, f in if !f { commit() } }
        .onChange(of: text) { _, t in
            let digits: String = String(t.filter { $0.isNumber }.prefix(3))
            if digits != t { text = digits }
        }
    }

    private var warning: String? {
        guard let n = Int(text), n <= 127 else { return nil }
        return model.mapClash(n)
    }

    private func commit() {
        guard let n = Int(text), n <= 127 else {
            text = "\(m.src.num)"
            return
        }
        if n != m.src.num { model.mapUpdate { $0.src.num = n } }
    }
}
