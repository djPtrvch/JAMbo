import SwiftUI

/// Строка браузера библиотеки: слева ▶ (у сэмпла и пресета — предпрослушка, звук не загружает), значок и имя,
/// справа — что это (число в папке, движок пресета). Тап — войти или загрузить, удержание — выбор нескольких (у своих
/// папок — перетаскивание, порядок; свайп, удержание и прокрутка — RowGesture, как у пресетов EQ),
/// свайп влево — карандаш (RENAME) и корзина (у непустой папки — второй тап по DELETE?); у системных — без свайпа.
struct LibRow: View {
    static let height: CGFloat = 44
    static let button: CGFloat = 52
    let model: AppModel
    let node: LibNode
    let confirm: Bool
    let rename: () -> Void
    let delete: () -> Void
    /// Своя папка: удержание — перетаскивание (ReorderState.hold); тап сразу после него не открывает папку.
    var drag: HoldDrag? = nil
    var reorder: ReorderState? = nil
    @State private var offset: CGFloat = 0
    @State private var open: Bool = false
    /// Удержание сработало — отпускание пальца не тап.
    @State private var held: Bool = false

    private var reveal: CGFloat { return 2 * LibRow.button + 4 + (confirm ? 40 : 0) }
    private var playable: Bool { return node.kind == .sample || node.kind == .preset }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions.opacity(offset < -1 ? 1 : 0)
            HStack(spacing: 0) {
                if playable { playButton }
                label
                    .gesture(gesture)
                    .onTapGesture { tapped() }
            }
            .padding(.trailing, max(0, -offset))
        }
        .frame(height: LibRow.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: model.libPicked == nil) { _, none in if none { held = false } }
        .onChange(of: confirm) { _, c in if c && open { withAnimation(.easeOut(duration: 0.2)) { offset = -reveal } } }
    }

    private var current: Bool { return model.libIsCurrent(node) }
    private var picked: Bool { return model.libPicked?.contains(node.id) ?? false }

    private var playButton: some View {
        Button { model.libPreview(node) } label: {
            Text("▶").font(.system(size: 14)).foregroundStyle(theme.text)
                .frame(width: 40, height: LibRow.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        let fg: Color = current ? theme.onAccent : theme.text
        return HStack(spacing: 8) {
            if node.id == Library.recordings {
                Circle().fill(theme.rec).frame(width: 7, height: 7).frame(width: 22)
                Text(node.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
            } else {
                Image(systemName: LibRow.icon(node)).font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
                Text(node.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if offset > -1 {
                Text(detail).font(.system(size: 12)).lineLimit(1).opacity(0.65)
            }
            if picked { Text("✓").font(.system(size: 14, weight: .bold)) }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 12)
        .tile(current ? theme.accent : theme.panel, radius: 8, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.accent, lineWidth: picked ? 1 : 0))
        .contentShape(Rectangle())
    }

    /// Значок по типу (SF Symbols): папка, таблица, сэмпл, пресет синта.
    static func icon(_ n: LibNode) -> String {
        switch n.kind {
        case .folder: return "folder.fill"
        case .table: return "square.grid.3x3.fill"
        case .sample: return "waveform"
        case .preset: return "pianokeys"
        }
    }

    private var detail: String {
        switch node.kind {
        case .folder:
            if node.id == LibraryBuiltins.folderId { return "\(LibraryBuiltins.tables.count)  ›" }
            let c: Int = model.library.children(node.id).count
            if node.id == Library.recordings && c == 0 { return "track stems  ›" }
            return "\(c)  ›"
        case .table:
            let key: String = node.key ?? ""
            return key.hasPrefix("wt:") ? "table · " + (key.split(separator: ":").last.map(String.init) ?? "") : "built-in table"
        case .sample:
            return "sample"
        case .preset:
            // Пресет движка, которого нет (Mutable Instruments), — просто «preset».
            guard let e = node.preset.flatMap({ SynthKey.engine($0.sound) }) else { return "preset" }
            return SynthEngines.engine(e)?.name ?? "preset"
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            icon("pencil", Color(hex: 0x8e8e93), width: LibRow.button) {
                close()
                rename()
            }
            if confirm {
                textButton("DELETE?") { delete() }
            } else {
                icon("trash", theme.rec, width: LibRow.button) { delete() }
            }
        }
    }

    private func icon(_ name: String, _ bg: Color, width: CGFloat, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: width, height: LibRow.height)
                .background(bg, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func textButton(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(.system(size: 12)).foregroundStyle(Color.white)
                .frame(width: LibRow.button + 40, height: LibRow.height)
                .background(theme.rec, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func tapped() {
        if let r = reorder, !r.tapAllowed { return }
        if held {
            held = false
            return
        }
        if open {
            close()
            return
        }
        model.libTap(node)
    }

    /// Удержание: своя папка — перетаскивание; сэмпл или пресет (0,5 с) — выбор нескольких; в LOAD TABLE — таблиц.
    private var hold: HoldDrag {
        if let d = drag, model.libPicked == nil { return d }
        let kinds: Bool = model.tableMode ? node.kind == .table
            : (node.kind == .sample || node.kind == .preset) && model.browser == .load(steps: [])
        guard kinds, model.libPicked == nil else { return HoldDrag.off }
        return HoldDrag(delay: 0.5, began: {
            guard model.libPicked == nil, !open else { return }
            held = true
            model.libHold(node)
        }, changed: { _ in }, ended: {})
    }

    /// Свайп вбок (у системных и в выборе нескольких — нет) и удержание — одним распознавателем; по вертикали —
    /// прокрутка списка.
    private var gesture: RowGesture {
        RowGesture(swipeChanged: { dx in
            if node.isSystem || model.libPicked != nil { return }
            let base: CGFloat = open ? -reveal : 0
            let x: CGFloat = base + dx
            offset = min(0, max(-reveal - 24, x))
        }, swipeEnded: {
            if node.isSystem || model.libPicked != nil { return }
            let show: Bool = offset < -reveal / 2
            open = show
            withAnimation(.easeOut(duration: 0.2)) { offset = show ? -reveal : 0 }
        }, hold: hold)
    }

    private func close() {
        open = false
        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
    }
}
