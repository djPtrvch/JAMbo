import SwiftUI

/// Меню аранжировщика (S15c): блока — COPY, PASTE, DUPLICATE, DELETE; места на дорожке — клипы дорожки и PASTE;
/// дорожки — COPY, PASTE, DUPLICATE и цвет. Тап мимо — закрыть.
struct ArrMenus: View {
    let model: AppModel
    let size: CGSize

    var body: some View {
        if let m = model.arrMenu {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .frame(width: size.width, height: size.height)
                    .onTapGesture { model.arrMenu = nil }
                menu(m)
            }
        }
    }

    @ViewBuilder
    private func menu(_ m: ArrMenuState) -> some View {
        switch m {
        case .block(let t, let i, let a):
            ArrBlockMenu(model: model, sel: ArrSel(track: t, block: i))
                .offset(place(a, w: ArrBlockMenu.width, h: ArrBlockMenu.height))
        case .lane(let t, let x, let a):
            laneMenu(t, x, a)
        case .track(let t, _):
            ArrTrackMenu(model: model, track: t).offset(trackPlace(t))
        case .marker(let k, let a):
            ArrMarkerWindow(model: model, index: k).offset(place(a, w: ArrMarkerWindow.width, h: ArrMarkerWindow.height))
        case .insert(let t, let x, let a):
            insertMenu(t, x, a)
        case .range(let a):
            ArrRangeMenu(model: model, anchor: a).offset(place(a, w: ArrRangeMenu.width, h: ArrRangeMenu.height))
        }
    }

    private func laneMenu(_ t: Int, _ x: Int, _ a: CGPoint) -> some View {
        let n: Int = model.arrClips(t).count
        let h: CGFloat = ArrLaneMenu.height(n, size.height)
        let o: CGSize = place(a, w: ArrLaneMenu.width, h: h)
        return ArrLaneMenu(model: model, track: t, at: x).frame(height: h).offset(o)
    }

    private func insertMenu(_ t: Int, _ x: Int, _ a: CGPoint) -> some View {
        let n: Int = model.arrClips(t).count
        let h: CGFloat = ArrLaneMenu.height(max(0, n - 1), size.height)
        let o: CGSize = place(a, w: ArrLaneMenu.width, h: h)
        return ArrInsertMenu(model: model, track: t, at: x).frame(height: h).offset(o)
    }

    /// Точка таймлайна → окно: меню под пальцем (не помещается — над ним), в пределах окна.
    private func place(_ a: CGPoint, w: CGFloat, h: CGFloat) -> CGSize {
        let ax: CGFloat = a.x + ArrMetrics.headerW + Layout.gap
        let left: CGFloat = ax - w / 2
        let right: CGFloat = size.width - w
        let x: CGFloat = max(0, min(left, right))
        let below: CGFloat = a.y + 12
        let above: CGFloat = max(0, a.y - 12 - h)
        let fits: Bool = below + h <= size.height
        let y: CGFloat = fits ? below : above
        return CGSize(width: x, height: y)
    }

    /// Меню дорожки — справа от её заголовка, по высоте — от строки дорожки.
    private func trackPlace(_ t: Int) -> CGSize {
        let m = ArrMetrics(size: size, port: model.arrPort, tracks: model.project.tracks.count, end: 0, expanded: model.settings.arrangeExpanded)
        let h: CGFloat = ArrTrackMenu.height
        let y: CGFloat = max(0, min(m.rowY(t), size.height - h))
        return CGSize(width: ArrMetrics.headerW + Layout.gap, height: y)
    }
}

struct ArrBlockMenu: View {
    static let width: CGFloat = 180
    /// 4 строки по 40, 3 зазора по 6, поля 16.
    static let height: CGFloat = 194
    let model: AppModel
    let sel: ArrSel

    var body: some View {
        VStack(spacing: 6) {
            MenuItem(title: "COPY") { run { model.arrCopyBlock(sel) } }
            MenuItem(title: "PASTE", enabled: model.arrBlockClipboard != nil) { run { model.arrPasteBlock(after: sel) } }
            MenuItem(title: "DUPLICATE") { run { model.arrDuplicateBlock(sel) } }
            MenuItem(title: "DELETE", red: true) { run { model.arrDeleteBlock(sel) } }
        }
        .frame(width: ArrBlockMenu.width)
        .modifier(MenuPanel())
    }

    private func run(_ f: () -> Void) {
        model.arrMenu = nil
        f()
    }
}

/// Меню места: клипы дорожки (имя строки) — блок встаёт на ближайшую линию сетки; PASTE — скопированный блок сюда.
struct ArrLaneMenu: View {
    static let width: CGFloat = 200
    let model: AppModel
    let track: Int
    let at: Int

    static func height(_ clips: Int, _ limit: CGFloat) -> CGFloat {
        let rows: CGFloat = CGFloat(clips + 1)
        let items: CGFloat = rows * 40
        let gaps: CGFloat = max(0, rows - 1) * 6
        let total: CGFloat = items + gaps + 16
        return min(limit, total)
    }

    var body: some View {
        let clips: [Int] = model.arrClips(track)
        return MenuScroll {
            VStack(spacing: 6) {
                MenuItem(title: "PASTE", enabled: model.arrBlockClipboard != nil) {
                    run { model.arrPasteBlock(track: track, at: at) }
                }
                ForEach(clips, id: \.self) { k in
                    MenuItem(title: model.arrClipName(k)) { run { model.arrAddBlock(track: track, clip: k, at: at) } }
                }
            }
        }
        .frame(width: ArrLaneMenu.width)
        .modifier(MenuPanel())
    }

    private func run(_ f: () -> Void) {
        model.arrMenu = nil
        f()
    }
}

/// Меню дорожки: COPY (все блоки), PASTE (заменяет блоки дорожки), DUPLICATE (ещё раз после последнего), палитра.
struct ArrTrackMenu: View {
    static let width: CGFloat = 220
    /// 4 строки по 40 (160, с DEFAULT), палитра 3 ряда по 22 и 2 зазора (78), 4 зазора по 6 (24), поля 16.
    static let height: CGFloat = 278
    let model: AppModel
    let track: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let cur: Int = track < model.project.tracks.count ? model.project.tracks[track].color : ArrPalette.defaultColor
        return VStack(spacing: 6) {
            MenuItem(title: "COPY") { run { model.arrCopyTrack(track) } }
            MenuItem(title: "PASTE", enabled: model.arrTrackClipboard != nil) { run { model.arrPasteTrack(track) } }
            MenuItem(title: "DUPLICATE") { run { model.arrDuplicateTrack(track) } }
            ArrPaletteGrid(current: cur) { c in model.arrSetTrackColor(track, c) }
        }
        .frame(width: ArrTrackMenu.width)
        .modifier(MenuPanel())
    }

    private func run(_ f: () -> Void) {
        model.arrMenu = nil
        f()
    }
}

/// Цвет: DEFAULT (цвет по умолчанию) и палитра без белого — 18 цветов, 6 × 3; выбранный — обводка цветом текста.
struct ArrPaletteGrid: View {
    let current: Int
    let pick: (Int) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let cols: [GridItem] = [GridItem](repeating: GridItem(.flexible(), spacing: 6), count: 6)
        let list: [Int] = ArrPalette.choices
        return VStack(spacing: 6) {
            // DEFAULT — цветом по умолчанию (как заголовок дорожки), выбранный — обводка, как у цветов.
            Text("DEFAULT")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(theme.trackBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(current == ArrPalette.defaultColor ? theme.text : Color.clear,
                                                                lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { pick(ArrPalette.defaultColor) }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(list, id: \.self) { k in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ArrColors.color(k))
                        .frame(height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(k == current ? theme.text : Color.clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture { pick(k) }
                }
            }
        }
    }
}

/// INSERT: клипы дорожки — выбранный вставляется в точку, блоки дорожки правее сдвигаются.
struct ArrInsertMenu: View {
    let model: AppModel
    let track: Int
    let at: Int

    var body: some View {
        let clips: [Int] = model.arrClips(track)
        return MenuScroll {
            VStack(spacing: 6) {
                ForEach(clips, id: \.self) { k in
                    MenuItem(title: model.arrClipName(k)) {
                        model.arrMenu = nil
                        model.arrInsertBlock(track: track, clip: k, at: at)
                    }
                }
            }
        }
        .frame(width: ArrLaneMenu.width)
        .modifier(MenuPanel())
    }
}

/// Окно маркера: имя (до 12 знаков; клавиатура — по тапу в поле), цвет, DELETE, OK. Имя сохраняется
/// и при закрытии тапом мимо.
struct ArrMarkerWindow: View {
    static let width: CGFloat = 240
    /// Имя 44, DEFAULT 40, палитра 78, 2 строки по 40, 5 зазоров по 6, поля 16.
    static let height: CGFloat = 288
    let model: AppModel
    let index: Int
    @State private var name: String = ""
    @State private var loaded: Bool = false
    @State private var deleted: Bool = false
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let cur: Int = model.arrMarker(index)?.color ?? ArrPalette.defaultColor
        return VStack(spacing: 6) {
            TextField("name", text: $name)
                .font(.system(size: 16))
                .focused($focused)
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
                .onSubmit { done() }
            ArrPaletteGrid(current: cur) { c in model.arrSetMarkerColor(index, c) }
            MenuItem(title: "DELETE", red: true) { delete() }
            MenuItem(title: "OK") { done() }
        }
        .frame(width: ArrMarkerWindow.width)
        .modifier(MenuPanel())
        .onAppear { load() }
        .onDisappear { if !deleted { model.arrRenameMarker(index, name) } }
    }

    private func load() {
        if loaded { return }
        loaded = true
        let m: ArrMarker? = model.arrMarker(index)
        name = m?.name ?? ""
    }

    private func done() {
        model.arrMenu = nil
    }

    private func delete() {
        deleted = true
        model.arrMenu = nil
        model.arrDeleteMarker(index)
    }

    /// Действие с маркером: сначала имя.
    private func act(_ f: () -> Void) {
        model.arrRenameMarker(index, name)
        model.arrMenu = nil
        f()
    }
}

/// Меню выделенного диапазона (двойной тап по нему на линейке): ADD SECTION — маркер секции в начале диапазона и окно
/// с именем; SPLIT — блоки всех дорожек разрезаются по краям диапазона. Зациклить — кнопка LOOP.
struct ArrRangeMenu: View {
    static let width: CGFloat = 180
    /// 2 строки по 40, зазор 6, поля 16.
    static let height: CGFloat = 102
    let model: AppModel
    let anchor: CGPoint

    var body: some View {
        VStack(spacing: 6) {
            MenuItem(title: "ADD SECTION") { model.arrSectionAtRange(anchor: anchor) }
            MenuItem(title: "SPLIT") {
                model.arrMenu = nil
                model.arrSplitRange()
            }
        }
        .frame(width: ArrRangeMenu.width)
        .modifier(MenuPanel())
    }
}
