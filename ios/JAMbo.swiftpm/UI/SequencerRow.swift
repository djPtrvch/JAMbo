import SwiftUI

/// Шаги открытой страницы — или всех играющих (16 × N в один ряд, шаги уже). Тап — триг; нажатие и протягивание
/// вправо — длина ноты (через границы страниц); зажат шаг + тап по другому — копия шага; удержание первого шага +
/// двойной тап по другому — последний шаг паттерна (первый тап копирует, второй отменяет копию). Мультитач.
struct SequencerRow: View {
    let model: AppModel
    @State private var presses: [SpatialEventCollection.Event.ID: StepPress] = [:]
    @State private var lastTap: [Int: Date] = [:]
    /// Последняя копия шага: куда, что там было (для отмены двойным тапом).
    @State private var lastCopy: (index: Int, old: Step)? = nil

    var body: some View {
        RedrawMeter.hit(.seq)
        let pages: ClosedRange<Int> = model.viewPages
        let look: SeqLook = SeqLook(pages: pages.count)
        return GeometryReader { geo in
            HStack(spacing: look.pageGap) {
                ForEach(pages, id: \.self) { page in
                    HStack(spacing: look.gap) {
                        ForEach(0..<Params.stepsPerPage, id: \.self) { col in
                            StepCell(model: model, page: page, col: col, look: look)
                                .midiMarks(model, page == pages.lowerBound ? [.button("STEP \(col + 1)")] : [])
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(touches(width: geo.size.width, look: look, first: pages.lowerBound))
        }
        .frame(height: Layout.seqHeight)
    }

    private func touches(width: CGFloat, look: SeqLook, first: Int) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    handle(e, col: look.column(e.location.x, width: width), first: first)
                }
            }
            .onEnded { events in
                for e in events {
                    finish(e.id, cancelled: e.phase == .cancelled)
                }
            }
    }

    private func handle(_ e: SpatialEventCollection.Event, col: Int, first: Int) {
        switch e.phase {
        case .active:
            if let p = presses[e.id] {
                move(e.id, p, to: col)
            } else {
                down(e.id, col: col, first: first)
            }
        case .ended:
            finish(e.id, cancelled: false)
        case .cancelled:
            finish(e.id, cancelled: true)
        @unknown default:
            break
        }
    }

    /// col — номер шага в ряду (0 — первый шаг первой показанной страницы).
    private func down(_ id: SpatialEventCollection.Event.ID, col: Int, first: Int) {
        model.ensureAudio()
        // MIDI LEARN: тап выбирает шаг открытой страницы целью (STEP 1…16).
        if model.midiLearn.on {
            model.learnTap(.button("STEP \(col % Params.stepsPerPage + 1)"))
            return
        }
        let index: Int = first * Params.stepsPerPage + col
        let firstHeld: Bool = presses.values.contains { $0.col == 0 }
        let secondary: Bool = firstHeld && col != 0
        if secondary, let t = lastTap[col], Date().timeIntervalSince(t) < 0.35 {
            // Двойной тап: первый тап скопировал первый шаг — копия отменяется, шаг становится последним.
            if let c = lastCopy, c.index == index { model.restoreStep(index, c.old) }
            lastCopy = nil
            model.setPatternLength(lastIndex: index)
            for (k, v) in presses where v.col == 0 { presses[k]?.used = true }
            lastTap[col] = nil
        }
        presses[id] = StepPress(col: col, index: index, t0: Date(), secondary: secondary)
        model.heldSteps.insert(index)
        model.beginGesture()
    }

    /// Палец по шагам (SETTINGS → RECORD → STEP SWIPE): LENGTH — длинная нота от первого шага; PAINT — триг на
    /// каждом пройденном шаге (в обе стороны; пропущенные при быстром движении — тоже).
    private func move(_ id: SpatialEventCollection.Event.ID, _ p: StepPress, to col: Int) {
        if p.secondary { return }
        if col == p.col && !p.dragged { return }
        if model.settings.stepPaint {
            presses[id]?.dragged = true
            presses[id]?.used = true
            let base: Int = p.index - p.col
            model.paintSteps(base + min(p.col, col), base + max(p.col, col))
            return
        }
        if col < p.col { return }
        presses[id]?.dragged = true
        presses[id]?.used = true
        model.setNoteLength(p.index, col - p.col + 1)
    }

    private func finish(_ id: SpatialEventCollection.Event.ID, cancelled: Bool) {
        guard let p = presses.removeValue(forKey: id) else { return }
        let used: Bool = p.used || model.usedSteps.contains(p.index)
        if !presses.values.contains(where: { $0.index == p.index }) {
            model.heldSteps.remove(p.index)
            model.usedSteps.remove(p.index)
        }
        defer { model.endGesture() }
        if cancelled { return }
        let quick: Bool = Date().timeIntervalSince(p.t0) < 0.35
        if quick && !p.dragged { lastTap[p.col] = Date() }
        if !quick || p.dragged || used { return }
        // Зажат другой шаг (раньше нажатый) — копия его в этот.
        let source: (key: SpatialEventCollection.Event.ID, value: StepPress)? = presses
            .filter { $0.value.index != p.index && $0.value.t0 < p.t0 }
            .min { $0.value.t0 < $1.value.t0 }
        if let src = source {
            if let old = model.copyStep(from: src.value.index, to: p.index) { lastCopy = (p.index, old) }
            presses[src.key]?.used = true
            return
        }
        if !p.secondary { model.toggleStep(p.index) }
    }
}

/// Размеры ряда шагов по числу показанных страниц: зазоры между шагами и страницами, поля, надпись ноты.
struct SeqLook {
    let pages: Int
    let gap: CGFloat
    let pageGap: CGFloat
    let inset: CGFloat
    let dot: CGFloat
    /// Отступ точки p-lock от угла ячейки.
    let dotPad: CGFloat
    let showLabel: Bool

    init(pages n: Int) {
        pages = max(1, n)
        switch pages {
        case 1: gap = Layout.stepGap; pageGap = 0; inset = 5; dot = 6; dotPad = 10
        case 2: gap = 2; pageGap = 6; inset = 3; dot = 5; dotPad = 6
        case 3, 4: gap = 1; pageGap = 5; inset = 1; dot = 4; dotPad = 3
        default: gap = 1; pageGap = 3; inset = 1; dot = 3; dotPad = 2
        }
        showLabel = pages <= 2
    }

    /// Шаг в ряду под x (0 … 16·pages − 1).
    func column(_ x: CGFloat, width: CGFloat) -> Int {
        let per: Int = Params.stepsPerPage
        let pageW: CGFloat = (width - pageGap * CGFloat(pages - 1)) / CGFloat(pages)
        let p: Int = min(pages - 1, max(0, Int(x / (pageW + pageGap))))
        let x0: CGFloat = x - CGFloat(p) * (pageW + pageGap)
        let cell: CGFloat = (pageW + gap) / CGFloat(per)
        let c: Int = min(per - 1, max(0, Int(x0 / cell)))
        return p * per + c
    }
}

/// Нажатый шаг.
struct StepPress {
    let col: Int
    let index: Int
    let t0: Date
    let secondary: Bool
    var dragged: Bool = false
    /// Нажатие уже что-то сделало (протягивание, длина паттерна) — триг на отпускании не переключается.
    var used: Bool = false
}

/// Шаг: триг (белый), хвост длинной ноты (полупрозрачный), нота или POLY, играющий — жёлтый контур,
/// зажатый — белый контур, ручные p-lock — жёлтая точка в левом верхнем углу, свой звук шага — жёлтая обводка,
/// за длиной паттерна — бледный, последний — жёлтая черта справа.
struct StepCell: View {
    let model: AppModel
    let page: Int
    let col: Int
    let look: SeqLook
    @Environment(\.theme) private var theme

    var body: some View {
        let info: StepInfo = StepInfo(model: model, page: page, col: col)
        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: look.pages > 2 ? 2 : 4)
                .fill(info.fill(theme))
                .overlay(noteLabel(info))
                .padding(look.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(col % 4 == 0 ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: look.pages > 2 ? 3 : 6))
                .overlay(RoundedRectangle(cornerRadius: look.pages > 2 ? 3 : 6).stroke(info.outline(theme), lineWidth: 1))
                .overlay(alignment: .topLeading) { lockDot(info) }
            if info.last {
                Rectangle().fill(theme.accent).frame(width: 2).padding(.vertical, 6).offset(x: look.gap / 2 + 1)
            }
        }
        .opacity(info.outside ? 0.3 : 1)
    }

    @ViewBuilder
    private func noteLabel(_ info: StepInfo) -> some View {
        if look.showLabel {
            Text(info.label)
                .font(.system(size: look.pages > 1 ? 10 : 11, weight: .bold))
                .foregroundStyle(theme.bg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private func lockDot(_ info: StepInfo) -> some View {
        if info.manualLock {
            Circle().fill(theme.accent)
                .frame(width: look.dot, height: look.dot)
                .padding(look.dotPad)
        }
    }
}

/// Что показать на шаге (вынесено, чтобы тело вида было простым).
struct StepInfo {
    let on: Bool
    let tail: Bool
    let label: String
    let playing: Bool
    let held: Bool
    let outside: Bool
    let last: Bool
    let channelOn: Bool
    /// Ручные p-lock (на триге или пустом шаге) — жёлтая точка; свой звук шага — жёлтая обводка.
    let manualLock: Bool
    let ownSound: Bool

    init(model: AppModel, page: Int, col: Int) {
        let t: Track = model.seq
        let index: Int = page * Params.stepsPerPage + col
        let s: Step? = t.step(index)
        // Ноты — только у дорожки; у MIX и MST — p-lock, длина и ход.
        channelOn = model.channel == .track
        on = channelOn && (s?.on ?? false)
        var isTail = false
        if channelOn && !on {
            var k = index - 1
            while k >= 0 && k >= index - 128 {
                if let p = t.step(k), p.on {
                    isTail = p.len > index - k
                    break
                }
                k -= 1
            }
        }
        tail = isTail
        manualLock = s.map { Track.hasManualLocks($0) } ?? false
        ownSound = on && s?.sound != nil
        if on, let s = s {
            label = s.notes.count > 1 ? "POLY" : (s.notes.first.map { Params.noteName($0) } ?? "")
        } else {
            label = ""
        }
        let pos: Int = model.playing ? model.openPlayPos : -1
        playing = pos == index
        held = model.heldSteps.contains(index)
        let len: Int = t.pageLen(page)
        outside = col >= len
        last = len < Params.stepsPerPage && col == len - 1
    }

    func fill(_ theme: Theme) -> Color {
        if on { return theme.text }
        if tail { return theme.text.opacity(0.4) }
        return Color.clear
    }

    func outline(_ theme: Theme) -> Color {
        if playing || ownSound { return theme.accent }
        if held { return theme.text }
        return Color.clear
    }
}
