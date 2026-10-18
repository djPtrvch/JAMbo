import SwiftUI

/// Какое значение полосы вводят числом (удержание FREQ, GAIN, Q).
enum EqInput {
    case freq, gain, q, thr, range
}

/// EQ на месте центра (кнопка EQ): вверху строка полей ровной сеткой со строкой дорожек, под ней поле EQ.
struct EqView: View {
    let model: AppModel
    let layout: Layout
    @State private var plotFrame: CGRect = .zero
    @State private var input: EqInput? = nil
    @State private var inputBand: Int = -1
    @State private var text: String = ""
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Layout.gap) {
            EqBar(model: model, layout: layout, plotFrame: plotFrame) { field in openInput(field) }
                .frame(height: 48)
            EqPlot(model: model)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { plotFrame = $0 }
        }
        // Меню COMPARE — поверх, раскладку не меняет: помещается в поле EQ (кнопки ужимаются).
        .overlay(alignment: .topLeading) {
            if model.eqCompareMenu {
                EqCompareMenu(model: model, width: 2 * layout.step + Layout.gap, height: plotFrame.height)
            }
        }
        // Другой канал — выбор полосы сбрасывается, точки съёма спектров — на новый канал.
        .onChange(of: model.eqChannel) { _, _ in
            model.eqBand = -1
            model.eqCompareMenu = false
            model.eqMsMenu = nil
            model.eqDynMenu = nil
            model.syncSpectra()
        }
        // Ввод числом из меню DYN (THRESHOLD, RANGE).
        .onChange(of: model.eqInputAsk) { _, f in
            if let field = f {
                model.eqInputAsk = nil
                openInput(field)
            }
        }
        .onAppear { model.syncSpectra() }
        .onDisappear { model.syncSpectra() }
        .alert(inputTitle, isPresented: inputShown) {
            TextField(inputTitle, text: $text).keyboardType(.numbersAndPunctuation)
            Button("OK") { enter() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var inputShown: Binding<Bool> {
        Binding(get: { input != nil }, set: { if !$0 { input = nil } })
    }

    private var inputTitle: String {
        switch input {
        case .freq: return "FREQ (Hz, 1.5k — kHz)"
        case .gain: return "GAIN (dB)"
        case .q: return "Q"
        case .thr: return "THRESHOLD (dB)"
        case .range: return "RANGE (dB)"
        case nil: return ""
        }
    }

    private func openInput(_ field: EqInput) {
        guard let b = model.selectedBand else { return }
        if field == .gain && !EqSpec.hasGain(b.type) { return }
        inputBand = model.eqBand
        switch field {
        case .freq: text = "\(Int(b.freq.rounded()))"
        case .gain: text = String(format: "%.1f", b.gain)
        case .q: text = String(format: "%.2f", b.q)
        case .thr: text = String(format: "%.1f", b.thr)
        case .range: text = String(format: "%.1f", b.range)
        }
        input = field
    }

    private func enter() {
        let k: Int = inputBand
        switch input {
        case .freq:
            if let v = EqFormat.parseFreq(text) { model.setEqBand(k, freq: v) }
        case .gain:
            if let v = EqFormat.parseNum(text) { model.setEqBand(k, gain: v) }
        case .q:
            if let v = EqFormat.parseNum(text), v > 0 { model.setEqBand(k, q: v) }
        case .thr:
            if let v = EqFormat.parseNum(text) { model.setEqDynParams(k, thr: v) }
        case .range:
            if let v = EqFormat.parseNum(text) { model.setEqDynParams(k, range: v) }
        case nil:
            break
        }
        input = nil
    }
}

/// Строка EQ: имя канала под бутербродом, TYPE, FREQ, GAIN, Q, STEREO, DYN, PRESETS, BYPASS — шириной столбцов
/// 8 дорожек (при 9–16 дорожках не сужаются), TYPE — с левого края поля BPM (решение пользователя; в вебе — над
/// дорожками 1…8). PRESETS — S7d (серая).
struct EqBar: View {
    let model: AppModel
    let layout: Layout
    let plotFrame: CGRect
    let input: (EqInput) -> Void
    @State private var lastQTap: Date = .distantPast
    @Environment(\.theme) private var theme

    var body: some View {
        let col: CGFloat = EqBar.column(layout)
        ZStack(alignment: .topLeading) {
            name.frame(width: EqBar.nameWidth, height: 48)
            ForEach(0..<8, id: \.self) { i in
                item(i).frame(width: col, height: 48).offset(x: EqBar.left(i, layout))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Ширина столбца: 8 столбцов с зазорами между MIX и MST.
    static func column(_ layout: Layout) -> CGFloat {
        let gaps: CGFloat = 9 * Layout.gap
        let free: CGFloat = layout.width - 2 * layout.step - gaps
        return free / 8
    }

    /// Имя канала — под бутербродом верхней панели (его ширина).
    static let nameWidth: CGFloat = 52

    /// Левый край столбца i: TYPE — с левого края поля BPM (решение пользователя), дальше — шагом столбцов дорожек.
    static func left(_ i: Int, _ layout: Layout) -> CGFloat {
        let col: CGFloat = column(layout) + Layout.gap
        let x0: CGFloat = EqBar.nameWidth + Layout.gap
        return x0 + CGFloat(i) * col
    }

    /// Имя канала: тап — у дорожки меню дорожек для сравнения, у мастера — спектр выхода (надпись красная).
    private var name: some View {
        let lit: Bool = model.eqOutShown || model.eqCompareShown != nil
        return Text("\(model.eqTargetName)\nEQ")
            .font(.system(size: 11)).tracking(0.9)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundStyle(model.eqOutShown ? theme.rec : (lit ? theme.text : theme.dim))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { model.eqNameTapped() }
    }

    @ViewBuilder
    private func item(_ i: Int) -> some View {
        let b: EqBand? = model.selectedBand
        switch i {
        case 0: typeField(b)
        case 1: freqField(b)
        case 2: gainField(b)
        case 3: qField(b)
        case 4: msField(b)
        case 5: dynField(b)
        case 6: EqTool(title: "PRESETS", enabled: false, active: false) {}
        default: EqTool(title: "BYPASS", enabled: true, active: !model.eqTarget.on) { model.toggleEqBypass() }
        }
    }

    // Значения полей в пунктах движения пальца и обратно.
    static func typeIndex(_ b: EqBand?) -> Double {
        let t: Int = b?.type ?? 0
        let i: Int = EqSpec.typeOrder.firstIndex(of: t) ?? 0
        return -Double(i)
    }

    static func typeAt(_ v: Double) -> Int {
        let n: Int = EqSpec.typeOrder.count
        let i: Int = -Int(v)
        let j: Int = ((i % n) + n) % n
        return EqSpec.typeOrder[j]
    }

    static func freqUnits(_ b: EqBand?) -> Double {
        let f: Double = b?.freq ?? 1000
        let oct: Double = log2(f / EqSpec.freqMin)
        return (oct * 24).rounded()
    }

    static func freqOf(_ v: Double) -> Double {
        let oct: Double = v / 24
        return EqSpec.freqMin * pow(2, oct)
    }

    static func gainUnits(_ b: EqBand?) -> Double {
        let g: Double = b?.gain ?? 0
        return (g * 10).rounded()
    }

    static func qUnits(_ b: EqBand?) -> Double {
        let q: Double = b?.q ?? 1
        let oct: Double = log2(q)
        return (oct * 12).rounded()
    }

    static func qOf(_ v: Double) -> Double {
        let oct: Double = v / 12
        return pow(2, oct)
    }

    /// TYPE: палец вниз — следующий тип по порядку меню; тап — меню полосы.
    private func typeField(_ b: EqBand?) -> some View {
        let k: Int = model.eqBand
        return EqField(label: "TYPE", value: b.map { EqFormat.type($0) } ?? "—", enabled: b != nil, pxPerUnit: 30,
                       get: { EqBar.typeIndex(model.selectedBand) },
                       set: { v in model.setEqType(k, EqBar.typeAt(v)) },
                       tap: { f in
                           model.eqMenu = EqMenuState(band: k, anchor: CGPoint(x: f.midX, y: f.maxY), bounds: plotFrame)
                       },
                       model: model)
    }

    /// FREQ: 2 px на 1/24 октавы; удержание (палец может сдвинуться до 14 px) — ввод числом (решение пользователя:
    /// тап — ничего, в вебе тап тоже открывает ввод).
    private func freqField(_ b: EqBand?) -> some View {
        let k: Int = model.eqBand
        return EqField(label: "FREQ", value: b.map { EqFormat.hz($0.freq) } ?? "—", enabled: b != nil, pxPerUnit: 2,
                       get: { EqBar.freqUnits(model.selectedBand) },
                       set: { v in model.setEqBand(k, freq: EqBar.freqOf(v)) },
                       hold: { input(.freq) }, moveTol: 14, model: model)
    }

    /// GAIN: 1 px на 0,1 dB (у cut и notch — «—»); удержание — ввод числом.
    private func gainField(_ b: EqBand?) -> some View {
        let k: Int = model.eqBand
        let has: Bool = b.map { EqSpec.hasGain($0.type) } ?? false
        return EqField(label: "GAIN", value: has ? EqFormat.gain(b?.gain ?? 0) : "—", enabled: has, pxPerUnit: 1,
                       get: { EqBar.gainUnits(model.selectedBand) },
                       set: { v in model.setEqBand(k, gain: v / 10) },
                       hold: { input(.gain) }, model: model)
    }

    /// M/S (как в вебе): палец вниз — следующий режим (30 px на режим), тап — меню STEREO / MID / SIDE.
    private func msField(_ b: EqBand?) -> some View {
        let k: Int = model.eqBand
        return EqField(label: "M/S", value: b.map { EqFormat.ms($0) } ?? "—", enabled: b != nil, pxPerUnit: 30,
                       get: { -Double(model.selectedBand?.ms ?? 0) },
                       set: { v in
                           let i: Int = -Int(v)
                           model.setEqMs(k, ((i % 3) + 3) % 3)
                       },
                       tap: { f in model.eqMsMenu = f },
                       model: model)
    }

    /// DYN (как в вебе): только тап — меню источника с THRESHOLD и RANGE; у cut и notch — «—».
    private func dynField(_ b: EqBand?) -> some View {
        let has: Bool = b.map { EqSpec.hasGain($0.type) } ?? false
        return EqField(label: "DYN", value: b.map { model.eqDynName($0) } ?? "—", enabled: has, pxPerUnit: 100000,
                       tap: { f in model.eqDynMenu = f }, model: model)
    }

    /// Q: 3 px на 1/12 октавы; двойной тап — Q по умолчанию (1,0); удержание — ввод числом.
    private func qField(_ b: EqBand?) -> some View {
        let k: Int = model.eqBand
        return EqField(label: "Q", value: b.map { String(format: "%.2f", $0.q) } ?? "—", enabled: b != nil, pxPerUnit: 3,
                       get: { EqBar.qUnits(model.selectedBand) },
                       set: { v in model.setEqBand(k, q: EqBar.qOf(v)) },
                       tap: { _ in
                           let now = Date()
                           if now.timeIntervalSince(lastQTap) < EqPlot.doubleTap {
                               model.setEqBand(k, q: EqSpec.qDef)
                               lastQTap = .distantPast
                           } else {
                               lastQTap = now
                           }
                       },
                       hold: { input(.q) }, model: model)
    }
}

/// Поле строки EQ: подпись над значением; палец вверх-вниз — pxPerUnit на пункт (одна запись UNDO на жест), тап,
/// удержание 0,5 с без движения (до moveTol px); выключенное — серое, касаний нет.
struct EqField: View {
    let label: String
    let value: String
    var enabled: Bool = true
    var pxPerUnit: CGFloat = 10
    var get: () -> Double = { 0 }
    var set: (Double) -> Void = { _ in }
    var tap: ((CGRect) -> Void)? = nil
    var hold: (() -> Void)? = nil
    var moveTol: CGFloat = 10
    let model: AppModel
    @State private var start: Double? = nil
    @State private var moved: Bool = false
    @State private var held: Bool = false
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var frame: CGRect = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 9)).tracking(0.8).foregroundStyle(theme.dim)
            Text(value).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(enabled ? theme.text : theme.off)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(start != nil ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
        .gesture(drag, including: enabled ? .all : .none)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil { begin() }
                let dy: CGFloat = g.translation.height
                if !moved && !held && abs(dy) > moveTol {
                    moved = true
                    holdTask?.cancel()
                }
                if moved, let s = start { set(s + (-dy / pxPerUnit).rounded()) }
            }
            .onEnded { _ in
                holdTask?.cancel()
                model.endGesture()
                start = nil
                if !moved && !held { tap?(frame) }
            }
    }

    private func begin() {
        start = get()
        moved = false
        held = false
        model.beginGesture()
        guard let h = hold else { return }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled || moved || start == nil { return }
            held = true
            h()
        }
    }
}

/// Кнопка строки EQ (PRESETS, BYPASS): горит, когда active; выключенная — серая.
struct EqTool: View {
    let title: String
    let enabled: Bool
    let active: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let fg: Color = !enabled ? theme.off : (active ? theme.onAccent : theme.text)
        return Text(title)
            .font(.system(size: 12, weight: .bold)).tracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(active ? theme.accent : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

/// Меню полосы: типы (порядок меню), крутизна среза (только у cut), ON/OFF (вкл./выкл. полосы — решение
/// пользователя, в вебе это двойной тап), DELETE (красная). Внутри поля EQ у точки или под
/// полем TYPE; тап мимо — закрыть.
struct EqBandMenu: View {
    static let width: CGFloat = 390
    /// Типы — 2 ряда по 44, крутизна 44, ON/OFF и DELETE 44, зазоры 4, поля 12.
    static let height: CGFloat = 200
    let model: AppModel
    let state: EqMenuState
    @Environment(\.theme) private var theme

    var body: some View {
        let r: CGRect = state.bounds
        let w: CGFloat = EqBandMenu.width
        let h: CGFloat = EqBandMenu.height
        let left: CGFloat = state.anchor.x - w / 2
        let maxX: CGFloat = r.maxX - w - 8
        let x: CGFloat = min(max(r.minX + 8, left), maxX)
        let bottom: CGFloat = state.anchor.y + 8 + h
        let below: Bool = bottom <= r.maxY - 8
        let above: CGFloat = max(r.minY + 8, state.anchor.y - 8 - h)
        let y: CGFloat = below ? state.anchor.y + 8 : above
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.eqMenu = nil }
            content
                .padding(6)
                .frame(width: w)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .offset(x: x, y: y)
        }
    }

    @ViewBuilder
    private var content: some View {
        let b: EqBand? = model.eqTarget.band(state.band)
        let cut: Bool = b.map { EqSpec.isCut($0.type) } ?? false
        let type: Int = b?.type ?? -1
        let slope: Int = b?.slope ?? -1
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        let off: Bool = !(b?.on ?? true)
        VStack(spacing: 4) {
            // Типы и крутизна — отдельными сетками: id пунктов в одной сетке не повторяются.
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(EqSpec.typeOrder, id: \.self) { t in
                    MenuItem(title: EqSpec.types[t].uppercased(), current: type == t) { pick { model.setEqType(state.band, t) } }
                        .frame(height: 44)
                }
            }
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(0..<EqSpec.slopes.count, id: \.self) { s in
                    let on: Bool = cut && slope == s
                    MenuItem(title: "\(EqSpec.slopes[s]) dB/oct", enabled: cut, current: on) {
                        pick { model.setEqSlope(state.band, s) }
                    }
                    .frame(height: 44)
                }
            }
            HStack(spacing: 4) {
                MenuItem(title: off ? "ON" : "OFF") { pick { model.toggleEqBand(state.band) } }.frame(height: 44)
                MenuItem(title: "DELETE", red: true) { pick { model.deleteEqBand(state.band) } }.frame(height: 44)
            }
        }
    }

    private func pick(_ act: () -> Void) {
        act()
        model.eqMenu = nil
    }
}

/// Меню STEREO / MID / SIDE (тап по M/S): под полем, один столбец; тап мимо — закрыть.
struct EqMsMenu: View {
    static let width: CGFloat = 200
    let model: AppModel
    let anchor: CGRect
    @Environment(\.theme) private var theme

    var body: some View {
        let ms: Int = model.selectedBand?.ms ?? -1
        let k: Int = model.eqBand
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.eqMsMenu = nil }
            VStack(alignment: .leading, spacing: 6) {
                Text("CHANNEL").font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(theme.text)
                ForEach(0..<EqSpec.msModes.count, id: \.self) { i in
                    MenuItem(title: EqSpec.msModes[i], current: ms == i) {
                        model.setEqMs(k, i)
                        model.eqMsMenu = nil
                    }
                    .frame(height: 44)
                }
            }
            .padding(8)
            .frame(width: EqMsMenu.width)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .offset(x: anchor.minX, y: anchor.maxY + 4)
        }
    }
}
