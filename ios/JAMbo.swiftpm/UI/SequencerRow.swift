import SwiftUI

/// 16 шагов открытой страницы. Тап — триг; нажатие и протягивание вправо — длина ноты;
/// удержание первого шага + двойной тап по другому — последний шаг паттерна. Мультитач.
struct SequencerRow: View {
    let model: AppModel
    @State private var presses: [SpatialEventCollection.Event.ID: StepPress] = [:]
    @State private var lastTap: [Int: Date] = [:]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: Layout.stepGap) {
                ForEach(0..<Params.stepsPerPage, id: \.self) { col in
                    StepCell(model: model, col: col)
                }
            }
            .contentShape(Rectangle())
            .gesture(touches(width: geo.size.width))
        }
        .frame(height: Layout.seqHeight)
    }

    private func column(_ x: CGFloat, width: CGFloat) -> Int {
        let cell: CGFloat = (width + Layout.stepGap) / CGFloat(Params.stepsPerPage)
        return min(Params.stepsPerPage - 1, max(0, Int(x / cell)))
    }

    private func touches(width: CGFloat) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    handle(e, width: width)
                }
            }
            .onEnded { events in
                for e in events {
                    finish(e.id, cancelled: e.phase == .cancelled)
                }
            }
    }

    private func handle(_ e: SpatialEventCollection.Event, width: CGFloat) {
        let col: Int = column(e.location.x, width: width)
        switch e.phase {
        case .active:
            if let p = presses[e.id] {
                move(e.id, p, to: col)
            } else {
                down(e.id, col: col)
            }
        case .ended:
            finish(e.id, cancelled: false)
        case .cancelled:
            finish(e.id, cancelled: true)
        @unknown default:
            break
        }
    }

    private func down(_ id: SpatialEventCollection.Event.ID, col: Int) {
        model.ensureAudio()
        let index: Int = model.viewPage * Params.stepsPerPage + col
        let firstHeld: Bool = presses.values.contains { $0.col == 0 }
        let secondary: Bool = firstHeld && col != 0
        if secondary, let t = lastTap[col], Date().timeIntervalSince(t) < 0.35 {
            model.setPatternLength(lastIndex: index)
            for (k, v) in presses where v.col == 0 { presses[k]?.used = true }
            lastTap[col] = nil
        }
        presses[id] = StepPress(col: col, index: index, t0: Date(), secondary: secondary)
        model.heldSteps.insert(index)
    }

    private func move(_ id: SpatialEventCollection.Event.ID, _ p: StepPress, to col: Int) {
        if p.secondary || col < p.col { return }
        if col == p.col && !p.dragged { return }
        presses[id]?.dragged = true
        presses[id]?.used = true
        model.setNoteLength(p.index, col - p.col + 1)
    }

    private func finish(_ id: SpatialEventCollection.Event.ID, cancelled: Bool) {
        guard let p = presses.removeValue(forKey: id) else { return }
        if !presses.values.contains(where: { $0.index == p.index }) { model.heldSteps.remove(p.index) }
        if cancelled { return }
        let quick: Bool = Date().timeIntervalSince(p.t0) < 0.35
        if quick && !p.dragged { lastTap[p.col] = Date() }
        if quick && !p.dragged && !p.secondary && !p.used { model.toggleStep(p.index) }
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
/// зажатый — белый контур, за длиной паттерна — бледный, последний — жёлтая черта справа.
struct StepCell: View {
    let model: AppModel
    let col: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let info: StepInfo = StepInfo(model: model, col: col)
        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(info.fill(theme))
                .overlay(noteLabel(info))
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(col % 4 == 0 ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(info.outline(theme), lineWidth: 1))
            if info.last {
                Rectangle().fill(theme.accent).frame(width: 2).padding(.vertical, 6).offset(x: 3)
            }
        }
        .opacity(info.outside ? 0.3 : 1)
    }

    private func noteLabel(_ info: StepInfo) -> some View {
        Text(info.label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(theme.bg)
            .lineLimit(1)
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

    init(model: AppModel, col: Int) {
        let t: Track = model.track
        let page: Int = model.viewPage
        let index: Int = page * Params.stepsPerPage + col
        let s: Step? = t.step(index)
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
        if on, let s = s {
            label = s.notes.count > 1 ? "POLY" : (s.notes.first.map { Params.noteName($0) } ?? "")
        } else {
            label = ""
        }
        let pos: Int = model.playing && channelOn ? model.live.playPos[model.selectedTrack] : -1
        playing = pos == index
        held = model.heldSteps.contains(index)
        let len: Int = t.pageLen(page)
        outside = channelOn && col >= len
        last = channelOn && len < Params.stepsPerPage && col == len - 1
    }

    func fill(_ theme: Theme) -> Color {
        if on { return theme.text }
        if tail { return theme.text.opacity(0.4) }
        return Color.clear
    }

    func outline(_ theme: Theme) -> Color {
        if playing { return theme.accent }
        if held { return theme.text }
        return Color.clear
    }
}
