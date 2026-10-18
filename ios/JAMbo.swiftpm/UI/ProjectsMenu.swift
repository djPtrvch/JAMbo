import SwiftUI

/// Что вводят в окне ввода меню PROJECTS: имя копии (SAVE AS), новое имя текущего (RENAME), проекта из списка.
enum ProjectInput: Equatable {
    case saveAs
    case rename
    case renameId(String)
}

/// Меню PROJECTS (S9c, как ui/projects.ts веба): стрелка назад и «имя · unsaved»; NEW, SAVE, SAVE AS, RENAME
/// (EXPORT, IMPORT — S11); список проектов: тап — окно LOAD / MIX, свайп влево — карандаш и корзина (у Autosave —
/// только корзина). SAVE AS с именем существующего проекта спрашивает, перезаписать ли его.
struct ProjectsPage: View {
    let model: AppModel
    let back: () -> Void
    let close: () -> Void
    @State private var input: ProjectInput? = nil
    @State private var text: String = ""
    @State private var overwrite: ProjectInfo? = nil
    @State private var opening: ProjectInfo? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            actions
            MenuHead(title: "PROJECTS")
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay { openPanel }
        .onAppear { model.refreshProjects() }
        .onChange(of: text) { old, new in
            if new.count > ProjectSession.nameLimit && new.count > old.count { text = old }
        }
        .alert(inputTitle, isPresented: inputShown) {
            TextField(inputTitle, text: $text)
            Button("OK") { enter() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Overwrite", isPresented: overwriteShown) {
            Button("CANCEL", role: .cancel) {}
            Button("OVERWRITE", role: .destructive) { confirmOverwrite() }
        } message: {
            Text("“\(overwrite?.name ?? "")” already exists. Overwrite it?")
        }
    }

    private var header: some View {
        MenuBackHeader(title: model.unsaved ? "\(model.session.name) · unsaved" : model.session.name, back: back)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            MenuItem(title: "NEW") {
                close()
                model.newProject()
            }
            MenuItem(title: "SAVE") { model.saveProject() }
            MenuItem(title: "SAVE AS") { ask(.saveAs, "\(model.session.name) copy") }
            MenuItem(title: "RENAME") { ask(.rename, model.session.name) }
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.projectList.isEmpty {
            Text("No saved projects yet — save one with SAVE").font(.system(size: 12)).foregroundStyle(theme.dim)
        } else {
            MenuScroll { rows }
        }
    }

    private var rows: some View {
        let items: [ProjectInfo] = model.projectList
        return VStack(spacing: 4) {
            ForEach(items, id: \.id) { info in
                row(info).id("\(info.id)#\(info.name)#\(info.updated)")
            }
        }
        .padding(.trailing, 6)
    }

    private func row(_ info: ProjectInfo) -> some View {
        let auto: Bool = info.id == ProjectStore.autosaveId
        let title: String = auto ? "\(ProjectSession.autosaveName) · \(info.projectName ?? "")" : info.name
        let edit: (() -> Void)? = auto ? nil : { ask(.renameId(info.id), info.name) }
        return SwipeRow(title: title, subtitle: ProjectsPage.date(info.updated), meta: ProjectSession.meta(info),
                        tint: auto ? theme.accentText : nil, current: !auto && info.id == model.session.id,
                        height: 48, tap: { opening = info }, rename: edit,
                        delete: { model.deleteProject(id: info.id) })
    }

    /// LOAD или MIX (MIX — переход между проектами, S10: пока серая).
    @ViewBuilder
    private var openPanel: some View {
        if let info = opening {
            ZStack {
                Color.black.opacity(0.35).onTapGesture { opening = nil }
                OpenProjectPanel(text: openText(info), load: {
                    opening = nil
                    close()
                    model.openProject(id: info.id)
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
        case .rename, .renameId: return "RENAME"
        case nil: return ""
        }
    }

    private func enter() {
        let what: ProjectInput? = input
        input = nil
        switch what {
        case .saveAs:
            if let same = model.projectNamed(text) {
                overwrite = same
            } else {
                model.saveProjectAs(text, replace: nil)
            }
        case .rename:
            model.renameProject(text)
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

/// Окно открытия проекта: текст, LOAD и MIX (серая до S10), пояснение.
struct OpenProjectPanel: View {
    let text: String
    let load: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 14)).foregroundStyle(theme.text).padding(.horizontal, 6).padding(.top, 4)
            HStack(spacing: 4) {
                MenuItem(title: "LOAD", action: load)
                MenuItem(title: "MIX", enabled: false) {}
            }
            Text("LOAD replaces the current project now. MIX keeps the playing patterns in the bottom row (PREV) and blends tempo and settings with the crossfader.")
                .font(.system(size: 12)).foregroundStyle(theme.dim)
        }
        .frame(width: 300)
        .modifier(MenuPanel())
    }
}
