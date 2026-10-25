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
            let h: CGFloat = ArrLaneMenu.height(model.arrClips(t).count, size.height)
            ArrLaneMenu(model: model, track: t, at: x)
                .frame(height: h)
                .offset(place(a, w: ArrLaneMenu.width, h: h))
        case .track(let t, _):
            ArrTrackMenu(model: model, track: t).offset(trackPlace(t))
        }
    }

    /// Точка таймлайна → окно: меню под пальцем (не помещается — над ним), в пределах окна.
    private func place(_ a: CGPoint, w: CGFloat, h: CGFloat) -> CGSize {
        let ax: CGFloat = a.x + ArrMetrics.headerW + Layout.gap
        let x: CGFloat = max(0, min(ax - w / 2, size.width - w))
        let below: CGFloat = a.y + 12
        let y: CGFloat = below + h <= size.height ? below : max(0, a.y - 12 - h)
        return CGSize(width: x, height: y)
    }

    /// Меню дорожки — справа от её заголовка, по высоте — от строки дорожки.
    private func trackPlace(_ t: Int) -> CGSize {
        let m = ArrMetrics(size: size, port: model.arrPort, tracks: model.project.tracks.count, end: 0)
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
        return min(limit, rows * 40 + max(0, rows - 1) * 6 + 16)
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
    /// 3 строки по 40, палитра 4 ряда по 28, зазоры и поля.
    static let height: CGFloat = 3 * 40 + 4 * 28 + 6 * 6 + 16
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

/// Палитра 20 цветов (5 × 4): выбранный — обводка цветом текста.
struct ArrPaletteGrid: View {
    let current: Int
    let pick: (Int) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let cols: [GridItem] = [GridItem](repeating: GridItem(.flexible(), spacing: 6), count: 5)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<ArrPalette.count, id: \.self) { k in
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
