import SwiftUI

/// Что вводят в окне ввода браузера.
enum LibInput: Equatable {
    case newFolder
    case rename(String)
    /// SAVE AS… после вопроса о занятом имени.
    case saveAs
}

/// Браузер библиотеки (S11b, как ui/browser.ts веба) на месте центра: вверху ‹, путь, NEW FOLDER, IMPORT, EXPORT (S11c:
/// выбор — файл или .zip, иначе открытая папка .zip, в корне — вся библиотека), ✕;
/// список (папки, потом сэмплы ∿ и пресеты ◆; слева ▶ — предпрослушка; свайп влево — карандаш и корзина);
/// внизу — NAME и SAVE HERE (сохранение), выбор нескольких (LOAD, CANCEL) и строка «что загружено».
struct LibraryBrowser: View {
    let model: AppModel
    @State private var input: LibInput? = nil
    @State private var text: String = ""
    @State private var name: String = ""
    @State private var overwrite: LibNode? = nil
    @State private var confirmId: String = ""
    /// EXPORT: готовый временный файл (окно сохранения в «Файлы»).
    @State private var exported: URL? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Layout.gap) {
            header.frame(height: 48)
            list
            if model.saveMode { saveBar.frame(height: 48) }
            if model.libPicked != nil { pickBar.frame(height: 48) }
            Text(note).font(.system(size: 12)).foregroundStyle(theme.dim).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
        }
        .onAppear { name = model.libDefaultName }
        .onChange(of: model.browser) { _, _ in name = model.libDefaultName }
        .onChange(of: model.libFolder) { _, _ in confirmId = "" }
        .onChange(of: text) { old, new in
            if new.count > Library.nameLimit && new.count > old.count { text = old }
        }
        .alert(inputTitle, isPresented: inputShown) {
            TextField(inputTitle, text: $text)
            Button("OK") { enter() }
            Button("Cancel", role: .cancel) {}
        }
        .fileMover(isPresented: exportShown, file: exported) { _ in exported = nil }
        .confirmationDialog(tableTitle, isPresented: tableShown, titleVisibility: .visible) { tableButtons }
        .alert("“\(overwrite?.name ?? "")” already exists", isPresented: overwriteShown) {
            Button("OVERWRITE", role: .destructive) { confirmOverwrite() }
            Button("SAVE AS…") { askSaveAs() }
            Button("CANCEL", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: Layout.gap) {
            ToolButton(title: "‹", enabled: model.libFolder != Library.root, width: 48) { model.libUp() }
            Text(model.libPath).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                .lineLimit(1).truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            ToolButton(title: "NEW FOLDER", width: 120) { ask(.newFolder, "New folder") }
            ToolButton(title: "IMPORT", width: 96) { model.chooseLibraryFiles() }
            ToolButton(title: "EXPORT", enabled: model.libFolder != LibraryBuiltins.folderId, width: 96) { export() }
            ToolButton(title: "✕", width: 48) { model.closeBrowser() }
        }
    }

    @ViewBuilder
    private var list: some View {
        let items: [LibNode] = model.libItems
        VStack(spacing: 0) {
            if items.isEmpty {
                Text(emptyText).font(.system(size: 12)).foregroundStyle(theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
            } else {
                MenuScroll { rows(items) }.padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func rows(_ items: [LibNode]) -> some View {
        VStack(spacing: 4) {
            ForEach(items, id: \.id) { n in
                LibRow(model: model, node: n, confirm: confirmId == n.id, rename: { ask(.rename(n.id), n.name) },
                       delete: { delete(n) })
                    .id("\(n.id)#\(n.name)#\(n.updated)")
            }
        }
        .padding(.trailing, 6)
    }

    private var saveBar: some View {
        HStack(spacing: Layout.gap) {
            Text("NAME").font(.system(size: 9)).foregroundStyle(theme.dim).padding(.leading, 6)
            TextField("Name", text: $name)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 10).frame(maxHeight: .infinity)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { save() }
                .onChange(of: name) { old, new in
                    if new.count > Library.nameLimit && new.count > old.count { name = old }
                }
            ToolButton(title: "SAVE HERE", width: 130) { save() }
        }
    }

    private var pickBar: some View {
        HStack(spacing: Layout.gap) {
            Text("\(model.libPicked?.count ?? 0) selected · tap " + (model.tableMode ? "tables" : "samples and presets") + " to add or remove")
                .font(.system(size: 12)).foregroundStyle(theme.text).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            ToolButton(title: "LOAD", width: 110) { model.libLoadPicked() }
            ToolButton(title: "CANCEL", width: 110) { model.libPicked = nil }
        }
    }

    private var emptyText: String {
        if model.libFolder == Library.recordings { return "Stems recorded from each track will be saved here." }
        if model.tableMode { return "No tables here. IMPORT a wavetable WAV from the iPad or iCloud Drive." }
        return "Empty folder. NEW FOLDER, or IMPORT files from the iPad or iCloud Drive."
    }

    private var note: String {
        if !model.libNote.isEmpty { return model.libNote }
        let steps: [Int] = model.browserSteps
        switch model.browser ?? .load(steps: []) {
        case .load where !steps.isEmpty: return "Loading a sample onto " + AppModel.stepsLabel(steps).lowercased() + "."
        case .load: return "Tap a sample or preset to load it on the track. Hold one to select several."
        case .loadTable: return "Tap a table to load it on the WTABLE track. IMPORT reads WAV files as wavetables."
        case .ref: return "Tap a sample to use it as the reference track, or IMPORT an audio file."
        default: return "Choose a folder, name it and SAVE HERE."
        }
    }

    // MARK: — размер кадра таблицы (IMPORT в LOAD TABLE)

    private var tableTitle: String {
        return (model.libTableAsk.first?.name ?? "") + ": frame size"
    }

    private var tableShown: Binding<Bool> {
        Binding(get: { !model.libTableAsk.isEmpty }, set: { _ in })
    }

    @ViewBuilder
    private var tableButtons: some View {
        if let t = model.libTableAsk.first {
            let auto: Int = WtWav.autoFrameSize(t.wav)
            Button("AUTO · \(auto) · \(WtWav.framesFor(t.wav, auto)) frames") { model.libAnswerTable(auto) }
            ForEach(WtWav.frameSizes, id: \.self) { s in
                Button("\(s) · \(WtWav.framesFor(t.wav, s)) frames") { model.libAnswerTable(s) }
            }
        }
        Button("CANCEL", role: .cancel) { model.libAnswerTable(nil) }
    }

    // MARK: — действия

    private func export() {
        model.libExport { url in
            if let u = url { exported = u } else { model.libNote = "Nothing to export" }
        }
    }

    private var exportShown: Binding<Bool> {
        Binding(get: { exported != nil }, set: { if !$0 { exported = nil } })
    }

    private func delete(_ n: LibNode) {
        // Непустая папка — второй тап подтверждает (DELETE?).
        if n.kind == .folder && model.library.countInside(n.id) > 0 && confirmId != n.id {
            confirmId = n.id
            return
        }
        confirmId = ""
        model.libDelete(n.id)
    }

    private func save() {
        let n: String = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.libDefaultName : name
        if let same = model.libSameName(n) {
            name = n
            overwrite = same
            return
        }
        model.libSave(n)
    }

    private func confirmOverwrite() {
        guard let same = overwrite else { return }
        overwrite = nil
        model.libSave(name, over: same.id)
    }

    private func askSaveAs() {
        overwrite = nil
        ask(.saveAs, model.libFreeName(name))
    }

    private func ask(_ what: LibInput, _ initial: String) {
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
        case .newFolder: return "NEW FOLDER"
        case .rename: return "RENAME"
        case .saveAs: return "SAVE AS"
        case nil: return ""
        }
    }

    private func enter() {
        let what: LibInput? = input
        input = nil
        switch what {
        case .newFolder: model.libNewFolder(text)
        case .rename(let id): model.libRename(id, text)
        case .saveAs:
            // Если и это имя занято — снова вопрос.
            name = text
            save()
        case nil: break
        }
    }
}
