import SwiftUI

/// Окно аранжировщика (S15c, docs/ai/arranger.md): на месте центра. Слева заголовки дорожек, справа таймлайн:
/// линейка (номера тактов, планка петли), строка маркеров секций, строки дорожек с блоками, жёлтый курсор.
struct ArrangeWindow: View {
    let model: AppModel
    /// Поднятый блок (удержание и перетаскивание) — рисуется поверх таймлайна.
    @State private var lift: ArrLift? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = RedrawMeter.hit(.arrange)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Заголовки вплотную к таймлайну (решение пользователя: без зазора).
                HStack(spacing: 0) {
                    ArrHeaders(model: model).frame(width: ArrMetrics.headerW)
                    ArrTimeline(model: model, lift: $lift)
                    // Измеритель справа с регулятором — выбранной дорожки: на месте измерителя окна дорожки (RootView);
                    // пока его рамка неизвестна — здесь.
                    if model.meterFrame == .zero {
                        MeterColumn(model: model).padding(.leading, Layout.gap)
                    } else {
                        Color.clear.frame(width: Layout.meterWidth).padding(.leading, Layout.gap)
                    }
                }
                // Слева от линейки: время; при строке REF — A/B (S15g).
                HStack(spacing: 0) {
                    ArrTotalTime(model: model)
                    if model.arrRefShown { ArrABSwitch(model: model).padding(.vertical, 5).padding(.trailing, 6) }
                }
                .frame(width: ArrMetrics.headerW, height: ArrMetrics.top)
                ArrMenus(model: model, size: geo.size)
            }
        }
    }
}

/// Слева от линейки (решение пользователя): время плейхеда / длительность аранжировки (до конца последнего блока),
/// мин:сек; при игре — каждый кадр.
struct ArrTotalTime: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.playing)) { _ in
            let _ = RedrawMeter.hit(.arrPlay)
            let bpm: Double = max(20, model.project.bpm)
            // Шаг — шестнадцатая: 15 / BPM секунд.
            let now: String = ArrTotalTime.clock(model.arrNowX * 15 / bpm)
            let total: String = ArrTotalTime.clock(Double(model.project.arrangeEnd) * 15 / bpm)
            Text(now + " / " + total)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
    }

    static func clock(_ seconds: Double) -> String {
        let sec: Int = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

/// A/B (S15g): A — слышен проект, B — референс (мимо мастера; измеритель, LUFS и регулятор — референса); горит
/// выбранная буква, тап — другая.
struct ArrABSwitch: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let b: Bool = model.arrRefB
        return HStack(spacing: 0) {
            letter("A", !b)
            letter("B", b)
        }
        .frame(width: 60)
        .background(theme.panel2, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { model.toggleArrRefB() }
    }

    private func letter(_ s: String, _ on: Bool) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(on ? theme.bg : theme.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.text : Color.clear, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Плейхед поверх холста (решение пользователя: при игре едет плавно — позиция между шагами по времени, каждый кадр;
/// основной холст по шагам не перерисовывается).
struct ArrCursorLayer: View {
    let model: AppModel
    let m: ArrMetrics
    let head: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.playing)) { _ in
            let _ = RedrawMeter.hit(.arrPlay)
            let pos: Double = model.arrNowX
            Canvas { ctx, _ in
                ArrDraw(ctx: ctx, m: m, theme: theme).cursorLine(pos, head: head)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Поднятый блок: дорожка, номер, блок, где он сейчас (начало в шагах, дробное — за пальцем) и куда встанет.
struct ArrLift: Equatable {
    let track: Int
    let index: Int
    let block: ArrBlock
    var at: Double
    var target: Int
    /// Блок выделенной рамкой группы: переезжает вся группа на тот же сдвиг.
    var group: Bool = false
}

/// Размеры и прокрутка таймлайна (общие у рисования и касаний).
struct ArrMetrics {
    /// Заголовки дорожек — до левого края SCALE верхней панели (решение пользователя): левая колонка и зазор.
    static let headerW: CGFloat = Layout.leftColumn + Layout.gap
    static let rulerH: CGFloat = 20
    static let markerH: CGFloat = 18
    static let top: CGFloat = rulerH + markerH
    static let stepsPerBar: Int = ArrGrid.stepsPerBar

    let size: CGSize
    let stepW: CGFloat
    let x: CGFloat
    let y: CGFloat
    let rowH: CGFloat
    let tracks: Int
    /// Шагов, до которых можно прокрутить.
    let steps: Int

    /// SETTINGS → ARRANGE: COMPACT — строки делят высоту окна поровну (без прокрутки), EXPANDED — своя высота строк
    /// (масштаб двумя пальцами по вертикали) и прокрутка.
    let expanded: Bool
    /// Строка REF (S15g) — над дорожками, под линейкой (не прокручивается); дорожки — на строку ниже.
    let refRow: Bool
    /// inset — низ окна, закрытый окном AUTO (STEPS выключена): дорожки не сжимаются, прокрутка — до последней.
    init(size: CGSize, port: ArrPort, tracks: Int, end: Int, expanded: Bool, inset: CGFloat = 0, ref: Bool = false) {
        self.size = size
        self.tracks = tracks
        self.expanded = expanded
        refRow = ref
        let w: CGFloat = max(1, size.width)
        let fit: CGFloat = w / 256
        let want: CGFloat = port.stepW ?? fit
        stepW = ArrMetrics.clampStep(want, width: w)
        let area: CGFloat = max(0, size.height - ArrMetrics.top)
        let seen: CGFloat = max(0, area - inset)
        let n: CGFloat = CGFloat(max(1, tracks))
        let g: CGFloat = ArrMetrics.gap
        let r: CGFloat = ref ? 1 : 0
        let fitRow: CGFloat = (seen - (n + r - 1) * g) / (n + r)
        // Решения пользователя: строки дорожек — через чёрный зазор (как зазоры между окнами). EXPANDED — 8 строк и 7
        // зазоров на высоту окна (одна высота строки на весь экран: низ — 3 строки и 2 зазора, RootView), больше 8 дорожек
        // — прокрутка; COMPACT — все дорожки на видимую высоту окна. Масштаба по вертикали нет.
        rowH = expanded ? max(20, (area - 7 * g) / 8) : max(16, fitRow)
        steps = max(end, 0) + 32 * ArrMetrics.stepsPerBar
        let maxX: CGFloat = max(0, CGFloat(steps) * stepW - w)
        x = min(maxX, max(0, port.x))
        let maxY: CGFloat = max(0, n * (rowH + g) - g - (seen - r * (rowH + g)))
        y = min(maxY, max(0, port.y))
    }

    /// Масштаб по времени: от 64 до 4 тактов на ширину окна.
    static func clampStep(_ s: CGFloat, width: CGFloat) -> CGFloat {
        let lo: CGFloat = width / CGFloat(64 * stepsPerBar)
        let hi: CGFloat = width / CGFloat(4 * stepsPerBar)
        return min(hi, max(lo, s))
    }

    func stepX(_ s: Double) -> CGFloat {
        return CGFloat(s) * stepW - x
    }

    /// Зазор между строками дорожек — как между окнами (чёрная линия).
    static let gap: CGFloat = Layout.gap

    /// Шаг строк: строка и зазор.
    var pitch: CGFloat { return rowH + ArrMetrics.gap }

    /// Верх дорожек: под линейкой, при строке REF — под ней.
    var body: CGFloat { return ArrMetrics.top + (refRow ? pitch : 0) }

    /// Точка в строке REF.
    func inRef(_ py: CGFloat) -> Bool {
        return refRow && py >= ArrMetrics.top && py < ArrMetrics.top + rowH
    }

    func rowY(_ t: Int) -> CGFloat {
        return body + CGFloat(t) * pitch - y
    }

    /// Строка заголовка с верхом y принимает касания, только если верх не ушёл под линейку: маска прячет строку, но не
    /// касания — уехавшая вверх строка ловила тапы второй строки экрана (AUTO включал S дорожки).
    func tappable(_ top: CGFloat) -> Bool {
        return top >= body - 1 && top < size.height
    }

    /// Шаг под точкой (дробный).
    func step(at px: CGFloat) -> Double {
        return Double((px + x) / stepW)
    }

    /// Дорожка под точкой (−1 — не дорожка: линейка или ниже последней).
    func track(at py: CGFloat) -> Int {
        if py < body { return -1 }
        let cy: CGFloat = py - body + y
        let t: Int = Int((cy / pitch).rounded(.down))
        return t >= 0 && t < tracks ? t : -1
    }

    func rect(_ t: Int, _ b: ArrBlock) -> CGRect {
        return CGRect(x: stepX(Double(b.start)), y: rowY(t) + 1, width: max(2, CGFloat(b.length) * stepW), height: rowH - 2)
    }

    /// Шаг подписей тактов: не теснее ~36 pt.
    var barLabelEvery: Int {
        let barW: CGFloat = stepW * CGFloat(ArrMetrics.stepsPerBar)
        var n: Int = 1
        while CGFloat(n) * barW < 36 { n *= 2 }
        return n
    }
}

/// Таймлайн: Canvas и все касания одним жестом (ArrTouches).
struct ArrTimeline: View {
    let model: AppModel
    @Binding var lift: ArrLift?
    @State private var touches = ArrTouches()
    @Environment(\.theme) private var theme

    var body: some View {
        let p: Project = model.project
        let port: ArrPort = model.arrPort
        let sel: ArrSel? = model.arrSel
        let group: [ArrSel] = model.arrGroup.count >= 2 ? model.arrGroup : []
        let marquee: CGRect? = model.arrMarquee
        let selTrack: Int = model.channel == .track ? model.selectedTrack : -1
        let following: [Bool] = (0..<p.tracks.count).map { model.arrFollowing($0) }
        let wave: RefWave? = model.arrRefShown ? model.refWave : nil
        let waveKey: String = (p.arrange.ref?.key ?? "") + "#\(model.samplesVersion)"
        return GeometryReader { geo in
            let m = ArrMetrics(size: geo.size, port: port, tracks: p.tracks.count, end: p.arrangeEnd, expanded: model.settings.arrangeExpanded,
                           inset: model.arrInset, ref: model.arrRefShown)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    // Левые углы прямые (к заголовкам дорожек), правые скруглены — решение пользователя.
                    var c = ctx
                    c.clip(to: ArrTimeline.frameShape.path(in: CGRect(origin: .zero, size: size)))
                    ArrDraw(ctx: c, m: m, theme: theme).draw(p, sel: sel, lift: lift, following: following,
                                                            track: selTrack, group: group, marquee: marquee, wave: wave)
                }
                ArrCursorLayer(model: model, m: m, head: true)
                if let l = lift { liftedView(l, m, p) }
                if let c = model.clipCarry, c.overArrange { ArrCarryLayer(model: model, carry: c, m: m) }
            }
            .contentShape(Rectangle())
            .gesture(touch(geo.size))
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { model.arrTimelineFrame = $0 }
        .background(theme.panel)
        .clipShape(ArrTimeline.frameShape)
        .onAppear { model.ensureRefWave() }
        .onChange(of: waveKey) { _, _ in model.ensureRefWave() }
    }

    static let frameShape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                   bottomTrailingRadius: Layout.radius, topTrailingRadius: Layout.radius)

    /// Поднятый блок — над дорожкой, с тенью; при отпускании плавно встаёт на место (анимация позиции).
    private func liftedView(_ l: ArrLift, _ m: ArrMetrics, _ p: Project) -> some View {
        let w: CGFloat = max(2, CGFloat(l.block.length) * m.stepW)
        let h: CGFloat = m.rowH - 2
        let color: Color = l.track < p.tracks.count ? ArrColors.color(p.tracks[l.track].color) : ArrColors.color(0)
        let cx: CGFloat = m.stepX(l.at) + w / 2
        let cy: CGFloat = m.rowY(l.track) + 1 + h / 2
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.text, lineWidth: 1))
            .frame(width: w, height: h)
            .shadow(color: Color.black.opacity(0.5), radius: 8, y: 4)
            .position(x: cx, y: cy)
            .allowsHitTesting(false)
    }

    private func touch(_ size: CGSize) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { e in apply(e, size) }
            .onEnded { e in apply(e, size) }
    }

    private func apply(_ events: SpatialEventCollection, _ size: CGSize) {
        let p: Project = model.project
        let m = ArrMetrics(size: size, port: model.arrPort, tracks: p.tracks.count, end: p.arrangeEnd, expanded: model.settings.arrangeExpanded,
                           inset: model.arrInset, ref: model.arrRefShown)
        var port: ArrPort = model.arrPort
        touches.handle(events, port: &port, m, model, lift: $lift)
        let c = ArrMetrics(size: size, port: port, tracks: p.tracks.count, end: p.arrangeEnd, expanded: model.settings.arrangeExpanded,
                           inset: model.arrInset, ref: model.arrRefShown)
        let next = ArrPort(stepW: port.stepW == nil ? nil : c.stepW, x: c.x, y: c.y)
        if next != model.arrPort { model.arrPort = next }
    }
}

/// Рисование таймлайна.
struct ArrDraw {
    let ctx: GraphicsContext
    let m: ArrMetrics
    let theme: Theme

    func draw(_ p: Project, sel: ArrSel?, lift: ArrLift?, following: [Bool], track: Int, group: [ArrSel],
              marquee: CGRect?, wave: RefWave? = nil) {
        gridLines(p)
        lanes(p)
        for t in 0..<p.tracks.count {
            // Тускнеют блоки дорожки, которая играет сетку, и заглушённой.
            let on: Bool = t < following.count ? following[t] : true
            let heard: Bool = p.audible(t)
            let dim: Bool = !on || !heard
            blocks(p, t, sel: sel, group: group, lift: lift, dim: dim)
        }
        selectedLane(track)
        if let l = lift { target(l, p, group) }
        if let r = marquee { marqueeRect(r) }
        refRow(p, wave)
        ruler(p)
        markers(p)
    }

    private func lanes(_ p: Project) {
        for t in 0..<p.tracks.count {
            let y: CGFloat = m.rowY(t)
            if y > m.size.height || y + m.rowH < m.body { continue }
            // Зазор под строкой — цветом фона (чёрная линия, как между окнами).
            let r = CGRect(x: 0, y: y + m.rowH, width: m.size.width, height: ArrMetrics.gap)
            ctx.fill(Path(r), with: .color(theme.bg))
        }
    }

    /// Линии тактов (ярче) и сетки (с выбранным шагом сетки, если не слишком тесно).
    private func gridLines(_ p: Project) {
        let first: Int = max(0, Int(m.step(at: 0)))
        let last: Int = Int(m.step(at: m.size.width)) + 1
        let g: Int = p.arrange.gridSteps
        let fine: Bool = CGFloat(g) * m.stepW >= 8
        var s: Int = first - first % max(1, g)
        let h: CGFloat = m.size.height - ArrMetrics.top
        while s <= last {
            let bar: Bool = s % ArrMetrics.stepsPerBar == 0
            if bar || fine {
                let x: CGFloat = m.stepX(Double(s))
                let c: Color = bar ? theme.gridStrong : theme.grid
                if x >= 1 { ctx.fill(Path(CGRect(x: x, y: ArrMetrics.top, width: 1, height: h)), with: .color(c)) }
            }
            s += max(1, g)
        }
    }

    /// Выбранная дорожка (решение пользователя): две жёлтые линии по всей длине строки — сверху и снизу (продолжают
    /// линии заголовка).
    private func selectedLane(_ t: Int) {
        if t < 0 || t >= m.tracks { return }
        let y: CGFloat = m.rowY(t)
        if y > m.size.height || y + m.rowH < m.body { return }
        // Те же высоты, что у линий заголовка (края строки): одна линия.
        ctx.fill(Path(CGRect(x: 0, y: y, width: m.size.width, height: 1)), with: .color(theme.accent))
        ctx.fill(Path(CGRect(x: 0, y: y + m.rowH - 1, width: m.size.width, height: 1)), with: .color(theme.accent))
    }

    private func blocks(_ p: Project, _ t: Int, sel: ArrSel?, group: [ArrSel], lift: ArrLift?, dim: Bool) {
        let tr: Track = p.tracks[t]
        let y: CGFloat = m.rowY(t)
        if y > m.size.height || y + m.rowH < m.body { return }
        let color: Color = ArrColors.color(tr.color)
        for (i, b) in tr.blocks.enumerated() {
            if let l = lift, l.track == t, l.index == i { continue }
            let r: CGRect = m.rect(t, b)
            if r.maxX < 0 || r.minX > m.size.width { continue }
            let shape = Path(roundedRect: r, cornerRadius: 4)
            ctx.fill(shape, with: .color(color.opacity(dim ? 0.35 : 1)))
            let s = ArrSel(track: t, block: i)
            if sel == s || group.contains(s) { ctx.stroke(shape, with: .color(theme.text), lineWidth: 1) }
            pattern(tr, b, r)
        }
    }

    /// Паттерн клипа на блоке (решение пользователя: без цифр): триг в один шаг — квадратик, длинная нота — линия на всю
    /// её длину; клип — по кругу с места блока, как он звучит.
    private func pattern(_ tr: Track, _ b: ArrBlock, _ r: CGRect) {
        guard tr.clipFilled(b.clip), let c = tr.clips[b.clip] else { return }
        let first: Int = max(b.start, Int(m.step(at: 0)) - 16)
        let last: Int = min(b.end, Int(m.step(at: m.size.width)) + 1)
        if last <= first { return }
        let side: CGFloat = max(2, min(m.stepW * 0.7, r.height * 0.4))
        let y: CGFloat = r.midY - side / 2
        let len: Int = c.playLen
        var path = Path()
        var s: Int = first
        while s < last {
            let n: Int = c.localStep(s - b.start + b.offset)
            if n < len {
                let idx: Int = c.playIndex(n)
                if let st = c.step(idx), st.on, !c.outside(idx) {
                    let pad: CGFloat = max(0.5, (m.stepW - side) / 2)
                    let x: CGFloat = m.stepX(Double(s)) + pad
                    var w: CGFloat = side
                    if st.len >= 2 {
                        let full: CGFloat = CGFloat(st.len) * m.stepW
                        w = full - 2 * pad
                    }
                    path.addRect(CGRect(x: x, y: y, width: w, height: side))
                }
            }
            s += 1
        }
        var cc = ctx
        cc.clip(to: Path(r.insetBy(dx: 1, dy: 1)))
        cc.fill(path, with: .color(ArrColors.text.opacity(0.6)))
    }

    /// Куда встанет поднятый блок — контур.
    private func target(_ l: ArrLift, _ p: Project, _ group: [ArrSel]) {
        var list: [(track: Int, block: ArrBlock)] = [(l.track, l.block)]
        if l.group {
            list = []
            for s in group where s.track < p.tracks.count && s.block < p.tracks[s.track].blocks.count {
                list.append((s.track, p.tracks[s.track].blocks[s.block]))
            }
        }
        let d: Int = l.target - l.block.start
        for g in list {
            let b = ArrBlock(clip: g.block.clip, start: g.block.start + d, length: g.block.length)
            ctx.stroke(Path(roundedRect: m.rect(g.track, b), cornerRadius: 4), with: .color(theme.text.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// Рамка выделения: бледная заливка и белый пунктир.
    private func marqueeRect(_ r: CGRect) {
        ctx.fill(Path(r), with: .color(theme.text.opacity(0.08)))
        ctx.stroke(Path(r), with: .color(theme.text.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    /// Строка REF (S15g): над дорожками (уехавшие под неё — закрыты), волна референса по времени таймлайна (файл в
    /// своём темпе: место — секунды шага при текущем темпе минус сдвиг), зазор снизу.
    private func refRow(_ p: Project, _ wave: RefWave?) {
        guard m.refRow else { return }
        let y0: CGFloat = ArrMetrics.top
        let h: CGFloat = m.rowH
        ctx.fill(Path(CGRect(x: 0, y: y0, width: m.size.width, height: h + ArrMetrics.gap)), with: .color(theme.bg))
        ctx.fill(Path(CGRect(x: 0, y: y0, width: m.size.width, height: h)), with: .color(theme.trackBg))
        guard let w = wave, let r = p.arrange.ref, w.key == r.key, !w.peaks.isEmpty else { return }
        let rate: Double = AudioCore.sampleRate
        let sps: Double = 15 / max(20, p.bpm)
        let colW: CGFloat = 2
        let perCol: Double = Double(colW / m.stepW) * sps * rate
        let mid: CGFloat = y0 + h / 2
        let amp: CGFloat = h / 2 - 3
        let count: Int = w.peaks.count
        var path = Path()
        var px: CGFloat = 0
        while px < m.size.width {
            let f0: Double = (m.step(at: px) * sps - r.offset) * rate
            let f1: Double = f0 + perCol
            if f1 > 0 && f0 < Double(w.frames) {
                let a: Int = max(0, Int(f0) / RefWave.hop)
                let b: Int = min(count, Int(f1) / RefWave.hop + 1)
                var v: Float = 0
                var k: Int = a
                while k < b {
                    if w.peaks[k] > v { v = w.peaks[k] }
                    k += 1
                }
                let hh: CGFloat = max(0.5, CGFloat(min(1, v)) * amp)
                path.addRect(CGRect(x: px, y: mid - hh, width: colW - 0.5, height: hh * 2))
            }
            px += colW
        }
        ctx.fill(path, with: .color(theme.text.opacity(0.6)))
    }

    /// Линейка: номера тактов, планка петли (жёлтая; выключенная петля — бледная).
    private func ruler(_ p: Project) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: m.size.width, height: ArrMetrics.top)), with: .color(theme.panel2))
        // Выделенный диапазон (он же петля) — верхняя половина линейки залита жёлтым (петля включена — ярче).
        let a = p.arrange
        if a.hasLoop {
            let x0: CGFloat = m.stepX(Double(a.loopFrom))
            let x1: CGFloat = m.stepX(Double(a.loopTo))
            let r = CGRect(x: x0, y: 0, width: max(2, x1 - x0), height: ArrMetrics.rulerH)
            ctx.fill(Path(r), with: .color(theme.accent.opacity(a.loop ? 0.75 : 0.35)))
        }
        let loopOn: Bool = p.arrange.loop && p.arrange.hasLoop
        let every: Int = m.barLabelEvery
        let firstBar: Int = max(0, Int(m.step(at: 0)) / ArrMetrics.stepsPerBar)
        let lastBar: Int = Int(m.step(at: m.size.width)) / ArrMetrics.stepsPerBar + 1
        var bar: Int = firstBar - firstBar % every
        while bar <= lastBar {
            let x: CGFloat = m.stepX(Double(bar * ArrMetrics.stepsPerBar))
            // Черта такта у самого края не рисуется.
            if x >= 1 { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: ArrMetrics.rulerH)), with: .color(theme.gridStrong)) }
            // В выделенном диапазоне при включённой петле (яркая заливка) — номера тактов чёрные.
            let s: Int = bar * ArrMetrics.stepsPerBar
            let lit: Bool = loopOn && s >= p.arrange.loopFrom && s < p.arrange.loopTo
            let tc: Color = lit ? theme.onAccent : theme.dim
            let text = Text("\(bar + 1)").font(.system(size: 9)).monospacedDigit().foregroundStyle(tc)
            ctx.draw(text, at: CGPoint(x: x + 3, y: 3), anchor: .topLeading)
            bar += every
        }
        ctx.fill(Path(CGRect(x: 0, y: ArrMetrics.top - 1, width: m.size.width, height: 1)), with: .color(theme.line))
    }

    /// Строка маркеров (решения пользователя: секции без цвета): начало и конец секции — тонкие жёлтые линии во всю
    /// высоту строки, имя — по центру секции (последняя без конца — у начала).
    private func markers(_ p: Project) {
        let list: [ArrMarker] = p.arrange.markers
        let top: CGFloat = ArrMetrics.rulerH + 1
        let h: CGFloat = ArrMetrics.markerH - 2
        for (k, mk) in list.enumerated() {
            let x0: CGFloat = m.stepX(Double(mk.at))
            let end: Int? = p.sectionEnd(k)
            let x1: CGFloat = end.map { m.stepX(Double($0)) } ?? m.size.width
            if x1 < 0 || x0 > m.size.width { continue }
            ctx.fill(Path(CGRect(x: x0, y: top, width: 1, height: h)), with: .color(theme.accent))
            // Секции вплотную (решение пользователя): граница между ними — одна линия, как край секции (конец не рисуется,
            // его заменяет начало следующей).
            let touching: Bool = k + 1 < list.count && end != nil && end! >= list[k + 1].at
            if end != nil && !touching { ctx.fill(Path(CGRect(x: x1 - 1, y: top, width: 1, height: h)), with: .color(theme.accent)) }
            var c = ctx
            c.clip(to: Path(CGRect(x: x0 + 1, y: top, width: max(1, x1 - x0 - 2), height: h)))
            let text: Text = Text(mk.name.isEmpty ? " " : mk.name).font(.system(size: 9, weight: .bold)).foregroundStyle(theme.text)
            if end != nil {
                c.draw(text, at: CGPoint(x: (x0 + x1) / 2, y: top + h / 2), anchor: .center)
            } else {
                c.draw(text, at: CGPoint(x: max(x0, 0) + 5, y: top + h / 2), anchor: .leading)
            }
        }
    }

    /// Плейхед на позиции pos (шаги, дробная); head — пятиугольник над линией (на таймлайне).
    func cursorLine(_ pos: Double, head drawHead: Bool) {
        let x: CGFloat = m.stepX(pos)
        if x < -8 || x > m.size.width + 8 { return }
        ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: m.size.height)), with: .color(theme.accent))
        if !drawHead { return }
        // Маркер плейхеда — жёлтый пятиугольник остриём вниз во всю высоту линейки и строки секций (решение
        // пользователя).
        let w: CGFloat = 14
        let h: CGFloat = ArrMetrics.top
        let side: CGFloat = h - 9
        var head = Path()
        head.move(to: CGPoint(x: x - w / 2, y: 0))
        head.addLine(to: CGPoint(x: x + w / 2, y: 0))
        head.addLine(to: CGPoint(x: x + w / 2, y: side))
        head.addLine(to: CGPoint(x: x, y: h))
        head.addLine(to: CGPoint(x: x - w / 2, y: side))
        head.closeSubpath()
        ctx.fill(head, with: .color(theme.accent))
    }
}
