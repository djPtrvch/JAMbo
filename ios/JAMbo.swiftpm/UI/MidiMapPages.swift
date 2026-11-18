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
            let all: [MidiControl] = model.midiContinuous(m.target) ? MidiControl.allCases : [.momentary, .toggle, .latch]
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
        var global = opt("global", "Global", key == "global") { $0.cond = .global }
        global.hint = "all pages and views"
        if m.target.isClip {
            global.hint = "launch patterns with PATTERNS closed too"
            return [global, clip]
        }
        let pg: MidiPage = m.cond == .page ? m.page : model.midiContext.page
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
            var any = opt("any", "Device", m.input == nil) { $0.input = nil }
            any.hint = "any input of " + m.dev
            var out: [MidiOption] = [any]
            for d in devices { out.append(opt("\(d.id)", d.name, m.input == d.id) { $0.input = d.id }) }
            return out
        }
        var dev = opt("def", "Device", m.port == .standard) { $0.port = .standard }
        dev.hint = "outputs of " + m.dev
        var out: [MidiOption] = [dev,
                                 opt("none", "None", m.port == .none) { $0.port = .none }]
        for d in devices { out.append(opt("\(d.id)", d.name, m.port == .device(d.id)) { $0.port = .device(d.id) }) }
        if case .controller(let n) = m.port { out.append(opt("controller", "All " + n, true) { _ in }) }
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
