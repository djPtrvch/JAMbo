import SwiftUI

/// Вклад дорожек в работу мастера (17.11, решение пользователя; на месте гониометра при MST). Модули мастера
/// обрабатывают сумму и снижают все дорожки одинаково, поэтому показывается не «сжатие дорожки», а её доля в работе
/// модуля: GR модуля за кадр делится между дорожками пропорционально квадрату их пика (кто громче в момент срабатывания —
/// тот и виноват). Доля и GR усреднены (постоянная ~2 с); показ — доля в процентах от всей работы модуля. Считается
/// в интерфейсе, только пока виден MST; колбэк не меняется.
final class TrackDrive {
    static let tau: Float = 2
    /// Усреднённая доля в dB: [модуль 0…2 — COMP, CLIP, LIM][дорожка].
    private(set) var share: [[Float]] = [[Float]](repeating: [Float](repeating: 0, count: Levels.channels), count: 3)
    /// Усреднённое GR модуля, dB.
    private(set) var gr: [Float] = [0, 0, 0]
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
        let g: [Float] = [d.comp.gr, d.clip.gr, d.lim.gr]
        let a: Float = min(1, dt / TrackDrive.tau)
        for k in 0..<3 {
            // Кадр без новых блоков (пики нулевые), а модуль ещё работает, — не тянуть доли к нулю.
            if sum <= 1e-12 && g[k] > 0 { continue }
            gr[k] += (g[k] - gr[k]) * a
            for t in 0..<n {
                let p: Float = m.framePeak(t)
                let v: Float = sum > 1e-12 ? g[k] * p * p / sum : 0
                share[k][t] += (v - share[k][t]) * a
            }
        }
    }

    /// Доля дорожки t в работе модуля k, 0…1; модуль почти не работает (< 0,5 dB) — 0.
    func part(_ k: Int, _ t: Int) -> Float {
        guard k >= 0 && k < 3 && t >= 0 && t < Levels.channels, gr[k] >= 0.5 else { return 0 }
        return min(1, max(0, share[k][t] / gr[k]))
    }
}

/// Вклад дорожек — вертикальные полосы 9 px, как все метры: по одной на дорожку, сверху вниз (сжатие и срез идут
/// сверху), сплошные, цветом модуля, выбранного кнопкой справа (COMP жёлтая, CLIP оранжевая, LIM красная; кнопки
/// переключают друг друга); вся высота — 100 % работы модуля. Под полосой — номер дорожки 9 px --dim, как в окне MIX.
struct TrackDriveView: View {
    let model: AppModel

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
        var k: Int = -1
        for i in 0..<3 where model.scopeOn[i + 1] { k = i }
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
            if k < 0 { continue }
            let f: CGFloat = CGFloat(s.part(k, t))
            if f < 0.01 { continue }
            var c = ctx
            c.clip(to: shape)
            c.fill(Path(CGRect(x: x, y: bar.minY, width: bw, height: f * h)), with: .color(colors[k]))
        }
    }
}
