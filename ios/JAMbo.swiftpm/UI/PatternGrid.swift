import SwiftUI

/// Сетка паттернов (PATTERNS): колонка строк над MIX, столбцы дорожек ровно над дорожками, справа (над MST) —
/// бутерброд сетки, LOOP ROW и стрелки окна строк. На экране 8 строк. Жесты — на всю сетку, у каждого пальца своё
/// касание (тапы по нескольким ячейкам сразу — запуск и остановка вместе); перетаскивается один клип или одна строка.
/// Ячейка: свайп вверх — меню, удержание (0,5 с) и перенос — копия клипа в другую ячейку, свайп вниз — ничего.
/// Строка: быстрый свайп вверх — меню строки, удержание и перенос — строка на другое место, остальное движение
/// пальцем вверх-вниз — прокрутка окна строк.
struct PatternGrid: View {
    let model: AppModel
    let layout: Layout
    @State private var presses: [SpatialEventCollection.Event.ID: GridPress] = [:]
    /// Палец, который тянет клип (копия под пальцем — ghost, ячейка под ним — target).
    @State private var dragId: SpatialEventCollection.Event.ID? = nil
    @State private var ghost: CGPoint? = nil
    @State private var target: CellRef? = nil
    /// Перетаскиваемая строка — строка окна под пальцем, куда она встанет.
    @State private var rowTarget: Int? = nil

    static let rowGap: CGFloat = 4
    static let hold: Double = 0.5
    /// Свайп вверх по строке — не дольше этого (дольше — прокрутка).
    static let flick: Double = 0.28

    var body: some View {
        GeometryReader { geo in
            let g = GridGeometry(size: geo.size, step: layout.step, tracks: model.project.tracks.count)
            let w = model.gridWindow
            ZStack(alignment: .topLeading) {
                // Жест сетки — только на ячейках (колонка строк и дорожки); кнопки справа и меню — свои касания.
                ZStack(alignment: .topLeading) {
                    cells(g)
                    ghostView(g)
                }
                .frame(width: g.size.width - g.sceneW - Layout.gap, height: g.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(touch(g))
                GridSideButtons(model: model, scroll: w.maxTop > 0, canUp: w.top > 0, canDown: w.top < w.maxTop)
                    .frame(width: g.sceneW, height: g.size.height)
                    .offset(x: g.size.width - g.sceneW)
                PatternMenus(model: model, geometry: g)
            }
        }
    }

    @ViewBuilder
    private func cells(_ g: GridGeometry) -> some View {
        let w = model.gridWindow
        ForEach(0..<Params.gridRows, id: \.self) { r in
            if let k = w.rows[r] {
                SceneCellView(model: model, row: k, target: rowTarget == k && dragRow != k).frame(width: g.sceneW, height: g.rowH)
                    .opacity(dragRow == k && ghost != nil ? 0.35 : 1)
                    .midiMarks(model, [.button("ROW \(r + 1)")])
                    .offset(g.origin(col: -1, row: r))
                ForEach(0..<g.tracks, id: \.self) { i in
                    ClipCellView(model: model, cell: CellRef(track: i, row: k), lifted: dragCell == CellRef(track: i, row: k) && ghost != nil,
                                 target: target == CellRef(track: i, row: k))
                        .frame(width: g.trackW, height: g.rowH)
                        .midiMarks(model, [.button(MidiButtons.clip(i, r))])
                        .offset(g.origin(col: i, row: r))
                        .offset(y: dropLift(g, track: i, row: k))
                        .animation(.easeInOut(duration: 0.45), value: model.mixDropDone)
                }
            } else if w.plusRow == r {
                PlusCell().frame(width: g.sceneW, height: g.rowH).offset(g.origin(col: -1, row: r))
            }
        }
    }

    /// MIX: клип PREV сначала стоит на строке, откуда опустился, затем съезжает вниз.
    private func dropLift(_ g: GridGeometry, track i: Int, row k: Int) -> CGFloat {
        guard model.isPrev(k), !model.mixDropDone, let from = model.mixDrop[i] else { return 0 }
        let rows: CGFloat = CGFloat(from - (Params.gridRows - 1))
        return rows * (g.rowH + PatternGrid.rowGap)
    }

    @ViewBuilder
    private func ghostView(_ g: GridGeometry) -> some View {
        if let p = ghost, let k = dragRow {
            SceneCellView(model: model, row: k, target: false)
                .frame(width: g.sceneW, height: g.rowH)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.5), radius: 10)
                .offset(x: 0, y: p.y - g.rowH / 2)
                .allowsHitTesting(false)
        } else if let p = ghost, let c = dragCell {
            ClipCellView(model: model, cell: c, lifted: false, target: false)
                .frame(width: g.trackW, height: g.rowH)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.5), radius: 10)
                .offset(x: p.x - g.trackW / 2, y: p.y - g.rowH / 2)
                .allowsHitTesting(false)
        }
    }

    // MARK: — жесты

    private var dragCell: CellRef? {
        guard let id = dragId else { return nil }
        return presses[id]?.cell
    }

    /// Строка, которую тянет палец.
    private var dragRow: Int? {
        guard let id = dragId, let p = presses[id], case .scene(let k) = p.hit else { return nil }
        return k
    }

    private func touch(_ g: GridGeometry) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    switch e.phase {
                    case .active:
                        if presses[e.id] == nil { begin(g, e.id, at: e.location) } else { move(g, e.id, e.location) }
                    case .ended:
                        end(g, e.id, e.location, cancelled: false)
                    case .cancelled:
                        end(g, e.id, e.location, cancelled: true)
                    @unknown default:
                        break
                    }
                }
            }
            .onEnded { events in
                for e in events { end(g, e.id, e.location, cancelled: e.phase == .cancelled) }
            }
    }

    private func begin(_ g: GridGeometry, _ id: SpatialEventCollection.Event.ID, at p: CGPoint) {
        model.ensureAudio()
        let hit = g.hit(p, window: model.gridWindow)
        // MIDI LEARN: тап выбирает ячейку или строку (по месту в окне строк) целью.
        if model.midiLearn.on {
            if let t = learnTarget(hit) { model.learnTap(t) }
            return
        }
        var gp = GridPress(hit: hit, t0: Date(), start: p)
        if case .cell(let c) = hit { gp.cell = c }
        gp.top0 = model.gridWindow.top
        presses[id] = gp
        let started = gp.t0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(PatternGrid.hold * 1e9))
            guard var cur = presses[id], cur.t0 == started, !cur.moved, dragId != id else { return }
            cur.held = true
            presses[id] = cur
            switch cur.hit {
            case .cell(let c): model.holdCell(c.track, c.row)
            // Строка: удержание поднимает её для переноса (меню — свайпом вверх).
            case .scene(let k):
                if !model.isPrev(k) && dragId == nil {
                    dragId = id
                    ghost = cur.start
                    rowTarget = k
                }
            default: break
            }
        }
    }

    private func move(_ g: GridGeometry, _ id: SpatialEventCollection.Event.ID, _ loc: CGPoint) {
        guard var p = presses[id] else { return }
        let dx: CGFloat = loc.x - p.start.x
        let dy: CGFloat = loc.y - p.start.y
        if hypot(dx, dy) > 8 { p.moved = true }
        presses[id] = p
        // Строка тянется только после удержания (палец замер на 0,5 с); строки между ней и пальцем — цель.
        if p.cell == nil {
            if dragId == id {
                ghost = CGPoint(x: g.sceneW / 2, y: loc.y)
                rowTarget = rowUnder(g, loc.y)
                return
            }
            if p.held || p.flicked { return }
            // Быстрый свайп вверх — меню строки; медленнее или вниз — прокрутка окна строк.
            let early: Bool = Date().timeIntervalSince(p.t0) < PatternGrid.flick
            if !p.scrolling && early && -dy > 24 && abs(dx) < -dy {
                p.flicked = true
                presses[id] = p
                if case .scene(let k) = p.hit, !model.isPrev(k) { model.rowMenu = k }
                return
            }
            if !p.scrolling && p.moved && abs(dy) > abs(dx) && !(early && dy < 0) { p.scrolling = true }
            if p.scrolling {
                presses[id] = p
                let pitch: CGFloat = g.rowH + PatternGrid.rowGap
                let rows: Int = Int((-dy / pitch).rounded())
                let w = model.gridWindow
                let top: Int = min(w.maxTop, max(0, p.top0 + rows))
                if top != w.top { model.gridTop = top }
            }
            return
        }
        // Клип тянется только после удержания (ячейка уже выбрана для правки); свайп без удержания клип не трогает.
        guard p.held, let c = p.cell, model.project.tracks[c.track].clipFilled(c.row) else { return }
        if let d = dragId, d != id { return }
        if dragId == nil && hypot(dx, dy) <= 8 { return }
        dragId = id
        ghost = loc
        if case .cell(let t) = g.hit(loc, window: model.gridWindow), t != c { target = t } else { target = nil }
    }

    private func end(_ g: GridGeometry, _ id: SpatialEventCollection.Event.ID, _ loc: CGPoint, cancelled: Bool) {
        guard let p = presses.removeValue(forKey: id) else { return }
        var dropped: CellRef? = nil
        var droppedRow: Int? = nil
        if dragId == id {
            dropped = target
            droppedRow = rowTarget
            dragId = nil
            ghost = nil
            target = nil
            rowTarget = nil
        }
        if cancelled || p.scrolling || p.flicked { return }
        if p.held {
            if let c = p.cell, let d = dropped { model.dropClip(from: c, to: d) }
            if case .scene(let k) = p.hit, let r = droppedRow { model.moveRow(k, to: r) }
            return
        }
        let dx: CGFloat = loc.x - p.start.x
        let dy: CGFloat = loc.y - p.start.y
        // Свайп вверх по ячейке — меню ячейки; свайп вниз — ничего.
        if let c = p.cell, -dy > 24 && abs(dx) < -dy {
            model.cellMenu = CellMenuState(cell: c, anchor: g.frame(c, window: model.gridWindow))
            return
        }
        if hypot(dx, dy) > 12 { return }
        tap(p.hit)
    }

    /// Строка проекта под пальцем (по высоте), куда встанет перетаскиваемая строка: только видимые строки, без PREV.
    private func rowUnder(_ g: GridGeometry, _ y: CGFloat) -> Int? {
        let pitch: CGFloat = g.rowH + PatternGrid.rowGap
        let r: Int = min(Params.gridRows - 1, max(0, Int(y / pitch)))
        guard let k = model.gridWindow.rows[r], !model.isPrev(k), k < model.project.visibleRows else { return nil }
        return k
    }

    /// Цель MIDI под пальцем: ячейка «CLIP t.r» или строка «ROW r» (r — место в окне строк 1–8).
    private func learnTarget(_ hit: GridHit) -> MidiTarget? {
        let rows: [Int?] = model.gridWindow.rows
        switch hit {
        case .cell(let c):
            guard let r = rows.firstIndex(of: c.row) else { return nil }
            return .button(MidiButtons.clip(c.track, r))
        case .scene(let k):
            guard let r = rows.firstIndex(of: k) else { return nil }
            return .button("ROW \(r + 1)")
        default:
            return nil
        }
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
    /// Точка начала касания (новое касание — другая точка).
    let start: CGPoint
    var cell: CellRef? = nil
    var moved: Bool = false
    var held: Bool = false
    /// Колонка строк: окно на старте, идёт ли прокрутка, открыто ли меню свайпом вверх.
    var top0: Int = 0
    var scrolling: Bool = false
    var flicked: Bool = false
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

/// Колонка над MST: бутерброд сетки, LOOP ROW, стрелки ▲ ▼ окна строк (если строк больше, чем видно). При переходе
/// MIX (CROSSFADER ON) бутерброда и LOOP ROW нет — стрелки сверху, под ними кроссфейдер до низа сетки.
struct GridSideButtons: View {
    let model: AppModel
    let scroll: Bool
    let canUp: Bool
    let canDown: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let h: CGFloat = (geo.size.height - 7 * PatternGrid.rowGap) / 8
            let fader: Bool = model.mix != nil && model.settings.mixCrossfader
            VStack(spacing: PatternGrid.rowGap) {
                if !fader {
                    BurgerButton { model.gridMenuOpen = true }.frame(height: h)
                    loopButton.frame(height: h)
                }
                if scroll {
                    arrow("▲", enabled: canUp || (model.project.arrowSwitch && model.playing)) { model.gridArrow(-1) }.frame(height: h).midiTarget(model, "GRID ▲")
                    arrow("▼", enabled: canDown || (model.project.arrowSwitch && model.playing)) { model.gridArrow(1) }.frame(height: h).midiTarget(model, "GRID ▼")
                }
                if fader {
                    MixFader(model: model).frame(maxHeight: .infinity).midiTarget(model, MidiButtons.xfader)
                } else {
                    Spacer(minLength: 0)
                }
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

/// Кроссфейдер перехода MIX: вертикальный, без надписей; внизу — общие настройки старого проекта, вверху — нового.
struct MixFader: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    static let thumbH: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let h: CGFloat = geo.size.height
            let pos: CGFloat = CGFloat(model.mix?.pos ?? 0)
            let travel: CGFloat = max(1, h - MixFader.thumbH)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6).fill(theme.panel2)
                Capsule().fill(theme.dim.opacity(0.5)).frame(width: 3).padding(.vertical, MixFader.thumbH / 2)
                RoundedRectangle(cornerRadius: 5).fill(theme.accent)
                    .frame(height: MixFader.thumbH)
                    .padding(.horizontal, 4)
                    .offset(y: (1 - pos) * travel)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let y: CGFloat = v.location.y - MixFader.thumbH / 2
                let p: CGFloat = 1 - y / travel
                model.setCrossfade(Double(min(1, max(0, p))))
            })
        }
    }
}
