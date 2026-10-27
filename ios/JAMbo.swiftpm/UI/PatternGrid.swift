import SwiftUI

/// Сетка паттернов (PATTERNS): колонка строк над MIX, столбцы дорожек ровно над дорожками, справа (над MST) —
/// бутерброд сетки, LOOP ROW и стрелки окна строк. На экране 8 строк. Жесты — на всю сетку, у каждого пальца своё
/// касание (тапы по нескольким ячейкам сразу — запуск и остановка вместе); перетаскивается один клип или одна строка.
/// Ячейка: свайп вверх — меню, удержание (0,35 с) и перенос — копия клипа в другую ячейку (на кнопку ARRANGE — в
/// аранжировку, AppModelCarry), свайп вниз — ничего. Свободное место (пустые строки внизу, колонка под кнопками справа):
/// сдвиг пальца (или удержание и протяжка) — рамка выделения (клипы и строки, которых она касается; для TO ARRANGE).
/// Строка: двойной тап — меню строки, удержание и перенос — строка целиком (колонка строк и клипы) едет за
/// пальцем, строки между ней и пальцем плавно сдвигаются; движение пальцем вверх-вниз — прокрутка окна строк.
struct PatternGrid: View {
    let model: AppModel
    let layout: Layout
    @Environment(\.theme) private var theme
    @State private var presses: [SpatialEventCollection.Event.ID: GridPress] = [:]
    /// Палец, который тянет клип (копия под пальцем — ghost, ячейка под ним — target).
    @State private var dragId: SpatialEventCollection.Event.ID? = nil
    @State private var ghost: CGPoint? = nil
    @State private var target: CellRef? = nil
    /// Перетаскиваемая строка — строка окна под пальцем, куда она встанет.
    @State private var rowTarget: Int? = nil
    /// Рамка выделения: палец и прямоугольник от точки касания.
    @State private var bandId: SpatialEventCollection.Event.ID? = nil
    @State private var band: CGRect? = nil
    /// Начало рамки — в координатах всех строк (y от первой строки проекта: рамка держится при прокрутке окна строк)
    /// и последняя точка пальца (автопрокрутка у края).
    @State private var bandAnchor: CGPoint = .zero
    @State private var bandLoc: CGPoint = .zero
    /// Последний тап по строке — для двойного тапа (меню строки).
    @State private var sceneTap: (row: Int, at: Date)? = nil
    /// Левый верхний угол сетки в координатах «root» (перенос клипа на ARRANGE).
    @State private var rootOrigin: CGPoint = .zero

    static let rowGap: CGFloat = 4
    static let hold: Double = 0.35
    /// Двойной тап по строке — второй тап не позже этого.
    static let doubleTap: Double = 0.3

    var body: some View {
        let _ = RedrawMeter.hit(.patterns)
        GeometryReader { geo in
            let g = GridGeometry(size: geo.size, step: layout.step, tracks: model.project.tracks.count, rows: model.gridRowsShown)
            let w = model.gridWindow
            ZStack(alignment: .topLeading) {
                // Жест сетки — только на ячейках (колонка строк и дорожки); кнопки справа и меню — свои касания.
                ZStack(alignment: .topLeading) {
                    cells(g)
                    ghostView(g)
                    bandView
                }
                .frame(width: g.size.width - g.sceneW - Layout.gap, height: g.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(touch(g))
                GridSideButtons(model: model, rows: g.rows, scroll: w.maxTop > 0, canUp: w.top > 0, canDown: w.top < w.maxTop)
                    .frame(width: g.sceneW, height: g.size.height)
                    .offset(x: g.size.width - g.sceneW)
                freeSide(g)
                PatternMenus(model: model, geometry: g)
            }
            .coordinateSpace(name: PatternGrid.space)
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named("root")).origin } action: { rootOrigin = $0 }
        }
    }

    static let space: String = "patternGrid"

    /// Свободное место колонки справа (под кнопками): касания — те же, что у сетки (рамка выделения).
    @ViewBuilder
    private func freeSide(_ g: GridGeometry) -> some View {
        let w = model.gridWindow
        let fader: Bool = model.mix != nil && model.settings.mixCrossfader
        let n: Int = (fader ? 0 : 4) + (w.maxTop > 0 ? 2 : 0)
        let h: CGFloat = g.rowH
        let top: CGFloat = CGFloat(n) * (h + PatternGrid.rowGap)
        if !fader && top < g.size.height {
            Color.clear
                .frame(width: g.sceneW, height: g.size.height - top)
                .contentShape(Rectangle())
                .gesture(touch(g))
                .offset(x: g.size.width - g.sceneW, y: top)
        }
    }

    @ViewBuilder
    private func cells(_ g: GridGeometry) -> some View {
        let w = model.gridWindow
        let group: Bool = groupLifted
        ForEach(0..<g.rows, id: \.self) { r in
            if let k = w.rows[r] {
                let lifted: Bool = dragRow == k && ghost != nil
                SceneCellView(model: model, row: k, selected: model.gridSel.rows.contains(k)).frame(width: g.sceneW, height: g.rowH)
                    .opacity(lifted ? 0 : 1)
                    .midiMarks(model, [.button("ROW \(r + 1)")])
                    .offset(g.origin(col: -1, row: r))
                    .offset(y: rowShift(g, k))
                    .animation(.easeInOut(duration: 0.2), value: rowTarget)
                ForEach(0..<g.tracks, id: \.self) { i in
                    ClipCellView(model: model, cell: CellRef(track: i, row: k), lifted: isLifted(CellRef(track: i, row: k), group),
                                 target: target == CellRef(track: i, row: k), selected: model.gridSel.contains(CellRef(track: i, row: k)))
                        .frame(width: g.trackW, height: g.rowH)
                        .midiMarks(model, [.button(MidiButtons.clip(i, r))])
                        .offset(g.origin(col: i, row: r))
                        .offset(y: dropLift(g, track: i, row: k))
                        .animation(.easeInOut(duration: 0.45), value: model.mixDropDone)
                        .opacity(lifted ? 0 : 1)
                        .offset(y: rowShift(g, k))
                        .animation(.easeInOut(duration: 0.2), value: rowTarget)
                }
            } else if w.plusRow == r {
                PlusCell().frame(width: g.sceneW, height: g.rowH).offset(g.origin(col: -1, row: r))
            }
        }
    }

    /// Перенос строки: строки между поднятой и местом под пальцем сдвигаются на её место (на строку вверх или вниз).
    private func rowShift(_ g: GridGeometry, _ k: Int) -> CGFloat {
        guard let a = dragRow, let b = rowTarget, a != b, k != a else { return 0 }
        let pitch: CGFloat = g.rowH + PatternGrid.rowGap
        if a < b && k > a && k <= b { return -pitch }
        if b < a && k >= b && k < a { return pitch }
        return 0
    }

    /// MIX: клип PREV сначала стоит на строке, откуда опустился, затем съезжает вниз.
    private func dropLift(_ g: GridGeometry, track i: Int, row k: Int) -> CGFloat {
        guard model.isPrev(k), !model.mixDropDone, let from = model.mixDrop[i] else { return 0 }
        let rows: CGFloat = CGFloat(from - (g.rows - 1))
        return rows * (g.rowH + PatternGrid.rowGap)
    }

    /// Подняты все клипы выделения рамкой (палец держит один из них).
    private var groupLifted: Bool {
        guard ghost != nil, let c = dragCell else { return false }
        return model.carryGroup(c) != nil
    }

    private func isLifted(_ c: CellRef, _ group: Bool) -> Bool {
        if ghost == nil { return false }
        if group { return model.gridSel.contains(c) }
        return dragCell == c
    }

    /// Выделение рамкой под пальцем: копии видимых выделенных клипов — на своих местах со сдвигом пальца.
    private func groupGhost(_ g: GridGeometry, _ p: CGPoint) -> some View {
        let w = model.gridWindow
        let start: CGPoint = dragId.flatMap { presses[$0]?.start } ?? p
        let dx: CGFloat = p.x - start.x
        let dy: CGFloat = p.y - start.y
        var list: [(cell: CellRef, at: CGSize)] = []
        for (r, row) in w.rows.enumerated() {
            guard let k = row else { continue }
            for i in 0..<g.tracks where model.gridSel.contains(CellRef(track: i, row: k)) {
                if model.project.tracks[i].clipFilled(k) { list.append((CellRef(track: i, row: k), g.origin(col: i, row: r))) }
            }
        }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<list.count, id: \.self) { n in
                ClipCellView(model: model, cell: list[n].cell, lifted: false, target: false)
                    .frame(width: g.trackW, height: g.rowH)
                    .scaleEffect(1.06)
                    .offset(x: list[n].at.width + dx, y: list[n].at.height + dy)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 10)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ghostView(_ g: GridGeometry) -> some View {
        if let p = ghost, groupLifted {
            groupGhost(g, p)
        } else if let p = ghost, let k = dragRow {
            // Строка целиком: колонка строк и клипы всех дорожек.
            ZStack(alignment: .topLeading) {
                SceneCellView(model: model, row: k).frame(width: g.sceneW, height: g.rowH)
                ForEach(0..<g.tracks, id: \.self) { i in
                    ClipCellView(model: model, cell: CellRef(track: i, row: k), lifted: false, target: false)
                        .frame(width: g.trackW, height: g.rowH)
                        .offset(x: g.origin(col: i, row: 0).width)
                }
            }
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

    /// Рамка выделения: бледная заливка и пунктир цветом текста (как в аранжировщике).
    @ViewBuilder
    private var bandView: some View {
        if let r = band {
            Rectangle().fill(theme.text.opacity(0.08))
                .overlay(Rectangle().stroke(theme.text.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
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
        SpatialEventGesture(coordinateSpace: .named(PatternGrid.space))
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
            case .cell(let c):
                model.holdCell(c.track, c.row)
                // Клип выделения рамкой: удержание поднимает все выделенные (как один клип при переносе).
                if dragId == nil && model.carryGroup(c) != nil {
                    withAnimation(.easeOut(duration: 0.15)) {
                        dragId = id
                        ghost = cur.start
                    }
                }
            // Свободное место: удержание — рамка выделения от точки касания.
            case .none:
                if bandId == nil {
                    let pitch: CGFloat = g.rowH + PatternGrid.rowGap
                    bandId = id
                    bandAnchor = CGPoint(x: cur.start.x, y: cur.start.y + CGFloat(model.gridWindow.top) * pitch)
                    band = CGRect(origin: cur.start, size: .zero)
                    bandLoc = cur.start
                    model.gridSel = GridSelection()
                    autoScroll(g, id)
                }
            // Строка: удержание поднимает её для переноса (меню — двойным тапом).
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
        if bandId == id {
            stretchBand(g, to: loc)
            return
        }
        // Свободное место: сдвиг пальца — сразу рамка (удерживать не нужно).
        if p.hit == .none && bandId == nil && p.moved && dragId == nil {
            let pitch: CGFloat = g.rowH + PatternGrid.rowGap
            bandId = id
            bandAnchor = CGPoint(x: p.start.x, y: p.start.y + CGFloat(model.gridWindow.top) * pitch)
            bandLoc = p.start
            model.gridSel = GridSelection()
            autoScroll(g, id)
            stretchBand(g, to: loc)
            return
        }
        // Строка тянется только после удержания (палец замер на 0,5 с); строки между ней и пальцем — цель.
        if p.cell == nil {
            if dragId == id {
                ghost = CGPoint(x: g.sceneW / 2, y: loc.y)
                rowTarget = rowUnder(g, loc.y)
                return
            }
            if p.held { return }
            // Движение пальцем вверх-вниз — прокрутка окна строк.
            if !p.scrolling && p.moved && abs(dy) > abs(dx) { p.scrolling = true }
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
        // Клип выделения рамкой несёт всё выделенное — только в аранжировку (в сетку не кладётся).
        let group: Bool = model.carryGroup(c) != nil
        if !group, case .cell(let t) = g.hit(loc, window: model.gridWindow), t != c { target = t } else { target = nil }
        // На кнопку ARRANGE — в аранжировку (клип PREV — нет).
        if !model.isPrev(c.row) { model.carryMove(c, root: CGPoint(x: loc.x + rootOrigin.x, y: loc.y + rootOrigin.y)) }
    }

    /// Рамка до пальца: выделены заполненные клипы, которых она касается, и строки, если задета колонка строк (по всем
    /// строкам проекта, в том числе ушедшим из окна при прокрутке).
    private func stretchBand(_ g: GridGeometry, to b: CGPoint) {
        bandLoc = b
        let pitch: CGFloat = g.rowH + PatternGrid.rowGap
        let shift: CGFloat = CGFloat(model.gridWindow.top) * pitch
        let a: CGPoint = bandAnchor
        let by: CGFloat = b.y + shift
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, by), width: abs(b.x - a.x), height: abs(by - a.y))
        // На экране — в пределах сетки.
        let seen: CGRect = r.offsetBy(dx: 0, dy: -shift).intersection(CGRect(origin: .zero, size: g.size))
        band = seen.isNull ? CGRect.zero : seen
        var sel = GridSelection()
        for k in 0..<model.project.visibleRows where !model.isPrev(k) {
            let y: CGFloat = CGFloat(k) * pitch
            if r.maxY < y || r.minY > y + g.rowH { continue }
            if r.minX <= g.sceneW { sel.rows.insert(k) }
            for t in 0..<g.tracks where model.project.tracks[t].clipFilled(k) {
                let x: CGFloat = g.origin(col: t, row: 0).width
                if r.maxX >= x && r.minX <= x + g.trackW { sel.cells.insert(CellRef(track: t, row: k)) }
            }
        }
        if sel != model.gridSel { model.gridSel = sel }
    }

    /// Рамка у верхнего или нижнего края сетки (полстроки) — окно строк прокручивается на строку каждые 0,25 с,
    /// если там есть ещё строки.
    private func autoScroll(_ g: GridGeometry, _ id: SpatialEventCollection.Event.ID) {
        Task { @MainActor in
            while bandId == id {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard bandId == id else { return }
                let w = model.gridWindow
                let edge: CGFloat = g.rowH / 2
                var top: Int = w.top
                if bandLoc.y < edge && top > 0 {
                    top -= 1
                } else if bandLoc.y > g.size.height - edge && top < w.maxTop {
                    top += 1
                }
                if top != w.top {
                    model.gridTop = top
                    stretchBand(g, to: bandLoc)
                }
            }
        }
    }

    private func end(_ g: GridGeometry, _ id: SpatialEventCollection.Event.ID, _ loc: CGPoint, cancelled: Bool) {
        guard let p = presses.removeValue(forKey: id) else { return }
        var dropped: CellRef? = nil
        var droppedRow: Int? = nil
        if bandId == id {
            bandId = nil
            band = nil
            return
        }
        // Конец переноса — без анимации: сдвинутые строки встают на новые места сразу, вместе с правкой проекта.
        var still = Transaction()
        still.disablesAnimations = true
        if dragId == id {
            // Клип унесли в аранжировщик — там и встаёт (или отмена), в сетку не кладётся.
            if model.carryEnd(cancelled: cancelled) { target = nil }
            dropped = target
            droppedRow = rowTarget
            withTransaction(still) {
                dragId = nil
                ghost = nil
                target = nil
                rowTarget = nil
            }
        }
        if cancelled || p.scrolling { return }
        if p.held {
            if let c = p.cell, let d = dropped { model.dropClip(from: c, to: d) }
            if case .scene(let k) = p.hit, let r = droppedRow {
                withTransaction(still) { model.moveRow(k, to: r) }
            }
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
        // Тап по клипу или свободному месту снимает выделение рамкой (по строке — нет: двойной тап открывает меню строки
        // для выделенного).
        if (p.cell != nil || p.hit == .none) && !model.gridSel.isEmpty { model.gridSel = GridSelection() }
        // Двойной тап по строке — меню строки (первый тап уже запустил строку; ожидающий запуск отменяется).
        if case .scene(let k) = p.hit, let last = sceneTap, last.row == k,
           Date().timeIntervalSince(last.at) < PatternGrid.doubleTap {
            sceneTap = nil
            if model.isPrev(k) { return }
            if model.playing && model.live.sceneQueued == k { model.queueScene(k) }
            model.rowMenu = k
            return
        }
        if case .scene(let k) = p.hit { sceneTap = (k, Date()) } else { sceneTap = nil }
        tap(p.hit)
    }

    /// Строка проекта под пальцем (по высоте), куда встанет перетаскиваемая строка: только видимые строки, без PREV.
    private func rowUnder(_ g: GridGeometry, _ y: CGFloat) -> Int? {
        let pitch: CGFloat = g.rowH + PatternGrid.rowGap
        let r: Int = min(g.rows - 1, max(0, Int(y / pitch)))
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
    /// Колонка строк: окно на старте, идёт ли прокрутка.
    var top0: Int = 0
    var scrolling: Bool = false
}

/// Геометрия сетки: те же столбцы, что у строки дорожек (MIX и MST — шириной шага, зазор 6), 8 строк с зазором 4.
struct GridGeometry {
    let size: CGSize
    let step: CGFloat
    let tracks: Int
    /// Строк в окне: 8; STEPS выключена — больше (той же высоты).
    var rows: Int = Params.gridRows

    /// Высота строки при n строках на высоту h (для раскладки экрана, RootView).
    static func rowH(_ h: CGFloat, rows n: Int) -> CGFloat {
        return (h - CGFloat(n - 1) * PatternGrid.rowGap) / CGFloat(max(1, n))
    }

    var sceneW: CGFloat { return step }
    var trackW: CGFloat {
        let area: CGFloat = size.width - 2 * step - 2 * Layout.gap
        return (area - CGFloat(max(0, tracks - 1)) * Layout.gap) / CGFloat(max(1, tracks))
    }
    var rowH: CGFloat {
        return GridGeometry.rowH(size.height, rows: rows)
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
        guard r >= 0 && r < rows else { return .none }
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

/// Колонка над MST: бутерброд сетки, LOOP ROW, STEPS (секвенсор и клавиатура), стрелки ▲ ▼ окна строк (если строк
/// больше, чем видно). При переходе MIX (CROSSFADER ON) бутерброда, LOOP ROW и STEPS нет — стрелки сверху, под ними
/// кроссфейдер до низа сетки.
struct GridSideButtons: View {
    let model: AppModel
    let rows: Int
    let scroll: Bool
    let canUp: Bool
    let canDown: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let h: CGFloat = GridGeometry.rowH(geo.size.height, rows: rows)
            let fader: Bool = model.mix != nil && model.settings.mixCrossfader
            VStack(spacing: PatternGrid.rowGap) {
                if !fader {
                    BurgerButton { model.gridMenuOpen = true }.frame(height: h)
                    loopButton.frame(height: h)
                    stepsButton.frame(height: h)
                    GridArrRecButton(model: model).frame(height: h)
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

    /// STEPS — значок и действие, как в строке кнопок аранжировщика: выключена — строка дорожек, секвенсор и клавиатура
    /// скрыты; горит, пока видны.
    private var stepsButton: some View {
        let on: Bool = !model.project.gridHideSteps
        return ArrStepsIcon(color: on ? theme.onAccent : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.accent : theme.panel2, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleGridSteps() }
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
