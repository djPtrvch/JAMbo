import SwiftUI
import UniformTypeIdentifiers

/// Главный экран (сверху вниз, как в вебе): верхняя панель, центр, строка дорожек, секвенсор, клавиатура.

struct RootView: View {
    let model: AppModel
    @State private var menuOpen: Bool = false
    /// Верх строки дорожек (низ меню бутерброда).
    @State private var trackTop: CGFloat = 600
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
        .fileImporter(isPresented: importing, allowedContentTypes: model.importingProject || model.importingLibrary ? [.data] : [.audio],
                      allowsMultipleSelection: !model.importingProject) { result in picked(result) }
        .alert(model.sampleRec.error ?? "", isPresented: recError) {
            Button("OK") { model.sampleRec.error = nil }
        }
    }

    /// REC: запись не началась (нет доступа к входу) — окно с сообщением.
    private var recError: Binding<Bool> {
        Binding(get: { model.sampleRec.error != nil }, set: { if !$0 { model.sampleRec.error = nil } })
    }

    /// Выбранные файлы: проект (IMPORT, один .jambo) или сэмплы (LOAD).
    private func picked(_ result: Result<[URL], Error>) {
        if model.importingLibrary {
            model.importingLibrary = false
            if case .success(let urls) = result { model.libImport(urls) }
            return
        }
        if model.importingProject {
            model.importingProject = false
            if case .success(let urls) = result, let url = urls.first { model.importProjectFile(url) }
            return
        }
        if case .success(let urls) = result { model.importFiles(urls) } else { model.importTarget = nil }
    }

    /// Выбор файлов (LOAD, IMPORT): «Файлы» iPad и iCloud Drive; сэмплов можно сразу несколько.
    private var importing: Binding<Bool> {
        Binding(get: { model.importing }, set: { model.importing = $0 })
    }

    private func screen(_ layout: Layout) -> some View {
        VStack(spacing: Layout.gap) {
            TopBar(model: model, menuOpen: $menuOpen)
            center(layout)
            TrackRow(model: model, layout: layout)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("root")).minY } action: { trackTop = $0 }
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
        if model.browser != nil {
            // Браузер библиотеки — на месте центра (как EQ), справа измеритель.
            HStack(spacing: Layout.gap) {
                LibraryBrowser(model: model)
                MeterColumn(model: model)
            }
        } else if model.rollView {
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
            // Тап мимо меню закрывает его.
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { menuOpen = false }
            MainMenu(model: model, isOpen: $menuOpen, height: max(240, trackTop - 58 - Layout.gap))
                .padding(.top, 58).padding(.leading, 12)
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
        if let f = model.sampleRec.menu {
            RecSourceMenu(model: model, anchor: f, bottom: trackTop)
        }
        if let w = model.appWindow {
            AppWindowView(model: model, window: w).padding(8)
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

/// Пункт бутерброда.
enum MenuPage {
    case main
    case projects
    case settings
}

/// Меню бутерброда (как веб): разделы PROJECT (PROJECTS) и APP (SETTINGS; DIAGNOSTICS, SELF-TEST, LICENSES — окна) — у каждого подзаголовок,
/// между ними черта; CONTROLLERS (MIDI) и SYNC — с S12. Меню и подменю одного размера: по ширине — от левого края
/// бутерброда до правого края поля SCALE, по высоте — до строки дорожек.
struct MainMenu: View {
    static let width: CGFloat = Layout.leftColumn + Layout.gap + Layout.topButton
    let model: AppModel
    @Binding var isOpen: Bool
    let height: CGFloat
    @State private var page: MenuPage = .main
    @Environment(\.theme) private var theme

    var body: some View {
        content
            .padding(12)
            .frame(width: MainMenu.width, height: height, alignment: .topLeading)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .projects:
            ProjectsPage(model: model, back: { page = .main }, close: { isOpen = false })
        case .settings:
            SettingsPage(model: model, back: { page = .main })
        case .main:
            MenuScroll { mainItems }
        }
    }

    private var mainItems: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuHead(title: "PROJECT")
            MenuItem(title: "PROJECTS") { page = .projects }
            Divider().overlay(theme.line).padding(.vertical, 8)
            MenuHead(title: "APP")
            MenuItem(title: "SETTINGS") { page = .settings }
            ForEach(AppWindow.allCases, id: \.self) { w in
                MenuItem(title: w.rawValue) {
                    isOpen = false
                    model.appWindow = w
                }
            }
        }
        .padding(.top, 4)
        .padding(.trailing, 6)
    }
}
