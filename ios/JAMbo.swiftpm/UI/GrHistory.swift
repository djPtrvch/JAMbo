import SwiftUI

/// История GR модулей мастера (17.11, решение пользователя; на месте гониометра при MST): GR COMP, CLIP, LIM за
/// последние 10 с, по точке на кадр метров (кольцо). Берётся из индикации мастера (MasterMeters: мгновенный подъём,
/// спад 20 dB/s; bypass — 0). Копится в интерфейсе, только пока виден MST; колбэк не меняется.
final class GrHistory {
    static let seconds: Double = 10
    static let size = 600
    /// [модуль 0…2 — COMP, CLIP, LIM][точка], dB ≥ 0.
    private(set) var gr: [[Float]] = [[Float]](repeating: [Float](repeating: 0, count: GrHistory.size), count: 3)
    /// Следующая точка (самая старая).
    private(set) var pos = 0
    private var next: Double = 0

    func tick(_ d: MasterMeters, now: Double) {
        let step: Double = GrHistory.seconds / Double(GrHistory.size)
        if now < next { return }
        next = max(now, next + step)
        if next - now > step { next = now + step }
        gr[0][pos] = d.comp.gr
        gr[1][pos] = d.clip.gr
        gr[2][pos] = d.lim.gr
        pos = (pos + 1) % GrHistory.size
    }
}

/// График: бегущий, справа — новое; сверху 0 dB, вниз — GR до 12 dB (глубже — у нижнего края); линии 1,5 px —
/// COMP жёлтая, CLIP оранжевая, LIM красная (цвета кнопок и форм волны скопа); сетка 3, 6, 9 dB, подписи −3, −6, −12
/// слева 9 px --dim. Модуль без GR — линия на нуле (у верхнего края её нет).
struct GrHistoryView: View {
    let model: AppModel
    static let range: Float = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            ScopeCanvas(now: tl.date) { ctx, size in draw(ctx, size) }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let top: CGFloat = 12
        let left: CGFloat = 26
        let right: CGFloat = 8
        let h: CGFloat = size.height - 2 * top
        let w: CGFloat = size.width - left - right
        if h <= 0 || w <= 0 { return }
        let range: CGFloat = CGFloat(GrHistoryView.range)
        for db in [3, 6, 9, 12] {
            let y: CGFloat = top + h * CGFloat(db) / range
            ctx.fill(Path(CGRect(x: left, y: y.rounded(), width: w, height: 1)), with: .color(theme.grid))
        }
        ctx.fill(Path(CGRect(x: left, y: top, width: w, height: 1)), with: .color(theme.gridStrong))
        for db in [3, 6, 12] {
            dimText(ctx, "−\(db)", CGPoint(x: left - 5, y: top + h * CGFloat(db) / range), .trailing)
        }
        let s: GrHistory = model.grHistory
        let n: Int = GrHistory.size
        let dx: CGFloat = w / CGFloat(n - 1)
        let colors: [Color] = [theme.accent, theme.gr, theme.rec]
        for k in 0..<3 {
            let line: [Float] = s.gr[k]
            var path = Path()
            var any = false
            for i in 0..<n {
                let v: Float = line[(s.pos + i) % n]
                if v > 0.05 { any = true }
                let y: CGFloat = top + h * CGFloat(min(GrHistoryView.range, max(0, v))) / range
                let p = CGPoint(x: left + CGFloat(i) * dx, y: y)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            if any { ctx.stroke(path, with: .color(colors[k]), lineWidth: 1.5) }
        }
    }
}
