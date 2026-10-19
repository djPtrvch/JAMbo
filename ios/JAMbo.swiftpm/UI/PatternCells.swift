import SwiftUI

// Ячейки сетки паттернов: клип (миниатюра страниц клипа, полоса хода), строка (имя, повторы), «+».

/// Ячейка клипа: пустая — фон панели; заполненная — темнее, играющая — светлее и полоса хода внизу;
/// выбранная для правки — жёлтый контур; ожидающая запуска или остановки — мигает; недоступно — вспышка красным.
struct ClipCellView: View {
    let model: AppModel
    let cell: CellRef
    let lifted: Bool
    let target: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let t: Track? = cell.track < model.project.tracks.count ? model.project.tracks[cell.track] : nil
        let filled: Bool = t?.clipFilled(cell.row) ?? false
        let active: Bool = filled && t?.slot == cell.row && !(t?.stopped ?? true)
        let editing: Bool = model.channel == .track && cell.track == model.selectedTrack && cell.row == model.editSlot
        let q: Int = model.live.queued[cell.track]
        let isSlot: Bool = t?.slot == cell.row
        let queued: Bool = q == cell.row || (isSlot && q == Launcher.stop)
        let denied: Bool = model.deniedCell == cell
        let bg: Color = !filled ? theme.panel : (active ? theme.panel2 : theme.panel2.opacity(0.62))
        let outline: Color = denied ? theme.rec : (target || editing ? theme.accent : Color.clear)
        return ZStack(alignment: .bottomLeading) {
            if let t = t, filled { ClipThumb(cells: ClipThumb.rows(t, cell.row)).padding(.horizontal, 6).padding(.top, 5).padding(.bottom, 7) }
            if active && model.playing { ProgressBar(fraction: progress(t)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(denied ? theme.rec.opacity(0.35) : bg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(outline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(lifted ? 0.35 : 1)
        .modifier(Blink(on: queued && model.playing))
    }

    /// Доля прохода клипа: (тик − начало прохода) mod длина.
    private func progress(_ t: Track?) -> CGFloat {
        _ = model.live.stepSerial
        guard let t = t else { return 0 }
        let tick: Int = model.audio.core.sequencer.clock.read().nextTick - 1
        let len: Int = t.playLen
        let n: Int = ((tick - model.live.trackStart[cell.track]) % len + len) % len
        return CGFloat(n + 1) / CGFloat(len)
    }
}

/// Мигание ожидающей ячейки (0,5 с).
struct Blink: ViewModifier {
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let phase: Bool = Int(ctx.date.timeIntervalSinceReferenceDate * 4) % 2 == 0
                content.opacity(phase ? 1 : 0.35)
            }
        } else {
            content
        }
    }
}

/// Жёлтая полоса хода внизу ячейки.
struct ProgressBar: View {
    let fraction: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(theme.accent).frame(width: geo.size.width * min(1, max(0, fraction)), height: 3)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Миниатюра клипа: его страницы строками (по 16 шагов), по высоте — не меньше 4 строк, по центру.
struct ClipThumb: View {
    let cells: [[ThumbCell]]
    @Environment(\.theme) private var theme

    static func rows(_ t: Track, _ k: Int) -> [[ThumbCell]] {
        guard let r = t.clipRange(k) else { return [] }
        // Свой паттерн клипа: миниатюра читает его, как открытый.
        var v = t
        v.open = k
        return r.map { ThumbCell.page(v, page: $0) }
    }

    var body: some View {
        let colors = ThumbColors(theme: theme)
        let data = cells
        return Canvas { ctx, size in ClipThumb.draw(ctx, size, data, colors) }
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ rows: [[ThumbCell]], _ c: ThumbColors) {
        let n: Int = Params.stepsPerPage
        let units: Int = max(rows.count, 4)
        let cw: CGFloat = size.width / CGFloat(n)
        let rh: CGFloat = size.height / CGFloat(units)
        let top: CGFloat = CGFloat(units - rows.count) / 2 * rh
        for (r, row) in rows.enumerated() {
            for (s, cell) in row.enumerated() {
                let rect = CGRect(x: CGFloat(s) * cw + cw * 0.12, y: top + CGFloat(r) * rh + rh * 0.12,
                                  width: cw * 0.76, height: rh * 0.76)
                var color: Color = c.off
                if cell.on { color = c.text } else if cell.tail { color = c.text.opacity(0.45) }
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(cell.outside ? color.opacity(0.2) : color))
            }
        }
    }
}

/// Ячейка строки (колонка над MIX): имя и повторы (×n; у играющей — проход n/N или ∞ при LOOP ROW), полоса хода.
struct SceneCellView: View {
    let model: AppModel
    let row: Int
    /// Сюда встанет перетаскиваемая строка — жёлтый контур.
    var target: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        let p: Project = model.project
        let filled: Bool = p.rowFilled(row)
        let playing: Bool = model.playing && model.live.sceneRow == row
        let reps: Int = p.scenes[row].repeats
        let pass: (n: Int, frac: CGFloat) = passInfo()
        let badge: String = playing ? (p.rowLoop ? "∞" : "\(min(pass.n + 1, reps))/\(reps)") : "×\(reps)"
        return ZStack(alignment: .bottomLeading) {
            VStack(spacing: 2) {
                Text(p.sceneName(row)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(filled ? theme.text : theme.off)
                Text(badge).font(.system(size: 10)).monospacedDigit().foregroundStyle(theme.dim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if playing { ProgressBar(fraction: pass.frac) }
        }
        .background(filled ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(target ? theme.accent : Color.clear, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .modifier(Blink(on: model.playing && model.live.sceneQueued == row))
    }

    private func passInfo() -> (n: Int, frac: CGFloat) {
        _ = model.live.stepSerial
        let tick: Int = model.audio.core.sequencer.clock.read().nextTick - 1
        let len: Int = max(1, model.live.sceneLen)
        let n: Int = max(0, tick - model.live.sceneStart)
        return (n / len, CGFloat(n % len + 1) / CGFloat(len))
    }
}

/// «+» под последней строкой (в колонке строк).
struct PlusCell: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("+").font(.system(size: 20)).foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.line, lineWidth: 1))
    }
}
