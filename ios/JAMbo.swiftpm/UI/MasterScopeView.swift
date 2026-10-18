import SwiftUI

/// Скоп мастера вне колбэка (как ui/scope.ts веба): осциллоскоп — по столбцу на точку ширины, в столбце минимум
/// и максимум своего отрезка (окно 1 с), по кругу; гониометр — последние 4096 отсчётов выхода мастера.
final class ScopeState {
    static let window: Double = 1
    static let gonioN = 4096
    /// Ширина осциллоскопа в точках (ставит вид).
    var width: Int = 200
    private(set) var mins: [[Float]] = [[Float]](repeating: [], count: 4)
    private(set) var maxs: [[Float]] = [[Float]](repeating: [], count: 4)
    private(set) var pos = [Int](repeating: 0, count: 4)
    private var carry = [Int](repeating: 0, count: 4)
    private var cMin = [Float](repeating: 0, count: 4)
    private var cMax = [Float](repeating: 0, count: 4)
    private var seen = [Int](repeating: -1, count: 4)
    private let buf = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumTap.capacity)
    let gl = UnsafeMutablePointer<Float>.allocate(capacity: ScopeState.gonioN)
    let gr = UnsafeMutablePointer<Float>.allocate(capacity: ScopeState.gonioN)
    private(set) var gonioOk = false

    init() {
        buf.initialize(repeating: 0, count: SpectrumTap.capacity)
        gl.initialize(repeating: 0, count: ScopeState.gonioN)
        gr.initialize(repeating: 0, count: ScopeState.gonioN)
    }

    deinit {
        buf.deallocate(); gl.deallocate(); gr.deallocate()
    }

    /// Кадр (drain): новые отсчёты включённых точек — в столбцы; выключенные — пустые.
    func tick(_ s: MasterScope, on: [Bool]) {
        let w = max(1, width)
        let spc: Int = max(1, Int(ScopeState.window * AudioCore.sampleRate) / w)
        for k in 0..<4 {
            if mins[k].count != w {
                mins[k] = [Float](repeating: 0, count: w)
                maxs[k] = [Float](repeating: 0, count: w)
                pos[k] = 0
                carry[k] = 0
            }
            let tap = s.taps[k]
            let end: Int = tap.written.load()
            if !on[k] {
                if seen[k] >= 0 { clear(k) }
                seen[k] = -1
                continue
            }
            let n: Int = seen[k] < 0 ? 0 : min(SpectrumTap.capacity, end - seen[k])
            seen[k] = end
            if n <= 0 { continue }
            tap.read(into: buf, count: n, end: end)
            fold(k, n, spc, w)
        }
        let end: Int = s.gonioL.written.load()
        s.gonioL.read(into: gl, count: ScopeState.gonioN, end: end)
        s.gonioR.read(into: gr, count: ScopeState.gonioN, end: end)
        gonioOk = end > 0
    }

    private func fold(_ k: Int, _ n: Int, _ spc: Int, _ w: Int) {
        var lo: Float = cMin[k], hi: Float = cMax[k]
        var c: Int = carry[k]
        var p: Int = pos[k]
        for i in 0..<n {
            let v: Float = buf[i]
            if c == 0 {
                lo = v
                hi = v
            } else {
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            c += 1
            if c >= spc {
                mins[k][p] = lo
                maxs[k][p] = hi
                p = (p + 1) % w
                c = 0
            }
        }
        cMin[k] = lo; cMax[k] = hi; carry[k] = c; pos[k] = p
    }

    private func clear(_ k: Int) {
        for i in 0..<mins[k].count {
            mins[k][i] = 0
            maxs[k][i] = 0
        }
    }
}

/// Скоп при MST на месте миниатюр страниц: сверху гониометр (конечный выход мастера; точки L/R, повёрнутые на 45°:
/// вертикаль — mid, горизонталь — side; послесвечение — старые отсчёты окна бледнее), под ним осциллоскоп (бегущая
/// форма волны за ~1 с, справа — новое; SAT белая всегда, COMP жёлтая, CLIP оранжевая, LIM красная — кнопками,
/// полупрозрачные 60 %, SAT снизу, LIM сверху).
struct MasterScopeView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let h: CGFloat = geo.size.height - gap
            VStack(spacing: gap) {
                panel { ctx, size in drawGonio(ctx, size) }.frame(height: h * 0.6)
                panel { ctx, size in drawOsc(ctx, size) }.frame(height: h * 0.4)
            }
        }
    }

    private func panel(_ draw: @escaping (GraphicsContext, CGSize) -> Void) -> some View {
        // Время кадра — параметром вида: иначе SwiftUI не перерисовывает Canvas.
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            ScopeCanvas(now: tl.date, draw: draw)
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func drawGonio(_ ctx: GraphicsContext, _ size: CGSize) {
        let cx: CGFloat = size.width / 2, cy: CGFloat = size.height / 2
        let r: CGFloat = min(size.width, size.height) / 2 - 4
        let d: CGFloat = r * 0.70710678
        var axes = Path()
        axes.move(to: CGPoint(x: cx, y: cy - r)); axes.addLine(to: CGPoint(x: cx, y: cy + r))
        axes.move(to: CGPoint(x: cx - r, y: cy)); axes.addLine(to: CGPoint(x: cx + r, y: cy))
        axes.move(to: CGPoint(x: cx - d, y: cy - d)); axes.addLine(to: CGPoint(x: cx + d, y: cy + d))
        axes.move(to: CGPoint(x: cx + d, y: cy - d)); axes.addLine(to: CGPoint(x: cx - d, y: cy + d))
        ctx.stroke(axes, with: .color(theme.gridStrong), lineWidth: 1)
        let fl = ctx.resolve(Text("L").font(.system(size: 9)).foregroundColor(theme.dim))
        let fr = ctx.resolve(Text("R").font(.system(size: 9)).foregroundColor(theme.dim))
        ctx.draw(fl, at: CGPoint(x: cx - d - 2, y: cy - d - 3), anchor: .bottomLeading)
        ctx.draw(fr, at: CGPoint(x: cx + d - 4, y: cy - d - 3), anchor: .bottomLeading)
        let s: ScopeState = model.scope
        if !s.gonioOk { return }
        // Четыре части окна: старые бледнее (послесвечение веба — 0,75 за кадр).
        let parts = 4
        let per: Int = ScopeState.gonioN / parts
        for q in 0..<parts {
            var dots = Path()
            var i: Int = q * per
            while i < (q + 1) * per {
                let l: Float = s.gl[i], rr: Float = s.gr[i]
                let m: CGFloat = CGFloat(max(-1.2, min(1.2, (l + rr) * 0.70710678)))
                let sd: CGFloat = CGFloat(max(-1.2, min(1.2, (l - rr) * 0.70710678)))
                dots.addRect(CGRect(x: cx + sd * r - 0.6, y: cy - m * r - 0.6, width: 1.2, height: 1.2))
                i += 2
            }
            let alpha: Double = 0.55 * pow(0.75, Double(parts - 1 - q))
            ctx.fill(dots, with: .color(theme.accent.opacity(alpha)))
        }
    }

    private func drawOsc(_ ctx: GraphicsContext, _ size: CGSize) {
        let s: ScopeState = model.scope
        let w = Int(size.width.rounded())
        if s.width != w { s.width = max(1, w) }
        let cy: CGFloat = size.height / 2
        let amp: CGFloat = size.height / 2 - 2
        ctx.fill(Path(CGRect(x: 0, y: cy.rounded(), width: size.width, height: 1)), with: .color(theme.gridStrong))
        let colors: [Color] = [theme.text, theme.accent, theme.gr, theme.rec]
        for k in 0..<4 where model.scopeOn[k] {
            let lo: [Float] = s.mins[k], hi: [Float] = s.maxs[k]
            let n: Int = lo.count
            if n == 0 { continue }
            var bars = Path()
            for x in 0..<n {
                let i: Int = (s.pos[k] + x) % n
                let top: CGFloat = cy - CGFloat(max(-1, min(1, hi[i]))) * amp
                let bot: CGFloat = cy - CGFloat(max(-1, min(1, lo[i]))) * amp
                bars.addRect(CGRect(x: CGFloat(x), y: top, width: 1, height: max(1, bot - top)))
            }
            ctx.fill(bars, with: .color(colors[k].opacity(0.6)))
        }
    }
}

/// Холст скопа на кадр (now — чтобы вид менялся каждый кадр).
struct ScopeCanvas: View {
    let now: Date
    let draw: (GraphicsContext, CGSize) -> Void

    var body: some View {
        Canvas { ctx, size in draw(ctx, size) }
    }
}

/// Кнопка точки съёма скопа (COMP, CLIP, LIM — при MST на месте MORPH, FX, MOD): тап включает и выключает;
/// включённая — цветом своей формы волны.
struct ScopeButton: View {
    let model: AppModel
    let tap: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.scopeOn[tap]
        let names: [String] = ["SAT", "COMP", "CLIP", "LIM"]
        let colors: [Color] = [theme.text, theme.accent, theme.gr, theme.rec]
        return Text(names[tap])
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(on ? theme.onAccent : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? colors[tap] : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { model.scopeOn[tap].toggle() }
    }
}
