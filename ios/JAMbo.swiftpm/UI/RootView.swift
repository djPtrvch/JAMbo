import SwiftUI
import UniformTypeIdentifiers

/// Главный экран (сверху вниз, как в вебе): верхняя панель, центр, строка дорожек, секвенсор, клавиатура. Низ — ровно
/// три строки дорожек аранжировщика (одна высота строки на весь экран — rowUnit).

struct RootView: View {
    let model: AppModel
    @State private var menuOpen: Bool = false
    /// Верх строки дорожек (низ меню бутерброда).
    @State private var trackTop: CGFloat = 600
    @Environment(\.theme) private var theme

    /// Поля экрана сверху и снизу (решение пользователя: без полей; снизу — и без безопасной зоны полоски «домой»).
    static let padTop: CGFloat = 0
    static let padBottom: CGFloat = 0
    /// Верх меню бутерброда: под верхней панелью и зазором.
    static var menuTop: CGFloat { return padTop + Layout.topHeight + Layout.gap }

    var body: some View {
        let _ = RedrawMeter.hit(.root)
        GeometryReader { geo in
            // Одна высота строки на весь экран (решение пользователя): окно аранжировщика (под второй строкой) —
            // линейка и 8 строк дорожек; низ (строка дорожек, секвенсор, клавиатура) — ровно 3 строки, его верх — верх
            // шестой дорожки; клавиатура — на остаток.
            let units: (bar: CGFloat, unit: CGFloat) = RootView.units(geo.size.height)
            // Низ — три строки и два зазора: его верх — верх шестой дорожки, над ним — зазор между пятой и шестой.
            let lowerH: CGFloat = 3 * units.unit + 2 * Layout.gap
            let piano: CGFloat = lowerH - Layout.trackHeight - Layout.seqHeight - 2 * Layout.gap
            let layout: Layout = Layout(width: geo.size.width - 24, piano: piano)
            ZStack(alignment: .topLeading) {
                theme.bg.ignoresSafeArea()
                screen(layout, lowerH, units.bar, geo.size.height)
                arrangeMeter
                overlays
                if let c = model.choice {
                    ChoiceMenu(model: model, state: c, screen: geo.size)
                }
                if model.pianoMenuOpen {
                    PianoMenu(model: model, layout: layout, screen: geo.size)
                }
                if model.midiLearn.mapTarget != nil {
                    MidiMapWindow(model: model, screen: geo.size)
                }
                if model.midiLearn.on {
                    LearnBar(model: model)
                        .frame(maxWidth: geo.size.width - 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 8)
                }
            }
            .coordinateSpace(name: "root")
        }
        // Клавиатура (имя дорожки, темп числом) не сдвигает экран: поля ввода — в верхней части.
        .ignoresSafeArea(.keyboard)
        // Снизу — до края экрана (под полоской «домой»); сверху — под строкой состояния, если она видна.
        .ignoresSafeArea(.container, edges: .bottom)
        .fileImporter(isPresented: importing, allowedContentTypes: model.importingProject || model.importingLibrary ? [.data] : [.audio],
                      allowsMultipleSelection: !model.importingProject) { result in picked(result) }
        .alert(model.sampleRec.error ?? "", isPresented: recError) {
            Button("OK") { model.sampleRec.error = nil }
        }
        // Окно MIDI MAP открыли из списка маппингов — после закрытия снова меню MIDI (MAPPING).
        .onChange(of: model.midiLearn.reopenMenu) { _, r in if r { menuOpen = true } }
        .alert(model.project.notice ?? "", isPresented: projectNotice) {
            Button("OK") { model.clearNotice() }
        }
    }

    /// Сообщение при открытии проекта (перевод старой версии: пропавший суб ANALOG, S12).
    private var projectNotice: Binding<Bool> {
        Binding(get: { model.project.notice != nil && model.sampleRec.error == nil },
                set: { if !$0 { model.clearNotice() } })
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

    /// Строка кнопок (bar: строка папки над превью, верхняя миниатюра паттернов, вторая строка аранжировщика, верхние
    /// строки EQ и окон мастера) и высота строки дорожки аранжировщика (unit). Аранжировщик — от низа строки кнопок до
    /// низа экрана: линейка, 8 строк и 7 зазоров; низ экрана — 3 строки и 2 зазора; центр — над низом; миниатюры — 8
    /// строк колонки над двумя парами кнопок. bar зависит от центра, центр — от unit, unit — от bar: решается
    /// последовательными приближениями (сходится за несколько шагов).
    static func units(_ h: CGFloat) -> (bar: CGFloat, unit: CGFloat) {
        let g: CGFloat = Layout.gap
        let centerTop: CGFloat = RootView.padTop + Layout.topHeight + g
        let rows: CGFloat = CGFloat(PagesColumn.rows)
        var bar: CGFloat = 40
        var unit: CGFloat = 60
        var k: Int = 0
        while k < 12 {
            let window: CGFloat = h - RootView.padBottom - (centerTop + bar + g)
            unit = max(20, (window - ArrMetrics.top - 7 * g) / 8)
            let lowerH: CGFloat = 3 * unit + 2 * g
            let center: CGFloat = h - RootView.padBottom - centerTop - lowerH - g
            let pages: CGFloat = center - 2 * Layout.pairHeight - 2 * g
            bar = max(24, (pages - PagesColumn.spacing * (rows - 1)) / rows)
            k += 1
        }
        return (bar, unit)
    }

    private func screen(_ layout: Layout, _ lowerH: CGFloat, _ bar: CGFloat, _ h: CGFloat) -> some View {
        // Перенос клипа из сетки на ARRANGE (AppModelCarry): аранжировщик открыт поверх, а сетка остаётся под ним
        // (почти прозрачной), пока палец не отпущен, — её жест не прерывается.
        let carrying: Bool = model.clipCarry != nil
        let arrange: Bool = model.arrangeView && model.browser == nil && !model.rollView
            && (!model.patternView || model.clipCarry?.overArrange == true)
        return VStack(spacing: Layout.gap) {
            TopBar(model: model, menuOpen: $menuOpen)
            ZStack(alignment: .top) {
                if !arrange || carrying {
                    main(layout, lowerH, h).opacity(arrange ? 0.001 : 1)
                }
                if arrange {
                    arrangeArea(layout, lowerH, bar)
                }
            }
        }
        .onChange(of: lowerH, initial: true) { _, h in model.arrLowerH = RootView.arrStepsH(h) }
        .onChange(of: bar, initial: true) { _, b in model.barH = b }
        .padding(.horizontal, 12)
        .padding(.top, RootView.padTop)
        .padding(.bottom, RootView.padBottom)
    }

    /// Обычный экран: центр и низ (высоты — явно, h — высота экрана). STEPS сетки паттернов выключена — как STEPS
    /// аранжировщика: строки дорожек, секвенсора и клавиатуры нет; на их месте — следующие строки сетки (решение
    /// пользователя: клипы и кнопки не растягиваются и не сдвигаются — строки той же высоты, сколько поместится).
    @ViewBuilder
    private func main(_ layout: Layout, _ lowerH: CGFloat, _ h: CGFloat) -> some View {
        // Центр: экран без полей сверху и снизу (RootView.padTop, padBottom), верхней панели, низа и двух зазоров.
        let centerH: CGFloat = max(0, h - RootView.padTop - RootView.padBottom - Layout.topHeight - lowerH - 2 * Layout.gap)
        let tall: Bool = model.patternView && model.project.gridHideSteps
        let rowH: CGFloat = GridGeometry.rowH(centerH, rows: Params.gridRows)
        let pitch: CGFloat = max(1, rowH + PatternGrid.rowGap)
        // Строка может зайти в нижнее поле экрана (padBottom; без поля — только целые строки).
        let more: Int = Int(((Layout.gap + lowerH + RootView.padBottom) / pitch).rounded(.down))
        let rows: Int = tall ? Params.gridRows + more : Params.gridRows
        let gridH: CGFloat = CGFloat(rows) * rowH + CGFloat(rows - 1) * PatternGrid.rowGap
        if tall {
            center(layout).frame(height: gridH)
                .frame(height: centerH + Layout.gap + lowerH, alignment: .top)
                // Низ меню бутерброда — низ экрана.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("root")).maxY } action: { trackTop = $0 }
                .onChange(of: rows, initial: true) { _, n in model.gridRowsShown = n }
        } else {
            VStack(spacing: Layout.gap) {
                center(layout).frame(height: centerH)
                lower(layout).frame(height: lowerH)
            }
            .onChange(of: rows, initial: true) { _, n in model.gridRowsShown = n }
        }
    }

    /// Аранжировщик (решения пользователя): строка кнопок (ArrangeBar) — сверху, слева на месте строки папки над
    /// превью, справа — на месте верхней миниатюры; под ней окно — до низа экрана (дорожки не схлопываются, прокрутка);
    /// STEPS — секвенсор и клавиатура внизу (на тех же местах, что на обычном экране); AUTO — на том же месте; KNOBS —
    /// окно дорожки с ручками и строкой дорожек под ними (как на обычном экране) поверх линейки и верхних дорожек
    /// (строку папки и верхнюю миниатюру закрывает строка кнопок). Проба: строка дорожек — в окне ручек, не в STEPS.
    private func arrangeArea(_ layout: Layout, _ lowerH: CGFloat, _ bar: CGFloat) -> some View {
        let steps: Bool = !model.project.arrange.hideSteps
        let stepsH: CGFloat = RootView.arrStepsH(lowerH)
        return GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ArrangeWindow(model: model)
                    .frame(height: max(0, g.size.height - bar - Layout.gap))
                    .offset(y: bar + Layout.gap)
                // Во время переноса клипа из сетки центр — сетка паттернов (она уже есть под аранжировщиком).
                if model.arrKnobs && !model.patternView {
                    // Фон — и под зазором снизу (чёрная полоса, как между дорожками): из-под окна ничего не видно.
                    VStack(spacing: Layout.gap) {
                        center(layout).frame(height: max(0, g.size.height - lowerH - Layout.gap))
                        TrackRow(model: model, layout: layout)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("root")).minY } action: { trackTop = $0 }
                    }
                    .frame(height: max(0, g.size.height - stepsH), alignment: .top)
                    .background(theme.bg)
                }
                // Над STEPS и AUTO — чёрная полоса (как под окном ручек): дорожки под окном не видны.
                if model.arrAutoPanel {
                    ArrAutoPanel(model: model).frame(height: stepsH)
                        .padding(.top, Layout.gap).background(theme.bg)
                        .offset(y: g.size.height - stepsH - Layout.gap)
                } else if steps {
                    arrSteps(layout).frame(height: stepsH)
                        .padding(.top, Layout.gap).background(theme.bg)
                        .offset(y: g.size.height - stepsH - Layout.gap)
                }
                ArrangeBar(model: model).frame(height: bar)
            }
        }
    }

    /// Высота STEPS и AUTO аранжировщика: низ обычного экрана без строки дорожек (она — в окне ручек).
    static func arrStepsH(_ lowerH: CGFloat) -> CGFloat {
        return max(0, lowerH - Layout.trackHeight - Layout.gap)
    }

    /// STEPS аранжировщика: секвенсор и клавиатура.
    private func arrSteps(_ layout: Layout) -> some View {
        VStack(spacing: Layout.gap) {
            SequencerRow(model: model)
            KeyboardPanel(model: model, layout: layout)
        }
        .background(theme.bg)
        // Меню бутерброда — до верха STEPS, если строки дорожек (окна ручек) нет.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("root")).minY } action: { y in
            if !model.arrKnobs { trackTop = y }
        }
    }

    /// Строка дорожек, секвенсор и клавиатура.
    private func lower(_ layout: Layout) -> some View {
        VStack(spacing: Layout.gap) {
            TrackRow(model: model, layout: layout)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("root")).minY } action: { trackTop = $0 }
            SequencerRow(model: model)
            KeyboardPanel(model: model, layout: layout)
        }
        .background(theme.bg)
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
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { model.meterFrame = $0 }
            }
        }
    }

    /// Аранжировщик: измеритель с регулятором — на месте и размера измерителя окна дорожки (решение пользователя: вниз
    /// не тянется).
    @ViewBuilder
    private var arrangeMeter: some View {
        let f: CGRect = model.meterFrame
        if model.arrangeView && !model.arrKnobs && f != .zero {
            MeterColumn(model: model).frame(width: f.width, height: f.height).offset(x: f.minX, y: f.minY)
        }
    }

    @ViewBuilder
    private var overlays: some View {
        if menuOpen {
            // Тап мимо меню закрывает его.
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { menuOpen = false }
            MainMenu(model: model, isOpen: $menuOpen, height: max(240, trackTop - RootView.menuTop - Layout.gap))
                .padding(.top, RootView.menuTop).padding(.leading, 12)
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

    /// Меню страницы — под её миниатюрой, по рамке колонки миниатюр (как меню звука — по левой колонке); тап мимо — закрыть.
    func pageMenu(_ menu: PageMenuState) -> some View {
        let r: CGRect = model.pagesFrame
        // Помещается под страницей — верх на нижней линии её обводки (на 2 px выше следующей миниатюры); не помещается —
        // от верха колонки и на 4 px выше (над обводкой с её линией): меню закрывает обводку целиком, а не встаёт
        // на её середину.
        let below: CGFloat = menu.y - 2
        let dy: CGFloat = below + PageMenu.height <= menu.maxY + 4 ? below : -4
        let x: CGFloat = r.midX - PageMenu.width / 2
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { model.pageMenu = nil }
            PageMenu(model: model, page: menu.page) { model.pageMenu = nil }
                .offset(x: x, y: r.minY + dy)
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
    case midi
    case sync
}

/// Меню бутерброда (как веб): разделы PROJECT (PROJECTS) и APP (SETTINGS; DIAGNOSTICS, SELF-TEST — окна) — у каждого подзаголовок,
/// между ними черта; CONTROLLERS — MIDI (S13a) и SYNC (S13e). Меню и подменю одного размера: по ширине — от левого края
/// бутерброда до правого края поля SCALE, по высоте — до строки дорожек.
struct MainMenu: View {
    static let width: CGFloat = Layout.leftColumn + Layout.gap + Layout.topButton
    let model: AppModel
    @Binding var isOpen: Bool
    let height: CGFloat
    @State private var page: MenuPage = .main
    @Environment(\.theme) private var theme

    /// Возврат из окна MIDI MAP — сразу меню MIDI.
    private func reopen() {
        guard model.midiLearn.reopenMenu else { return }
        model.midiLearn.reopenMenu = false
        page = .midi
    }

    var body: some View {
        content
            .padding(12)
            .frame(width: MainMenu.width, height: height, alignment: .topLeading)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
            .onAppear { reopen() }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .projects:
            ProjectsPage(model: model, back: { page = .main }, close: { isOpen = false })
        case .settings:
            SettingsPage(model: model, back: { page = .main })
        case .midi:
            MidiMenuPage(model: model, back: { page = .main }, close: { isOpen = false })
        case .sync:
            SyncMenuPage(model: model, back: { page = .main })
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
            Divider().overlay(theme.line).padding(.vertical, 8)
            MenuHead(title: "CONTROLLERS")
            MenuItem(title: "MIDI") { page = .midi }
            MenuItem(title: "SYNC") { page = .sync }
        }
        .padding(.top, 4)
        .padding(.trailing, 6)
    }
}
