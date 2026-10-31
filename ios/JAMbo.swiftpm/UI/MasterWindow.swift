import SwiftUI

/// Окно модуля мастера (S6, на общей основе, как masterwin.ts веба): вверху строка кнопок (barH, как стрелки над миниатюрами) — название (тап — меню
/// SAT, COMP, CLIP, LIM), поля параметров, PRESETS, BYPASS, ✕; ниже — дисплей модуля. Нижней панели нет.
struct MasterWindowView: View {
    let model: AppModel
    let module: Int
    @State private var frame: CGRect = .zero
    @State private var text: String = ""
    /// Имя занято: SAVE — номер пресета с этим именем (OVERWRITE / SAVE AS), RENAME — (пресет, занятый).
    @State private var clash: NameClash? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = RedrawMeter.hit(.masterWin)
        VStack(spacing: Layout.barGap) {
            MasterStrip(model: model, module: module, bounds: frame, input: { t in openInput(t) })
                .frame(height: model.barH)
            display
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
        // Окно ввода открывают поле (двойной тап), SAVE и RENAME: текст — текущее значение или имя.
        .onChange(of: model.masterInput) { _, t in
            if let t = t { text = initialText(t) }
        }
        .alert(inputTitle, isPresented: inputShown) {
            TextField(inputTitle, text: $text)
            Button("OK") { enter() }
            Button("Cancel", role: .cancel) {}
        }
        .modifier(NameClashAlert(clash: $clash, overwrite: { k in
            model.saveMasterPreset(module, name: text, over: k)
        }, again: { c in
            // Текст окна ставит onChange(of: masterInput).
            let t: MasterInputTarget = c.renaming.map { MasterInputTarget.rename($0) } ?? MasterInputTarget.save
            model.masterInput = t
        }))
    }

    @ViewBuilder
    private var display: some View {
        if module == MasterScope.lim {
            LimiterDisplay(model: model)
        } else if module == MasterScope.comp {
            CompDisplay(model: model)
        } else if module == MasterScope.clip {
            ClipDisplay(model: model)
        } else {
            SatDisplay(model: model)
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
            if let k = model.masterPresets.index(module, named: text) {
                clash = NameClash(name: text, existing: k, renaming: nil)
                return
            }
            model.saveMasterPreset(module, name: text)
        case .rename(let k):
            if model.masterPresets.index(module, named: text, except: k) != nil {
                clash = NameClash(name: text, existing: -1, renaming: k)
                return
            }
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
        let lead: (count: Int, width: CGFloat?) = leadFields
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
                    .frame(width: i < lead.count ? lead.width : nil)
            }
            EqTool(title: "PRESETS", enabled: true, active: model.masterMenu?.kind == .presets) {
                model.masterMenu = MasterMenuState(kind: .presets, anchor: presetsFrame, bounds: bounds)
            }
            .frame(width: 100)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { presetsFrame = $0 }
            EqTool(title: "BYPASS", enabled: true, active: bypass) { model.toggleMasterBypass(module) }
                .frame(width: 100)
            CloseButton(side: model.barH) { model.closeMasterWindow() }
        }
    }

    /// Первые поля — до правого края дисплея TRANSFER под строкой (решение пользователя): у COMP — до MAKEUP, у SAT —
    /// до TYPE, у CLIP — до CEILING; у LIM — по ширине полей CLIP (TRANSFER у него нет). Остальные поля — поровну до
    /// PRESETS. Ширина TRANSFER — как в CompDisplay, ClipDisplay, SatDisplay (от размера дисплея под строкой).
    private var leadFields: (count: Int, width: CGFloat?) {
        let g: CGFloat = Layout.gap
        let wide: CGFloat = bounds.width
        let high: CGFloat = max(0, bounds.height - model.barH - Layout.barGap)
        if wide <= 0 || high <= 0 { return (0, nil) }
        let sat: Bool = module == MasterScope.sat
        let transfer: CGFloat = sat ? min(wide * 0.35, high) : min(wide * 0.4, high * 1.4)
        let k: Int = module == MasterScope.comp ? 4 : 2
        let x0: CGFloat = EqBar.nameWidth + g
        let w: CGFloat = (transfer - x0 - CGFloat(k - 1) * g) / CGFloat(k)
        return (k, max(40, w))
    }

    private func tapAction(_ p: ParamDef) -> (() -> Void)? {
        if p.id == "cmp.ratio" { return { model.tapRatio() } }
        if p.id == "sat.type" { return { model.tapSatType() } }
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

/// Поле окна модуля (как поля EQ, без рамки подсветки — решение пользователя): подпись над значением; палец
/// вверх-вниз — 240 px на весь диапазон, как у ручек (одна запись UNDO на жест); двойной тап без движения — ввод
/// числом, как в EQ (решение пользователя; прежде — удержание 0,5 с); тап — tap (TYPE, RATIO — следующее значение;
/// срабатывает, когда второго тапа не было за EqPlot.doubleTap).
struct MasterField: View {
    static let travel: CGFloat = 240
    let model: AppModel
    let param: ParamDef
    var gray: Bool = false
    var tap: (() -> Void)? = nil
    let input: () -> Void
    @State private var start: Double? = nil
    @State private var moved: Bool = false
    @State private var lastTap: Date = .distantPast
    /// Отложенный одиночный тап (ждёт, не будет ли второго).
    @State private var tapTask: Task<Void, Never>? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let v: Double = model.masterValue(param)
        let value: String = param.format(v).replacingOccurrences(of: "\n", with: " ")
        return VStack(alignment: .leading, spacing: 0) {
            Text(param.label.uppercased()).font(.system(size: 9)).tracking(0.8).foregroundStyle(theme.dim)
                .lineLimit(1)
            Text(value).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(gray ? theme.off : theme.text)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(start != nil ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .gesture(drag)
        .modifier(GestureCancelGuard {
            if start != nil {
                start = nil
                model.endGesture()
            }
        })
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil { begin() }
                let dy: CGFloat = g.translation.height
                if !moved && abs(dy) > 10 { moved = true }
                guard moved, let s = start else { return }
                let d: Double = Double(-dy / MasterField.travel)
                model.setMaster(param, param.fromNorm(s + d))
            }
            .onEnded { _ in
                if start != nil { model.endGesture() }
                start = nil
                if !moved { tapped() }
            }
    }

    private func begin() {
        start = param.toNorm(model.masterValue(param))
        moved = false
        model.beginGesture()
    }

    /// Второй тап подряд — ввод числом; одиночный — tap (с задержкой на ожидание второго).
    private func tapped() {
        let now = Date()
        tapTask?.cancel()
        tapTask = nil
        if now.timeIntervalSince(lastTap) < EqPlot.doubleTap {
            lastTap = .distantPast
            input()
            return
        }
        lastTap = now
        guard let t = tap else { return }
        tapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 330_000_000)
            if Task.isCancelled { return }
            t()
        }
    }
}

/// Имя пресета занято: SAVE — existing (номер пресета с этим именем), RENAME — renaming (номер переименуемого).
struct NameClash: Equatable {
    let name: String
    let existing: Int
    let renaming: Int?
}

/// Предупреждение «имя уже есть» (как в библиотеке и PROJECTS): SAVE — OVERWRITE / SAVE AS… / CANCEL,
/// RENAME — RENAME… / CANCEL. again — снова окно ввода.
struct NameClashAlert: ViewModifier {
    @Binding var clash: NameClash?
    let overwrite: (Int) -> Void
    let again: (NameClash) -> Void

    func body(content: Content) -> some View {
        let shown = Binding<Bool>(get: { clash != nil }, set: { if !$0 { clash = nil } })
        return content.alert("“\(clash?.name ?? "")” already exists", isPresented: shown) {
            if let c = clash, c.renaming == nil {
                Button("OVERWRITE", role: .destructive) {
                    clash = nil
                    overwrite(c.existing)
                }
                Button("SAVE AS…") { reopen(c) }
            } else if let c = clash {
                Button("RENAME…") { reopen(c) }
            }
            Button("CANCEL", role: .cancel) { clash = nil }
        }
    }

    /// Окно ввода — после закрытия этого (два alert подряд в одном кадре SwiftUI не показывает).
    private func reopen(_ c: NameClash) {
        clash = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            again(c)
        }
    }
}

/// Жест, который система отменила (onEnded не пришёл): cleanup закрывает его запись UNDO — иначе следующие правки
/// сливаются с ней в одну отмену. После обычного конца жеста cleanup ничего не делает (флаги уже сброшены).
struct GestureCancelGuard: ViewModifier {
    @GestureState private var down: Bool = false
    let cleanup: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($down) { _, s, _ in s = true })
            .onChange(of: down) { _, d in
                if d { return }
                // Чуть позже: при обычном конце жеста сначала срабатывает его onEnded.
                let c: () -> Void = cleanup
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    c()
                }
            }
    }
}
