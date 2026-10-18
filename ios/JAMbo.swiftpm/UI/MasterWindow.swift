import SwiftUI

/// Окно модуля мастера (S9a, на общей основе, как masterwin.ts веба): вверху строка 48 px — название (тап — меню
/// SAT, COMP, CLIP, LIM), поля параметров, PRESETS, BYPASS, ✕; ниже — дисплей модуля. Нижней панели нет.
struct MasterWindowView: View {
    let model: AppModel
    let module: Int
    @State private var frame: CGRect = .zero
    @State private var text: String = ""
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Layout.gap) {
            MasterStrip(model: model, module: module, bounds: frame, input: { t in openInput(t) })
                .frame(height: 48)
            display
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
        // Окно ввода открывают поле (удержание), SAVE и RENAME: текст — текущее значение или имя.
        .onChange(of: model.masterInput) { _, t in
            if let t = t { text = initialText(t) }
        }
        .alert(inputTitle, isPresented: inputShown) {
            TextField(inputTitle, text: $text)
            Button("OK") { enter() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var display: some View {
        if module == MasterScope.lim {
            LimiterDisplay(model: model)
        } else if module == MasterScope.comp {
            CompDisplay(model: model)
        } else {
            Placeholder(title: "DISPLAY — NEXT STEP")
        }
    }

    private var inputShown: Binding<Bool> {
        Binding(get: { model.masterInput != nil }, set: { if !$0 { model.masterInput = nil } })
    }

    private var inputTitle: String {
        switch model.masterInput {
        case .param(let id):
            let label: String = Params.byId[id]?.label.uppercased() ?? ""
            return label
        case .save: return "PRESET NAME"
        case .rename: return "RENAME"
        case nil: return ""
        }
    }

    private func openInput(_ t: MasterInputTarget) {
        text = initialText(t)
        model.masterInput = t
    }

    private func initialText(_ t: MasterInputTarget) -> String {
        switch t {
        case .param(let id):
            guard let p = Params.byId[id] else { return "" }
            return MasterInput.text(p, model.masterValue(p))
        case .save:
            return model.masterPresets.nextName(module)
        case .rename(let k):
            let list: [MasterPreset] = model.masterPresets.list(module)
            return k < list.count ? list[k].name : ""
        }
    }

    private func enter() {
        let t: MasterInputTarget? = model.masterInput
        model.masterInput = nil
        switch t {
        case .param(let id):
            guard let p = Params.byId[id], let v = MasterInput.parse(p, text) else { return }
            model.setMaster(p, v)
        case .save:
            model.saveMasterPreset(module, name: text)
        case .rename(let k):
            model.renameMasterPreset(module, k, to: text)
        case nil:
            break
        }
    }
}

/// Строка окна модуля: название, поля, PRESETS, BYPASS (рядом с крестиком), ✕. При BYPASS поля серые (у LIM —
/// только INPUT и CEILING, как в вебе).
struct MasterStrip: View {
    let model: AppModel
    let module: Int
    let bounds: CGRect
    let input: (MasterInputTarget) -> Void
    @State private var presetsFrame: CGRect = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        let fields: [ParamDef] = AppModel.masterFields(module)
        let bypass: Bool = model.masterBypass(module)
        return HStack(spacing: Layout.gap) {
            MasterTitle(model: model, module: module, bounds: bounds)
            ForEach(0..<fields.count, id: \.self) { i in
                let p: ParamDef = fields[i]
                // Поля без ручек (RATIO и дальше) — за тонкой чертой.
                if p.id == "cmp.ratio" {
                    Rectangle().fill(theme.line).frame(width: 1).padding(.vertical, 8)
                }
                MasterField(model: model, param: p, gray: bypass && grays(p), tap: tapAction(p),
                            input: { input(.param(p.id)) })
            }
            EqTool(title: "PRESETS", enabled: true, active: model.masterMenu?.kind == .presets) {
                model.masterMenu = MasterMenuState(kind: .presets, anchor: presetsFrame, bounds: bounds)
            }
            .frame(width: 100)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { presetsFrame = $0 }
            EqTool(title: "BYPASS", enabled: true, active: bypass) { model.toggleMasterBypass(module) }
                .frame(width: 100)
            CloseButton { model.closeMasterWindow() }
        }
    }

    private func tapAction(_ p: ParamDef) -> (() -> Void)? {
        if p.id == "cmp.ratio" { return { model.tapRatio() } }
        return nil
    }

    private func grays(_ p: ParamDef) -> Bool {
        if module != MasterScope.lim { return true }
        return p.id == "lim.input" || p.id == "lim.ceiling"
    }
}

/// Название окна (MASTER / LIM ▾): тап — меню модулей.
struct MasterTitle: View {
    let model: AppModel
    let module: Int
    let bounds: CGRect
    @State private var frame: CGRect = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        let name: String = MasterPresetBook.titles[module]
        return Text("MASTER\n\(name) ▾")
            .font(.system(size: 11)).tracking(0.9)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundStyle(theme.dim)
            // Под бутербродом, как имя в строке EQ: первое поле — с левого края поля BPM.
            .frame(width: EqBar.nameWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
            .onTapGesture { model.masterMenu = MasterMenuState(kind: .modules, anchor: frame, bounds: bounds) }
    }
}

/// Поле окна модуля: подпись над значением; палец вверх-вниз — 240 px на весь диапазон, как у ручек (одна запись
/// UNDO на жест); удержание 0,5 с без движения — ввод числом; тап без движения — tap (TYPE, RATIO — S9a-2, S9a-4);
/// жёлтая рамка — параметр меняют (палец, ручка, UNDO) и ещё 400 мс.
struct MasterField: View {
    static let travel: CGFloat = 240
    let model: AppModel
    let param: ParamDef
    var gray: Bool = false
    var tap: (() -> Void)? = nil
    let input: () -> Void
    @State private var start: Double? = nil
    @State private var moved: Bool = false
    @State private var held: Bool = false
    @State private var holdTask: Task<Void, Never>? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let v: Double = model.masterValue(param)
        let value: String = param.format(v).replacingOccurrences(of: "\n", with: " ")
        return VStack(alignment: .leading, spacing: 0) {
            Text(param.label.uppercased()).font(.system(size: 9)).tracking(0.8).foregroundStyle(theme.dim)
                .lineLimit(1)
            Text(value).font(.system(size: 15)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(gray ? theme.off : theme.text)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(start != nil ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(HotFrame(model: model, id: param.id))
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil { begin() }
                let dy: CGFloat = g.translation.height
                if !moved && !held && abs(dy) > 10 {
                    moved = true
                    holdTask?.cancel()
                }
                guard moved, let s = start else { return }
                let d: Double = Double(-dy / MasterField.travel)
                model.setMaster(param, param.fromNorm(s + d))
            }
            .onEnded { _ in
                holdTask?.cancel()
                model.masterHot.release(param.id)
                model.endGesture()
                start = nil
                if !moved && !held { tap?() }
            }
    }

    private func begin() {
        start = param.toNorm(model.masterValue(param))
        moved = false
        held = false
        model.beginGesture()
        model.masterHot.hold(param.id)
        holdTask?.cancel()
        let open: () -> Void = input
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled || moved || start == nil { return }
            held = true
            open()
        }
    }
}

/// Жёлтая рамка поля или дисплея, пока параметр id подсвечен (HotTracker).
struct HotFrame: View {
    let model: AppModel
    let id: String
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            let lit: Bool = model.masterHotNow(id, now: now)
            RoundedRectangle(cornerRadius: Layout.radius)
                .stroke(theme.accent, lineWidth: 1)
                .opacity(lit ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}
