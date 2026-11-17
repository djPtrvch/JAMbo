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

/// Полосы дорожек: белая линия — уровень дорожки (шкала −36…0 dBFS), с правого конца — полупрозрачные доли включённых
/// кнопками модулей (COMP жёлтая, CLIP оранжевая, LIM красная; в порядке цепочки справа налево), длина — dB доли по той
/// же шкале. Слева — номер дорожки 9 px --dim; заглушённые — серые.
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
        let pad: CGFloat = 8
        let left: CGFloat = 24
        let bh: CGFloat = 9
        let row: CGFloat = min(22, (size.height - 2 * pad) / CGFloat(n))
        let top: CGFloat = (size.height - row * CGFloat(n)) / 2
        let w: CGFloat = size.width - left - pad
        let colors: [Color] = [theme.accent, theme.gr, theme.rec]
        let s: TrackDrive = model.trackDrive
        for t in 0..<n {
            let y: CGFloat = top + row * CGFloat(t) + (row - bh) / 2
            dimText(ctx, "\(t + 1)", CGPoint(x: left - 6, y: y + bh / 2), .trailing)
            let bar = CGRect(x: left, y: y, width: w, height: bh)
            let shape = Path(roundedRect: bar, cornerRadius: 3)
            ctx.fill(shape, with: .color(theme.meterTrack))
            let p: Float = model.meters.bars(t, stereo: false).first?.level ?? 0
            if p <= 0 { continue }
            var c = ctx
            c.clip(to: shape)
            let db: Float = 20 * log10(p)
            var cut: Float = 0
            for k in 0..<3 where model.scopeOn[k + 1] { cut += s.share[k][t] }
            let solid: CGFloat = frac(db - cut) * w
            let muted: Bool = !model.project.audible(t)
            c.fill(Path(CGRect(x: left, y: y, width: solid, height: bh)), with: .color(muted ? theme.muteGrey : theme.text))
            // Доли — от конца белой линии влево по порядку цепочки: COMP, затем CLIP, затем LIM.
            var acc: Float = 0
            for k in 0..<3 where model.scopeOn[k + 1] {
                let v: Float = s.share[k][t]
                if v <= 0.05 { continue }
                let x1: CGFloat = left + frac(db - acc) * w
                let x0: CGFloat = left + frac(db - acc - v) * w
                acc += v
                c.fill(Path(CGRect(x: x0, y: y, width: max(1, x1 - x0), height: bh)), with: .color(colors[k].opacity(0.5)))
            }
        }
    }

    private func frac(_ db: Float) -> CGFloat {
        return CGFloat(min(1, max(0, (db + TrackDriveView.range) / TrackDriveView.range)))
    }
}
