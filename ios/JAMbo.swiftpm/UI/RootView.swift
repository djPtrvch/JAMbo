import SwiftUI
import UniformTypeIdentifiers

/// Главный экран (сверху вниз, как в вебе): верхняя панель, центр, строка дорожек, секвенсор, клавиатура.

struct RootView: View {
    let model: AppModel
    @State private var menuOpen: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let layout: Layout = Layout(width: geo.size.width - 24)
            ZStack(alignment: .topLeading) {
                theme.bg.ignoresSafeArea()
                screen(layout)
                overlays
                if let c = model.choice {
                    ChoiceMenu(model: model, state: c, screen: geo.size)
                }
                if model.pianoMenuOpen {
                    PianoMenu(model: model, layout: layout, screen: geo.size)
                }
            }
            .coordinateSpace(name: "root")
        }
        // Клавиатура (имя дорожки, темп числом) не сдвигает экран: поля ввода — в верхней части.
        .ignoresSafeArea(.keyboard)
        .fileImporter(isPresented: importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFiles(urls) } else { model.importTarget = nil }
        }
    }

    /// Выбор файлов (LOAD): «Файлы» iPad и iCloud Drive, можно сразу несколько.
    private var importing: Binding<Bool> {
        Binding(get: { model.importing }, set: { model.importing = $0 })
    }

    private func screen(_ layout: Layout) -> some View {
        VStack(spacing: Layout.gap) {
            TopBar(model: model, menuOpen: $menuOpen)
            center(layout)
            TrackRow(model: model, layout: layout)
            SequencerRow(model: model)
            KeyboardPanel(model: model, layout: layout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Центр: левая колонка | сетка ручек | правая колонка | измеритель; с PATTERNS — сетка паттернов во всю ширину;
    /// с EQ и окном модуля мастера — до края миниатюр страниц, справа измеритель.
    @ViewBuilder
    private func center(_ layout: Layout) -> some View {
        if model.rollView {
            RollWindow(model: model, layout: layout)
        } else if model.patternView {
            PatternGrid(model: model, layout: layout)
        } else if model.eqView {
            HStack(spacing: Layout.gap) {
                EqView(model: model, layout: layout)
                MeterColumn(model: model)
            }
        } else if let m = model.masterWin {
            // Окно модуля мастера — на месте центра (как EQ), справа измеритель.
            HStack(spacing: Layout.gap) {
                MasterWindowView(model: model, module: m)
                MeterColumn(model: model)
            }
        } else if model.editorOpen {
            // Редактор сэмпла — на месте центра (окно сэмпла, сетка ручек, правая колонка), справа измеритель.
            HStack(spacing: Layout.gap) {
                SampleEditor(model: model)
                MeterColumn(model: model)
            }
        } else {
            HStack(spacing: Layout.gap) {
                LeftColumn(model: model).frame(width: Layout.leftColumn)
                KnobGrid(model: model)
                RightColumn(model: model).frame(width: Layout.leftColumn)
                MeterColumn(model: model)
            }
        }
    }

    @ViewBuilder
    private var overlays: some View {
        if menuOpen {
            MainMenu(model: model, isOpen: $menuOpen).padding(.top, 58).padding(.leading, 12)
        }
        if let menu = model.pageMenu {
            pageMenu(menu)
        }
        if let m = model.soundMenu {
            soundMenu(m)
        }
        if let m = model.eqMenu {
            EqBandMenu(model: model, state: m)
        }
        if let f = model.eqMsMenu {
            EqMsMenu(model: model, anchor: f)
        }
        if let f = model.eqDynMenu {
            EqDynMenu(model: model, anchor: f)
        }
        if let m = model.eqPresetMenu {
            EqPresetsMenu(model: model, state: m)
        }
        if let m = model.masterMenu {
            MasterMenuView(model: model, state: m)
        }
        if model.showDiagnostics {
            DiagnosticsView(model: model).padding(8)
        }
    }
}

extension RootView {
    /// Меню звука — на месте левой колонки; тап мимо — закрыть.
    func soundMenu(_ m: SoundMenuState) -> some View {
        let r: CGRect = model.leftFrame
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { model.soundMenu = nil }
            SoundMenu(model: model, state: m)
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
        }
    }

    /// Меню страницы — под её миниатюрой, по центру колонки миниатюр (как в вебе); тап мимо — закрыть.
    func pageMenu(_ menu: PageMenuState) -> some View {
        let top: CGFloat = 8 + Layout.topHeight + Layout.gap + max(0, min(menu.y + 4, menu.maxY - PageMenu.height))
        let trailing: CGFloat = 12 + Layout.meterWidth + Layout.gap + (Layout.leftColumn - PageMenu.width) / 2
        return ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { model.pageMenu = nil }
            PageMenu(model: model, page: menu.page) { model.pageMenu = nil }
                .padding(.top, top)
                .padding(.trailing, trailing)
        }
    }
}

/// Заглушка будущей части экрана.
struct Placeholder: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .foregroundStyle(theme.off)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
    }
}

/// Меню бутерброда: APPEARANCE (тема) и DIAGNOSTICS.
struct MainMenu: View {
    let model: AppModel
    @Binding var isOpen: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuHead(title: "APPEARANCE")
            HStack(spacing: 6) {
                ForEach(Appearance.allCases, id: \.self) { a in
                    InkButton(title: a.rawValue, active: model.appearance == a) { model.setAppearance(a) }
                }
            }
            Divider().overlay(theme.line)
            MenuHead(title: "SAMPLER")
            Text("SLICE NOTES").font(.system(size: 9)).foregroundStyle(theme.dim)
            HStack(spacing: 6) {
                InkButton(title: "CHROMATIC", active: model.settings.sliceMap == .chromatic) { model.setSliceMap(.chromatic) }
                InkButton(title: "SCALE", active: model.settings.sliceMap == .scale) { model.setSliceMap(.scale) }
            }
            Text("Notes of slice markers in order: C3, C#3, D3… or steps of the scale from the root in octave 3.")
                .font(.system(size: 12)).foregroundStyle(theme.dim)
            Divider().overlay(theme.line)
            MenuHead(title: "DIAGNOSTICS")
            InkButton(title: "DIAGNOSTICS") {
                isOpen = false
                model.showDiagnostics = true
            }
        }
        .padding(12)
        .frame(width: 330)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
    }
}
