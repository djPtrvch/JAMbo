import SwiftUI

/// Что вводят в окне ввода меню PROJECTS: имя копии (SAVE AS), имя нового проекта при первом SAVE (подставлено
/// случайное), новое имя проекта из списка (карандаш).
enum ProjectInput: Equatable {
    case saveAs
    case saveNew
    case renameId(String)
}

/// Меню PROJECTS (S9c, как ui/projects.ts веба): стрелка назад и «имя · unsaved»; NEW, SAVE, SAVE AS
/// (переименование — карандашом в списке, решение пользователя), EXPORT, IMPORT (S11a, файл .jambo — AppModelFiles);
/// список проектов: тап — окно LOAD / MIX, свайп влево — карандаш и корзина (у Autosave — только корзина).
/// SAVE AS с именем существующего проекта спрашивает, перезаписать ли его. IMPORT кончается окном LOAD / MIX.
struct ProjectsPage: View {
    let model: AppModel
    let back: () -> Void
    let close: () -> Void
    /// EXPORT SONG — страница меню (того же размера).
    var song: () -> Void = {}
    @State private var input: ProjectInput? = nil
    @State private var text: String = ""
    @State private var overwrite: ProjectInfo? = nil
    @State private var opening: ProjectInfo? = nil
    /// EXPORT: готовый временный файл (окно сохранения в «Файлы»); ошибка EXPORT или IMPORT.
    @State private var exported: URL? = nil
    @State private var failure: String? = nil

    var body: some View {
        // Содержимое — AnyView: цепочка модификаторов ниже оборачивает маленький тип (S14, память сборки).
        AnyView(projectsMain)
        .onAppear {
            model.refreshProjects()
            imported(model.projectImport)
        }
        .onChange(of: text) { old, new in
            if new.count > ProjectSession.nameLimit && new.count > old.count { text = old }
        }
        .alert(inputTitle, isPresented: inputShown) {
            TextField(inputTitle, text: $text)
            Button("OK") { enter() }
            Button("Cancel", role: .cancel) {}
        }
        .fileMover(isPresented: exportShown, file: exported) { _ in exported = nil }
        .onChange(of: model.projectImport) { _, r in imported(r) }
        .alert(failure ?? "", isPresented: failureShown) { Button("OK", role: .cancel) {} }
        .alert("Overwrite", isPresented: overwriteShown) {
            Button("CANCEL", role: .cancel) {}
            Button("OVERWRITE", role: .destructive) { confirmOverwrite() }
        } message: {
            Text("“\(overwrite?.name ?? "")” already exists. Overwrite it?")
        }
    }

    private var projectsMain: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            actions
            MenuHead(title: "PROJECTS")
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay { openPanel }
    }

    private var header: some View {
        MenuBackHeader(title: model.unsaved ? "\(model.session.name) · unsaved" : model.session.name, caps: false, back: back)
    }

    /// Три ряда: NEW, SAVE, SAVE AS; EXPORT, IMPORT; EXPORT SONG.
    private var actions: some View {
        VStack(spacing: 4) {
            MenuChoiceButtons(items: [
                MenuChoice(title: "NEW", current: false) {
                    close()
                    model.newProject()
                },
                MenuChoice(title: "SAVE", current: false) { save() },
                MenuChoice(title: "SAVE AS", current: false) { ask(.saveAs, "\(model.session.name) copy") },
            ])
            MenuChoiceButtons(items: [
                MenuChoice(title: "EXPORT", current: false) { export() },
                MenuChoice(title: "IMPORT", current: false) { model.chooseProjectFile() },
            ])
            // Песня из аранжировки в аудиофайл (AppModelSongExport).
            MenuItem(title: "EXPORT SONG") { song() }
        }
    }

    // MARK: — EXPORT, IMPORT (S11a)

    private func export() {
        model.exportProjectFile { url in
            if let u = url { exported = u } else { failure = "Can’t export the project." }
        }
    }

    /// Итог IMPORT: новый проект — окно LOAD / MIX, ошибка — сообщение.
    private func imported(_ r: ProjectImport?) {
        guard let r = r else { return }
        model.projectImport = nil
        switch r {
        case .done(let info): opening = info
        case .failed(let text): failure = text
        }
    }

    private var exportShown: Binding<Bool> {
        Binding(get: { exported != nil }, set: { if !$0 { exported = nil } })
    }

    private var failureShown: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    private var list: AnyView {
        if model.projectList.isEmpty {
            return AnyView(Text("No saved projects yet — save one with SAVE").font(.system(size: 12)).foregroundStyle(theme.dim))
        } else {
            return AnyView(MenuScroll { rows })
        }
    }

    private var rows: some View {
        let items: [ProjectInfo] = model.projectList
        return VStack(spacing: 4) {
            ForEach(items, id: \.id) { info in
                row(info).id("\(info.id)#\(info.name)#\(info.updated)")
            }
        }
    }

    private func row(_ info: ProjectInfo) -> some View {
        let auto: Bool = info.id == ProjectStore.autosaveId
        let title: String = auto ? "\(ProjectSession.autosaveName) · \(info.projectName ?? "")" : info.name
        let edit: (() -> Void)? = auto ? nil : { ask(.renameId(info.id), info.name) }
        let current: Bool = !auto && info.id == model.session.id
        var r = SwipeRow(title: title, subtitle: ProjectsPage.date(info.updated), meta: "\(Int(info.bpm.rounded()))",
                         tint: auto ? theme.accentText : nil, current: current,
                         height: 48, tap: { opening = info }, rename: edit,
                         delete: { model.deleteProject(id: info.id) })
        r.key = (ProjectSession.keyName(info), keyColor(info, current: current))
        return r
    }

    /// Тональность проекта по квинтовому кругу от открытого: жёлтая — та же или соседняя, оранжевая — через 2–3
    /// шага, красная — дальше; у открытого проекта и у Chromatic — цветом строки.
    private func keyColor(_ info: ProjectInfo, current: Bool) -> Color {
        let plain: Color = current ? theme.onAccent : theme.text
        if current { return plain }
        let p = model.project
        guard let d = KeyMatch.distance(scale: p.scale, root: p.root, scale: info.scale, root: info.root) else {
            return plain.opacity(0.65)
        }
        let g: Int = KeyMatch.grade(d)
        return g == 0 ? theme.accentText : (g == 1 ? theme.gr : theme.rec)
    }

    /// LOAD или MIX (переход между проектами, S10).
    @ViewBuilder
    private var openPanel: some View {
        if let info = opening {
            ZStack {
                Color.black.opacity(0.35).onTapGesture { opening = nil }
                OpenProjectPanel(text: openText(info), load: {
                    opening = nil
                    close()
                    model.openProject(id: info.id)
                }, mix: {
                    opening = nil
                    close()
                    model.mixProject(id: info.id)
                }, importRows: {
                    opening = nil
                    if model.importProjectRows(id: info.id) > 0 {
                        close()
                    } else {
                        failure = "Nothing to import: the project has no patterns or the grid has no free rows."
                    }
                })
            }
        }
    }

    /// Текущий проект открывается в сохранённом виде (кнопкой SAVE) — несохранённое пропадёт.
    private func openText(_ info: ProjectInfo) -> String {
        if info.id == model.session.id && model.unsaved {
            return "Open saved “\(info.name)”? Unsaved changes will be lost."
        }
        return "Open “\(info.name)”"
    }

    static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd MMM, HH:mm"
        return f
    }()

    static func date(_ t: Double) -> String {
        return dateFormat.string(from: Date(timeIntervalSince1970: t))
    }

    // MARK: — окна ввода

    /// SAVE: новый (ещё не сохранённый) проект — окно имени со случайным именем, иначе запись сразу.
    private func save() {
        if model.isNewProject {
            ask(.saveNew, ProjectSession.randomName(model.projectList))
        } else {
            model.saveProject()
        }
    }

    private func ask(_ what: ProjectInput, _ initial: String) {
        text = initial
        input = what
    }

    private var inputShown: Binding<Bool> {
        Binding(get: { input != nil }, set: { if !$0 { input = nil } })
    }

    private var overwriteShown: Binding<Bool> {
        Binding(get: { overwrite != nil }, set: { if !$0 { overwrite = nil } })
    }

    private var inputTitle: String {
        switch input {
        case .saveAs: return "SAVE AS"
        case .saveNew: return "SAVE"
        case .renameId: return "RENAME"
        case nil: return ""
        }
    }

    private func enter() {
        let what: ProjectInput? = input
        input = nil
        switch what {
        case .saveAs, .saveNew:
            if let same = model.projectNamed(text) {
                overwrite = same
            } else {
                model.saveProjectAs(text, replace: nil)
            }
        case .renameId(let id):
            model.renameProject(id: id, to: text)
        case nil:
            break
        }
    }

    private func confirmOverwrite() {
        guard let same = overwrite else { return }
        overwrite = nil
        model.saveProjectAs(same.name, replace: same)
    }
}

/// Окно открытия проекта: текст, LOAD, MIX и IMPORT, пояснение.
struct OpenProjectPanel: View {
    let text: String
    let load: () -> Void
    let mix: () -> Void
    let importRows: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 14)).foregroundStyle(theme.text).padding(.horizontal, 6).padding(.top, 4)
            MenuChoiceButtons(items: [
                MenuChoice(title: "LOAD", current: false, action: load),
                MenuChoice(title: "MIX", current: false, action: mix),
                MenuChoice(title: "IMPORT", current: false, action: importRows),
            ])
            Text("LOAD replaces the current project now. MIX keeps the playing patterns in the bottom row (PREV) and blends tempo and settings with the crossfader. IMPORT adds the project’s rows with their sounds to free rows of this grid.")
                .font(.system(size: 12)).foregroundStyle(theme.dim)
        }
        .frame(width: 300)
        .modifier(MenuPanel())
    }
}
