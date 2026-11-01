import SwiftUI

/// Меню аранжировщика (S15c): блока — COPY, PASTE, DUPLICATE, DELETE; места на дорожке — клипы дорожки и PASTE;
/// дорожки — COPY, PASTE, DUPLICATE и цвет. Тап мимо — закрыть. Меню — только на свободном месте окна: над окнами
/// STEPS и AUTO (решение пользователя).
struct ArrMenus: View {
    let model: AppModel
    let size: CGSize

    /// Низ свободного места: окно без закрытого STEPS или AUTO.
    private var free: CGFloat {
        return max(0, size.height - model.arrInset)
    }

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

    private func menu(_ m: ArrMenuState) -> AnyView {
        switch m {
        case .block(let t, let i, let a):
            return AnyView(ArrBlockMenu(model: model, sel: ArrSel(track: t, block: i))
                .offset(place(a, w: ArrBlockMenu.width, h: ArrBlockMenu.height)))
        case .lane(let t, let x, let a):
            return AnyView(laneMenu(t, x, a))
        case .track(let t, _):
            return AnyView(ArrTrackMenu(model: model, track: t).offset(trackPlace(t)))
        case .marker(let k, let a):
            // Своё окно у каждой секции (ADD SECTION открывает окно новой — с пустым именем).
            return AnyView(ArrMarkerWindow(model: model, index: k).id(k).offset(place(a, w: ArrMarkerWindow.width, h: ArrMarkerWindow.height)))
        case .insert(let t, let x, let a):
            return AnyView(insertMenu(t, x, a))
        case .ref:
            return AnyView(ArrRefMenu(model: model).offset(CGSize(width: ArrMetrics.headerW, height: ArrMetrics.top)))
        case .drop(let a):
            return AnyView(ArrDropMenu(model: model).offset(place(a, w: ArrDropMenu.width, h: ArrDropMenu.height)))
        case .grid:
            // Под кнопкой сетки — у левого края окна.
            return AnyView(ArrGridMenu(model: model))
        case .ruler(let a):
            return AnyView(ArrRulerMenu(model: model, anchor: a).offset(place(a, w: ArrRulerMenu.width, h: ArrRulerMenu.height(model, a))))
        }
    }

    private func laneMenu(_ t: Int, _ x: Int, _ a: CGPoint) -> some View {
        let n: Int = model.arrClips(t).count
        let h: CGFloat = ArrLaneMenu.height(n, free)
        let o: CGSize = place(a, w: ArrLaneMenu.width, h: h)
        return ArrLaneMenu(model: model, track: t, at: x).frame(height: h).offset(o)
    }

    private func insertMenu(_ t: Int, _ x: Int, _ a: CGPoint) -> some View {
        let n: Int = model.arrClips(t).count
        let h: CGFloat = ArrLaneMenu.height(max(0, n - 1), free)
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
        let fits: Bool = below + h <= free
        // Палец над окном STEPS или AUTO и сверху не помещается — вплотную к нему сверху.
        let y: CGFloat = fits ? below : max(0, min(above, free - h))
        return CGSize(width: x, height: y)
    }

    /// Меню дорожки — справа от её заголовка, по высоте — от строки дорожки.
    private func trackPlace(_ t: Int) -> CGSize {
        let m = ArrMetrics(size: size, port: model.arrPort, tracks: model.project.tracks.count, end: 0, expanded: model.settings.arrangeExpanded,
                           inset: model.arrInset, ref: model.arrRefShown)
        let h: CGFloat = ArrTrackMenu.height
        let y: CGFloat = max(0, min(m.rowY(t), free - h))
        // От начала таймлайна (решение пользователя).
        return CGSize(width: ArrMetrics.headerW, height: y)
    }
}

/// Меню REF: LOAD — браузер (другой файл), DELETE — референса нет.
struct ArrRefMenu: View {
    static let width: CGFloat = 180
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        return MenuChoiceColumn(items: [
            MenuChoice(title: "LOAD", current: false) { m.arrMenu = nil; m.openBrowser(.ref) },
            MenuChoice(title: "DELETE", red: true, current: false) { m.arrMenu = nil; m.arrDeleteRef() },
        ])
        .frame(width: ArrRefMenu.width)
        .modifier(MenuPanel())
    }
}

struct ArrBlockMenu: View {
    static let width: CGFloat = 180
    /// 5 строк по 40, 4 зазора по 6, поля 16.
    static let height: CGFloat = 240
    let model: AppModel
    let sel: ArrSel

    var body: some View {
        // Блок группы (выделение рамкой): DUPLICATE и DELETE — всей группы, COPY и PASTE — только у одного блока.
        let group: Bool = model.arrInGroup(sel)
        let m: AppModel = model
        let b: ArrSel = sel
        return MenuChoiceColumn(items: [
            MenuChoice(title: "COPY", enabled: !group, current: false) { m.arrMenu = nil; m.arrCopyBlock(b) },
            MenuChoice(title: "PASTE", enabled: !group && m.arrBlockClipboard != nil, current: false) { m.arrMenu = nil; m.arrPasteBlock(after: b) },
            MenuChoice(title: "DUPLICATE", current: false) {
                m.arrMenu = nil
                if group { m.arrDuplicateGroup() } else { m.arrDuplicateBlock(b) }
            },
            // LINK (решение пользователя): автоматизация блока соединяется со следующим блоком дорожки; неактивна — не горит.
            MenuChoice(title: "LINK AUTO", enabled: !group && m.arrCanLink(b), current: !group && m.arrCanLink(b) && (m.arrBlock(b)?.autoLink ?? false)) {
                m.arrMenu = nil
                m.arrToggleLink(b)
            },
            MenuChoice(title: "DELETE", red: true, current: false) {
                m.arrMenu = nil
                if group { m.arrDeleteGroup() } else { m.arrDeleteBlock(b) }
            },
        ])
        .frame(width: ArrBlockMenu.width)
        .modifier(MenuPanel())
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
        let m: AppModel = model
        let t: Int = track
        let x: Int = at
        var items: [MenuChoice] = [MenuChoice(title: "PASTE", enabled: m.arrBlockClipboard != nil, current: false) {
            m.arrMenu = nil
            m.arrPasteBlock(track: t, at: x)
        }]
        for k in clips {
            items.append(MenuChoice(title: m.arrClipName(k), current: false) {
                m.arrMenu = nil
                m.arrAddBlock(track: t, clip: k, at: x)
            })
        }
        return MenuScroll {
            MenuChoiceColumn(items: items)
        }
        .frame(width: ArrLaneMenu.width)
        .modifier(MenuPanel())
    }
}

/// Меню дорожки: COPY (все блоки), PASTE (заменяет блоки дорожки), DUPLICATE (ещё раз после последнего), палитра.
struct ArrTrackMenu: View {
    static let width: CGFloat = 220
    /// 3 строки по 40 (120), палитра 3 ряда квадратов по 29 и 2 зазора (99), 3 зазора по 6 (18), поля 16.
    static let height: CGFloat = 253
    let model: AppModel
    let track: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let cur: Int = track < model.project.tracks.count ? model.project.tracks[track].color : ArrPalette.defaultColor
        let m: AppModel = model
        let t: Int = track
        return VStack(spacing: 6) {
            MenuChoiceColumn(items: [
                MenuChoice(title: "COPY", current: false) { m.arrMenu = nil; m.arrCopyTrack(t) },
                MenuChoice(title: "PASTE", enabled: m.arrTrackClipboard != nil, current: false) { m.arrMenu = nil; m.arrPasteTrack(t) },
                MenuChoice(title: "DUPLICATE", current: false) { m.arrMenu = nil; m.arrDuplicateTrack(t) },
            ])
            ArrPaletteGrid(current: cur, none: true) { c in m.arrSetTrackColor(t, c) }
        }
        .frame(width: ArrTrackMenu.width)
        .modifier(MenuPanel())
    }
}

/// Цвет: палитра без белого, 6 в ряд; выбранный — обводка цветом текста. Первый квадратик — цвет по умолчанию: у дорожки
/// «нет цвета» (перечёркнутый круг; заголовок — как строка дорожек), у секции — сам этот цвет (решение пользователя).
struct ArrPaletteGrid: View {
    let current: Int
    let none: Bool
    let pick: (Int) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let cols: [GridItem] = [GridItem](repeating: GridItem(.flexible(), spacing: 6), count: 6)
        let list: [Int] = [ArrPalette.defaultColor] + ArrPalette.choices
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(list, id: \.self) { k in
                // Квадратики (решение пользователя).
                swatch(k)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(k == current ? theme.text : Color.clear, lineWidth: 2))
                    .contentShape(Rectangle())
                    .onTapGesture { pick(k) }
            }
        }
    }

    private func swatch(_ k: Int) -> AnyView {
        if none && k == ArrPalette.defaultColor {
            return AnyView(RoundedRectangle(cornerRadius: 4)
                .fill(theme.trackBg)
                .overlay(Image(systemName: "nosign").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.dim)))
        } else {
            return AnyView(RoundedRectangle(cornerRadius: 4).fill(ArrColors.color(k)))
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
/// Окно секции (RENAME в меню линейки, новая секция): NAME, DELETE, OK.
struct ArrMarkerWindow: View {
    static let width: CGFloat = 240
    /// Имя 44, 2 строки по 40, 2 зазора по 6, поля 16 (цвета у секции нет — решение пользователя).
    static let height: CGFloat = 152
    let model: AppModel
    let index: Int
    @State private var name: String = ""
    @State private var loaded: Bool = false
    @State private var deleted: Bool = false
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            TextField("name", text: $name)
                .font(.system(size: 16))
                .focused($focused)
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
                .onSubmit { done() }
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

/// Выделение из сетки положили поверх блоков (решение пользователя): HERE — прямо здесь (перекрытое заменяется),
/// INSERT — раздвинуть (всё с этого места — правее на длину выделения), TO END — в конец аранжировки. Тап мимо —
/// ничего не кладётся.
struct ArrDropMenu: View {
    static let width: CGFloat = 180
    /// 3 строки по 40, 2 зазора по 6, поля 16.
    static let height: CGFloat = 148
    let model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            MenuItem(title: "HERE") { model.arrDrop(.here) }
            MenuItem(title: "INSERT") { model.arrDrop(.insert) }
            MenuItem(title: "TO END") { model.arrDrop(.end) }
        }
        .frame(width: ArrDropMenu.width)
        .modifier(MenuPanel())
    }
}

/// Меню кнопки сетки (решение пользователя; из SETTINGS → ARRANGE): шаг сетки (1 BAR, 1/2, 1/4, 1 STEP) и ниже рычажок
/// SNAP TO GRID (привязка к линиям сетки, прежний магнит). У проекта, с UNDO; меню не закрывается.
struct ArrGridMenu: View {
    static let width: CGFloat = Layout.leftColumn + 40
    let model: AppModel

    var body: some View {
        let a: Arrangement = model.project.arrange
        return VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "GRID")
            HStack(spacing: 4) {
                ForEach(0..<ArrGrid.names.count, id: \.self) { k in
                    MenuItem(title: ArrGrid.names[k], current: a.grid == k) { model.setArrGrid(k) }
                }
            }
            ToggleRow(title: "SNAP TO GRID", isOn: a.snap) { v in if v != a.snap { model.toggleArrSnap() } }
        }
        .frame(width: ArrGridMenu.width)
        .modifier(MenuPanel())
    }
}

/// Меню линейки (двойной тап, решение пользователя): на секции — RENAME (окно секции), DELETE SECTION; вне секции —
/// ADD SECTION (секция на выделенном диапазоне под пальцем, иначе на такте). SPLIT убран (решение пользователя).
struct ArrRulerMenu: View {
    static let width: CGFloat = 180
    let model: AppModel
    let anchor: CGPoint

    /// 2 строки или 1 по 40, зазоры 6, поля 16.
    static func height(_ model: AppModel, _ a: CGPoint) -> CGFloat {
        return model.arrSectionAt(anchor: a) != nil ? 102 : 56
    }

    var body: some View {
        let k: Int? = model.arrSectionAt(anchor: anchor)
        return VStack(spacing: 6) {
            if let s = k {
                MenuItem(title: "RENAME") { model.arrMenu = .marker(index: s, anchor: anchor) }
            } else {
                MenuItem(title: "ADD SECTION") { model.arrSectionHere(anchor: anchor) }
            }
            if let s = k {
                MenuItem(title: "DELETE SECTION", red: true) {
                    model.arrMenu = nil
                    model.arrDeleteMarker(s)
                }
            }
        }
        .frame(width: ArrRulerMenu.width)
        .modifier(MenuPanel())
    }
}

