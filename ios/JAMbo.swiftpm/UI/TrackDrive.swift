import SwiftUI

/// Вклад дорожек в работу мастера (17.11, решение пользователя; на месте гониометра при MST). Модули мастера
/// обрабатывают сумму и снижают все дорожки одинаково, поэтому показывается не «сжатие дорожки», а её доля в снижении
/// модуля: GR модуля за кадр делится между дорожками пропорционально квадрату их пика (кто громче в момент срабатывания —
/// тот и виноват). Доля — dB, усреднена (постоянная ~2 с), чтобы не мелькала. Считается в интерфейсе, только пока виден
/// MST; колбэк не меняется.
final class TrackDrive {
    static let tau: Float = 2
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
        let a: Float = min(1, dt / TrackDrive.tau)
        for k in 0..<3 {
            // Кадр без новых блоков (пики нулевые), а модуль ещё работает, — не тянуть доли к нулю.
            if sum <= 1e-12 && gr[k] > 0 { continue }
            for t in 0..<n {
                let p: Float = m.framePeak(t)
                let v: Float = sum > 1e-12 ? gr[k] * p * p / sum : 0
                share[k][t] += (v - share[k][t]) * a
            }
        }
    }
}

/// Доли дорожек — вертикальные полосы, как стержни GR индикации мастера: сверху вниз (сжатие и срез идут сверху),
/// сплошные, цветом модуля (COMP жёлтая, CLIP оранжевая, LIM красная); у каждой дорожки — по полосе на включённый
/// кнопками модуль, рядом через 3 px; шкала — как у индикации: COMP 18 dB, CLIP и LIM 12 dB. Без чисел; под полосами —
/// номер дорожки 9 px --dim.
struct TrackDriveView: View {
    let model: AppModel
    static let scale: [Float] = [18, 12, 12]

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
        var mods: [Int] = []
        for k in 0..<3 where model.scopeOn[k + 1] { mods.append(k) }
        let pad: CGFloat = 12
        let label: CGFloat = 16
        let gap: CGFloat = 3
        let col: CGFloat = (size.width - 2 * pad) / CGFloat(n)
        let m: CGFloat = CGFloat(max(1, mods.count))
        let bw: CGFloat = max(2, min(9, (col - 4 - gap * (m - 1)) / m))
        let span: CGFloat = bw * m + gap * (m - 1)
        let h: CGFloat = size.height - pad - label
        let colors: [Color] = [theme.accent, theme.gr, theme.rec]
        let s: TrackDrive = model.trackDrive
        for t in 0..<n {
            let x0: CGFloat = pad + col * (CGFloat(t) + 0.5) - span / 2
            dimText(ctx, "\(t + 1)", CGPoint(x: x0 + span / 2, y: pad + h + 4), .top)
            if mods.isEmpty {
                let bar = CGRect(x: x0, y: pad, width: bw, height: h)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(theme.meterTrack))
                continue
            }
            for (i, k) in mods.enumerated() {
                let bar = CGRect(x: x0 + CGFloat(i) * (bw + gap), y: pad, width: bw, height: h)
                let shape = Path(roundedRect: bar, cornerRadius: 3)
                ctx.fill(shape, with: .color(theme.meterTrack))
                let v: Float = s.share[k][t]
                let f: CGFloat = CGFloat(min(1, max(0, v / TrackDriveView.scale[k])))
                if f < 0.005 { continue }
                var c = ctx
                c.clip(to: shape)
                c.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bw, height: f * h)), with: .color(colors[k]))
            }
        }
    }
}
