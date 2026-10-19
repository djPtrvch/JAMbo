import SwiftUI

/// Пункт выбора окна MIDI MAP: подпись, пояснение справа, галочка у текущего; тап — выбрать и вернуться.
struct MidiOption: Identifiable {
    let id: String
    let label: String
    var hint: String = ""
    let current: Bool
    let pick: () -> Void
}

/// Страницы выбора окна MIDI MAP (кроме Range и Preset).
struct MidiMapOptions: View {
    let model: AppModel
    let m: MidiMapping
    @Environment(\.theme) private var theme

    var body: some View {
        let items: [MidiOption] = options
        if model.midiLearn.mapPage == .channel {
            let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(items) { o in MenuItem(title: o.label, current: o.current) { choose(o) } }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { o in row(o) }
            }
        }
    }

    private func row(_ o: MidiOption) -> some View {
        HStack(spacing: 8) {
            Text(o.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(o.current ? theme.accentText : theme.text)
            Spacer(minLength: 8)
            Text(o.hint).font(.system(size: 11)).foregroundStyle(theme.dim).lineLimit(1)
            Text(o.current ? "✓" : "").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.accentText).frame(width: 16)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { choose(o) }
    }

    private func choose(_ o: MidiOption) {
        o.pick()
        model.midiLearn.mapPage = .main
    }

    private var options: [MidiOption] {
        switch model.midiLearn.mapPage {
        case .channel:
            return (0..<16).map { c in opt("\(c)", "\(c + 1)", m.src.ch == c) { $0.src.ch = c } }
        case .event:
            return [opt("cc", "CC", m.src.type == .cc) { $0.src.type = .cc },
                    opt("note", "Note", m.src.type == .note) { $0.src.type = .note }]
        case .control:
            let all: [MidiControl] = model.midiContinuous(m.target) ? MidiControl.allCases : [.momentary, .toggle]
            return all.map { c in opt(c.rawValue, c.title, m.control == c) { $0.control = c } }
        case .encoder:
            return MidiEncoder.allCases.map { e in
                var o = opt(e.rawValue, MidiMapOptions.encName(e), m.enc == e) { $0.enc = e }
                o.hint = MidiMapOptions.encHint(e)
                return o
            }
        case .cond: return condOptions
        case .action: return actionOptions
        case .port: return portOptions(inputs: true)
        case .feedback: return portOptions(inputs: false)
        default: return []
        }
    }

    private func opt(_ id: String, _ label: String, _ current: Bool,
                     _ change: @escaping (inout MidiMapping) -> Void) -> MidiOption {
        return MidiOption(id: id, label: label, current: current) { model.mapUpdate(change) }
    }

    /// Condition: Global, Current page (страница, показанная сейчас), Clip launcher; у ячеек и строк сетки — только Clip.
    private var condOptions: [MidiOption] {
        let key: String = m.condKey
        var clip = opt("clip", "Clip launcher", key == "clip") { $0.cond = .clip }
        clip.hint = "only while PATTERNS is open"
        if m.target.isClip { return [clip] }
        let pg: MidiPage = m.cond == .page ? m.page : model.midiContext.page
        var global = opt("global", "Global", key == "global") { $0.cond = .global }
        global.hint = "all pages and views"
        var page = opt("page", "Current page", key == "page:" + pg.rawValue) { mm in
            mm.cond = .page
            mm.page = pg
        }
        page.hint = "only on this knob page"
        return [global, page, clip]
    }

    /// Action нажатия ручки: Reset (по умолчанию), Param, любая кнопка.
    private var actionOptions: [MidiOption] {
        var reset = opt("reset", "Reset", m.press == .reset) { $0.press = .reset }
        reset.hint = "default value, clears p-locks"
        var param = opt("param", "Param", m.press == .param) { $0.press = .param }
        param.hint = "Max on press, Min on release"
        var out: [MidiOption] = [reset, param]
        for n in MidiButtons.all {
            out.append(opt("btn:" + n, n, m.press == .button(n)) { $0.press = .button(n) })
        }
        return out
    }

    private func portOptions(inputs: Bool) -> [MidiOption] {
        let devices: [MidiEndpoint] = inputs ? model.midi.inputs : model.midi.outputs
        if inputs {
            var out: [MidiOption] = [opt("any", "Any", m.input == nil) { $0.input = nil }]
            for d in devices { out.append(opt("\(d.id)", d.name, m.input == d.id) { $0.input = d.id }) }
            return out
        }
        let def: String = model.midiPortName(model.settings.midi.feedback, inputs: false, none: "None")
        var out: [MidiOption] = [opt("def", "Default (\(def))", m.port == .standard) { $0.port = .standard },
                                 opt("none", "None", m.port == .none) { $0.port = .none }]
        for d in devices { out.append(opt("\(d.id)", d.name, m.port == .device(d.id)) { $0.port = .device(d.id) }) }
        return out
    }

    static func encName(_ e: MidiEncoder) -> String {
        switch e {
        case .offset: return "Offset 64"
        case .twos: return "2’s complement"
        case .signed: return "Signed bit"
        }
    }

    static func encHint(_ e: MidiEncoder) -> String {
        switch e {
        case .offset: return "65 up · 63 down"
        case .twos: return "1 up · 127 down"
        case .signed: return "1 up · 65 down"
        }
    }

    static func condName(_ m: MidiMapping) -> String {
        switch m.cond {
        case .global: return "Global"
        case .page: return "Current page"
        case .clip: return "Clip launcher"
        }
    }

    static func actionName(_ a: MidiPressAction) -> String {
        switch a {
        case .reset: return "Reset"
        case .param: return "Param"
        case .button(let n): return n
        }
    }
}

/// Range: график от входа 0 до 127 — левый конец (Min) и правый (Max) тянут вверх-вниз; Invert и Reset.
struct MidiRangeEditor: View {
    let model: AppModel
    let m: MidiMapping
    @State private var end: Int? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size) }
                    .contentShape(Rectangle())
                    .gesture(drag(geo.size))
            }
            .frame(height: 150)
            Text("Min \(pct(m.min))% · Max \(pct(m.max))%" + (m.min > m.max ? " · inverted" : ""))
                .font(.system(size: 12)).foregroundStyle(theme.dim)
            HStack(spacing: 4) {
                MenuItem(title: "Invert") {
                    let a: Double = m.min
                    let b: Double = m.max
                    model.mapUpdate { mm in
                        mm.min = b
                        mm.max = a
                    }
                }
                MenuItem(title: "Reset") {
                    model.mapUpdate { mm in
                        mm.min = 0
                        mm.max = 1
                    }
                }
            }
        }
    }

    private func pct(_ n: Double) -> Int { return Int((n * 100).rounded()) }

    /// Поле графика: отступ 20 по бокам, 10 сверху, 24 снизу (подписи 0 и 127).
    private func box(_ size: CGSize) -> CGRect {
        return CGRect(x: 20, y: 10, width: size.width - 40, height: size.height - 34)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let r: CGRect = box(size)
        ctx.stroke(Path(r), with: .color(theme.line), lineWidth: 1)
        let p0 = CGPoint(x: r.minX, y: r.maxY - CGFloat(m.min) * r.height)
        let p1 = CGPoint(x: r.maxX, y: r.maxY - CGFloat(m.max) * r.height)
        var line = Path()
        line.move(to: p0)
        line.addLine(to: p1)
        ctx.stroke(line, with: .color(theme.accent), lineWidth: 2)
        for p in [p0, p1] {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(theme.accent))
        }
        ctx.draw(Text("0").font(.system(size: 9)).foregroundStyle(theme.dim), at: CGPoint(x: r.minX, y: size.height - 8))
        ctx.draw(Text("127").font(.system(size: 9)).foregroundStyle(theme.dim), at: CGPoint(x: r.maxX, y: size.height - 8))
    }

    /// Конец ближе к пальцу по горизонтали: левый — Min, правый — Max.
    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let r: CGRect = box(size)
                if end == nil { end = g.startLocation.x < size.width / 2 ? 0 : 1 }
                let raw: Double = Double((r.maxY - g.location.y) / r.height)
                let n: Double = (min(1, max(0, raw)) * 100).rounded() / 100
                let isMin: Bool = end == 0
                model.mapUpdate { mm in
                    if isMin { mm.min = n } else { mm.max = n }
                }
            }
            .onEnded { _ in end = nil }
    }
}

/// Preset: тап — загрузить (маппинги пресета заменяют все нынешние); ниже — сохранить, перезаписать, переименовать,
/// удалить (действия с текущим пресетом без него неактивны).
struct MidiPresetPage: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let own: String = model.settings.midi.preset
        let list: [MidiPreset] = model.midiLearn.presets.list
        return VStack(alignment: .leading, spacing: 4) {
            if list.isEmpty { SettingsNote(text: "No presets yet.") }
            ForEach(list, id: \.name) { p in
                MidiMapLine(label: p.name + (p.name == own ? "  ✓" : ""), value: "\(p.mappings.count)") {
                    model.loadMidiPreset(p.name)
                    model.midiLearn.mapPage = .main
                }
            }
            SettingsNote(text: "Loading a preset replaces all current mappings.").padding(.vertical, 6)
            MenuItem(title: "SAVE CURRENT AS NEW…") { model.midiLearn.presetInput = .save }
            MenuItem(title: own.isEmpty ? "SAVE TO PRESET" : "SAVE TO “\(own)”", enabled: !own.isEmpty) { model.saveMidiPreset(own) }
            MenuItem(title: "RENAME…", enabled: !own.isEmpty) { model.midiLearn.presetInput = .rename(own) }
            MenuItem(title: "DELETE", enabled: !own.isEmpty, red: !own.isEmpty) { model.deleteMidiPreset(own) }
        }
    }
}

/// Ввод имени пресета маппингов — системное окно (как имена пресетов модулей мастера).
struct MidiPresetAlert: ViewModifier {
    let model: AppModel
    @State private var text: String = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: model.midiLearn.presetInput) { _, i in
                if let i = i { text = initial(i) }
            }
            .alert(title, isPresented: shown) {
                TextField(title, text: $text)
                Button("OK") { enter() }
                Button("Cancel", role: .cancel) {}
            }
    }

    private var shown: Binding<Bool> {
        Binding(get: { model.midiLearn.presetInput != nil }, set: { if !$0 { model.midiLearn.presetInput = nil } })
    }

    private var title: String {
        if case .rename = model.midiLearn.presetInput { return "RENAME" }
        return "PRESET NAME"
    }

    private func initial(_ i: MidiPresetInput) -> String {
        switch i {
        case .save: return model.midiLearn.presets.nextName
        case .rename(let n): return n
        }
    }

    private func enter() {
        let name: String = String(text.prefix(MidiPresetBook.nameMax))
        switch model.midiLearn.presetInput {
        case .save: model.saveMidiPreset(name)
        case .rename(let from): model.renameMidiPreset(from, to: name)
        case nil: break
        }
        model.midiLearn.presetInput = nil
    }
}
