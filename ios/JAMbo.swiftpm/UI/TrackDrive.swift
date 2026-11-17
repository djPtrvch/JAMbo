import SwiftUI

/// Вклад дорожек в работу мастера (17.11, решение пользователя; на месте гониометра при MST). Модули мастера
/// обрабатывают сумму и снижают все дорожки одинаково, поэтому показывается не «сжатие дорожки», а её доля в снижении
/// модуля: GR модуля за кадр делится между дорожками пропорционально квадрату их пика (кто громче в момент срабатывания —
/// тот и виноват). Доля — dB, мгновенный подъём, спад 20 dB/s (как GR индикации); уровень дорожки — полоса метра.
/// Считается в интерфейсе, только пока виден MST; колбэк не меняется.
final class TrackDrive {
    static let fall: Float = 20
    /// Доли: [модуль 0…2 — COMP, CLIP, LIM][дорожка], dB ≥ 0.
    private(set) var share: [[Float]] = [[Float]](repeating: [Float](repeating: 0, count: Levels.channels), count: 3)
    private var last: Double = 0

    func tick(_ m: MeterState, _ d: MasterMeters, tracks: Int, now: Double) {
        let n: Int = min(tracks, Levels.master)
        let dt: Float = last > 0 ? Float(min(0.1, now - last)) : 0
        last = now
        var sum: Float = 0
        for t in 0..<n {
            let p: Float = m.framePeak(t)
            sum += p * p
        }
        let gr: [Float] = [d.comp.gr, d.clip.gr, d.lim.gr]
        for k in 0..<3 {
            for t in 0..<n {
                let p: Float = m.framePeak(t)
                let v: Float = sum > 1e-12 ? gr[k] * p * p / sum : 0
                share[k][t] = max(v, share[k][t] - TrackDrive.fall * dt)
            }
        }
    }
}

/// Полосы дорожек — вертикальные, как все метры: белая линия снизу вверх — уровень дорожки (шкала −36…0 dBFS),
/// с верхнего конца вниз — полупрозрачные доли включённых кнопками модулей (COMP жёлтая, CLIP оранжевая, LIM красная;
/// по цепочке сверху вниз), длина — dB доли по той же шкале. Под полосой — номер дорожки 9 px --dim; заглушённые — серые.
struct TrackDriveView: View {
    let model: AppModel
    static let range: Float = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            ScopeCanvas(now: tl.date) { ctx, size in draw(ctx, size) }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let n: Int = min(model.project.tracks.count, Levels.master)
        if n == 0 { return }
        let pad: CGFloat = 12
        let label: CGFloat = 16
        let bw: CGFloat = 9
        let col: CGFloat = (size.width - 2 * pad) / CGFloat(n)
        let h: CGFloat = size.height - pad - label
        let colors: [Color] = [theme.accent, theme.gr, theme.rec]
        let s: TrackDrive = model.trackDrive
        for t in 0..<n {
            let x: CGFloat = pad + col * (CGFloat(t) + 0.5) - bw / 2
            dimText(ctx, "\(t + 1)", CGPoint(x: x + bw / 2, y: pad + h + 4), .top)
            let bar = CGRect(x: x, y: pad, width: bw, height: h)
            let shape = Path(roundedRect: bar, cornerRadius: 3)
            ctx.fill(shape, with: .color(theme.meterTrack))
            let p: Float = model.meters.bars(t, stereo: false).first?.level ?? 0
            if p <= 0 { continue }
            var c = ctx
            c.clip(to: shape)
            let db: Float = 20 * log10(p)
            var cut: Float = 0
            for k in 0..<3 where model.scopeOn[k + 1] { cut += s.share[k][t] }
            let solid: CGFloat = frac(db - cut) * h
            let muted: Bool = !model.project.audible(t)
            c.fill(Path(CGRect(x: x, y: bar.maxY - solid, width: bw, height: solid)),
                   with: .color(muted ? theme.muteGrey : theme.text))
            // Доли — от верха белой линии вниз по порядку цепочки: COMP, затем CLIP, затем LIM.
            var acc: Float = 0
            for k in 0..<3 where model.scopeOn[k + 1] {
                let v: Float = s.share[k][t]
                if v <= 0.05 { continue }
                let y0: CGFloat = bar.maxY - frac(db - acc) * h
                let y1: CGFloat = bar.maxY - frac(db - acc - v) * h
                acc += v
                c.fill(Path(CGRect(x: x, y: y0, width: bw, height: max(1, y1 - y0))), with: .color(colors[k].opacity(0.5)))
            }
        }
    }

    private func frac(_ db: Float) -> CGFloat {
        return CGFloat(min(1, max(0, (db + TrackDriveView.range) / TrackDriveView.range)))
    }
}
