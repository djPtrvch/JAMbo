import SwiftUI

/// Сетка паттернов (PATTERNS): колонка строк над MIX, столбцы дорожек ровно над дорожками, справа (над MST) —
/// бутерброд сетки, LOOP ROW и стрелки окна строк. На экране 8 строк. Жесты — одним касанием на всю сетку.
struct PatternGrid: View {
    let model: AppModel
    let layout: Layout
    @State private var press: GridPress? = nil
    @State private var ghost: CGPoint? = nil
    @State private var target: CellRef? = nil

    static let rowGap: CGFloat = 4
    static let hold: Double = 0.5
    static let flick: Double = 0.28

    var body: some View {
        GeometryReader { geo in
            let g = GridGeometry(size: geo.size, step: layout.step, tracks: model.project.tracks.count)
            ZStack(alignment: .topLeading) {
                cells(g)
                ghostView(g)
                PatternMenus(model: model, geometry: g)
            }
            .contentShape(Rectangle())
            .gesture(touch(g))
        }
    }

    @ViewBuilder
    private func cells(_ g: GridGeometry) -> some View {
        let w = model.gridWindow
        ForEach(0..<Params.gridRows, id: \.self) { r in
            if let k = w.rows[r] {
                SceneCellView(model: model, row: k).frame(width: g.sceneW, height: g.rowH).offset(g.origin(col: -1, row: r))
                ForEach(0..<g.tracks, id: \.self) { i in
                    ClipCellView(model: model, cell: CellRef(track: i, row: k), lifted: press?.cell == CellRef(track: i, row: k) && ghost != nil,
                                 target: target == CellRef(track: i, row: k))
                        .frame(width: g.trackW, height: g.rowH).offset(g.origin(col: i, row: r))
                }
            } else if w.plusRow == r {
                PlusCell().frame(width: g.sceneW, height: g.rowH).offset(g.origin(col: -1, row: r))
            }
        }
        GridSideButtons(model: model, scroll: w.maxTop > 0, canUp: w.top > 0, canDown: w.top < w.maxTop)
            .frame(width: g.sceneW, height: g.size.height).offset(x: g.size.width - g.sceneW)
    }

    @ViewBuilder
    private func ghostView(_ g: GridGeometry) -> some View {
        if let p = ghost, let c = press?.cell {
            ClipCellView(model: model, cell: c, lifted: false, target: false)
                .frame(width: g.trackW, height: g.rowH)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.5), radius: 10)
                .offset(x: p.x - g.trackW / 2, y: p.y - g.rowH / 2)
                .allowsHitTesting(false)
        }
    }

    // MARK: — жесты

    private func touch(_ g: GridGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if press == nil { begin(g, at: v.startLocation) }
                move(g, v)
            }
            .onEnded { v in end(g, v) }
    }

    private func begin(_ g: GridGeometry, at p: CGPoint) {
        model.ensureAudio()
        let hit = g.hit(p, window: model.gridWindow)
        var gp = GridPress(hit: hit, t0: Date())
        if case .cell(let c) = hit { gp.cell = c }
        press = gp
        let started = gp.t0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(PatternGrid.hold * 1e9))
            guard var cur = press, cur.t0 == started, !cur.moved, ghost == nil else { return }
            cur.held = true
            press = cur
            switch cur.hit {
            case .cell(let c): model.holdCell(c.track, c.row)
            case .scene(let k): model.rowMenu = k
            default: break
            }
        }
    }

    private func move(_ g: GridGeometry, _ v: DragGesture.Value) {
        guard var p = press, !p.held else { return }
        let dx: CGFloat = v.translation.width
        let dy: CGFloat = v.translation.height
        if hypot(dx, dy) > 12 { p.moved = true }
        press = p
        guard let c = p.cell, model.project.tracks[c.track].clipFilled(c.row) else { return }
        let early: Bool = Date().timeIntervalSince(p.t0) < PatternGrid.flick && -dy > abs(dx)
        if ghost == nil && (early || hypot(dx, dy) <= 12) { return }
        ghost = v.location
        if case .cell(let t) = g.hit(v.location, window: model.gridWindow), t != c { target = t } else { target = nil }
    }

    private func end(_ g: GridGeometry, _ v: DragGesture.Value) {
        guard let p = press else { return }
        press = nil
        let dropped = target
        let dragged: Bool = ghost != nil
        ghost = nil
        target = nil
        if p.held { return }
        let dx: CGFloat = v.translation.width
        let dy: CGFloat = v.translation.height
        let flick: Bool = Date().timeIntervalSince(p.t0) < PatternGrid.flick && -dy > 24 && abs(dx) < -dy
        if let c = p.cell {
            if flick {
                model.cellMenu = CellMenuState(cell: c, anchor: g.frame(c, window: model.gridWindow))
                return
            }
            if dragged {
                if let d = dropped { model.dropClip(from: c, to: d) }
                return
            }
        }
        if hypot(dx, dy) > 12 { return }
        tap(p.hit)
    }

    private func tap(_ hit: GridHit) {
        switch hit {
        case .cell(let c): model.tapCell(c.track, c.row)
        case .scene(let k): model.queueScene(k)
        case .plus: model.addRow()
        case .none: break
        }
    }
}

/// Куда попало касание.
enum GridHit: Equatable {
    case cell(CellRef)
    case scene(Int)
    case plus
    case none
}

struct GridPress {
    let hit: GridHit
    let t0: Date
    var cell: CellRef? = nil
    var moved: Bool = false
    var held: Bool = false
}

/// Геометрия сетки: те же столбцы, что у строки дорожек (MIX и MST — шириной шага, зазор 6), 8 строк с зазором 4.
struct GridGeometry {
    let size: CGSize
    let step: CGFloat
    let tracks: Int

    var sceneW: CGFloat { return step }
    var trackW: CGFloat {
        let area: CGFloat = size.width - 2 * step - 2 * Layout.gap
        return (area - CGFloat(max(0, tracks - 1)) * Layout.gap) / CGFloat(max(1, tracks))
    }
    var rowH: CGFloat {
        return (size.height - CGFloat(Params.gridRows - 1) * PatternGrid.rowGap) / CGFloat(Params.gridRows)
    }

    /// Левый верхний угол ячейки: col −1 — колонка строк, 0…N−1 — дорожки.
    func origin(col: Int, row: Int) -> CGSize {
        let y: CGFloat = CGFloat(row) * (rowH + PatternGrid.rowGap)
        if col < 0 { return CGSize(width: 0, height: y) }
        let x: CGFloat = step + Layout.gap + CGFloat(col) * (trackW + Layout.gap)
        return CGSize(width: x, height: y)
    }

    func frame(_ c: CellRef, window: (rows: [Int?], plusRow: Int?, top: Int, maxTop: Int)) -> CGRect {
        let r: Int = window.rows.firstIndex(where: { $0 == c.row }) ?? 0
        let o = origin(col: c.track, row: r)
        return CGRect(x: o.width, y: o.height, width: trackW, height: rowH)
    }

    func hit(_ p: CGPoint, window: (rows: [Int?], plusRow: Int?, top: Int, maxTop: Int)) -> GridHit {
        let r: Int = Int(p.y / (rowH + PatternGrid.rowGap))
        guard r >= 0 && r < Params.gridRows else { return .none }
        if p.x < step {
            if let k = window.rows[r] { return .scene(k) }
            return window.plusRow == r ? .plus : .none
        }
        guard let k = window.rows[r] else { return .none }
        let x: CGFloat = p.x - step - Layout.gap
        let i: Int = Int(x / (trackW + Layout.gap))
        guard x >= 0 && i >= 0 && i < tracks else { return .none }
        return .cell(CellRef(track: i, row: k))
    }
}

/// Колонка над MST: бутерброд сетки, LOOP ROW, стрелки ▲ ▼ окна строк (если строк больше, чем видно).
struct GridSideButtons: View {
    let model: AppModel
    let scroll: Bool
    let canUp: Bool
    let canDown: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let h: CGFloat = (geo.size.height - 7 * PatternGrid.rowGap) / 8
            VStack(spacing: PatternGrid.rowGap) {
                BurgerButton { model.gridMenuOpen = true }.frame(height: h)
                loopButton.frame(height: h)
                if scroll {
                    arrow("▲", enabled: canUp || (model.project.arrowSwitch && model.playing)) { model.gridArrow(-1) }.frame(height: h)
                    arrow("▼", enabled: canDown || (model.project.arrowSwitch && model.playing)) { model.gridArrow(1) }.frame(height: h)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var loopButton: some View {
        let on: Bool = model.project.rowLoop
        return Image(systemName: "repeat")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(on ? theme.onAccent : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.accent : theme.panel2, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleRowLoop() }
    }

    private func arrow(_ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Text(title).font(.system(size: 16)).foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel2, in: RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
