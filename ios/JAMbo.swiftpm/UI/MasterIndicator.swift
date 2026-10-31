import SwiftUI

/// Блок индикации модуля мастера (LevelBars веба) вне колбэка: IN и OUT — dB с мгновенным подъёмом и спадом
/// 20 dB/s, красный держится не меньше 300 мс; GR — dB с тем же спадом; данные старше 150 мс — тишина.
final class DynBarsState {
    static let fall: Float = 20
    private(set) var inDb: Float = -120
    private(set) var outDb: Float = -120
    private(set) var gr: Float = 0
    private(set) var inOverUntil: Double = 0
    private(set) var outOverUntil: Double = 0
    private var count = 0
    private var lastAt: Double = 0
    private var last: Double = 0
    private var mIn: Float = 0
    private var mGr: Float = 0
    private var mOut: Float = 0

    func tick(_ t: DynTele, bypass: Bool, now: Double) {
        let dt: Float = last > 0 ? Float(min(0.1, now - last)) : 0
        last = now
        let r = t.peaks(since: count)
        count = r.count
        if r.frames > 0 {
            mIn = r.inPeak
            mGr = r.gr
            mOut = r.outPeak
            lastAt = now
        }
        let live: Bool = now - lastAt < 0.15
        let vi: Float = live ? DynBarsState.db(mIn) : -120
        let vo: Float = live ? DynBarsState.db(mOut) : -120
        inDb = max(vi, inDb - DynBarsState.fall * dt)
        outDb = max(vo, outDb - DynBarsState.fall * dt)
        if vi > 0 { inOverUntil = now + 0.3 }
        if vo > 0 { outOverUntil = now + 0.3 }
        let g: Float = live && !bypass ? mGr : 0
        gr = bypass ? 0 : max(g, gr - DynBarsState.fall * dt)
    }

    static func db(_ x: Float) -> Float {
        return 20 * log10(max(x, 1e-6))
    }
}

/// Индикация COMP, CLIP, LIM (кадры из MasterChain).
final class MasterMeters {
    let comp = DynBarsState()
    let clip = DynBarsState()
    let lim = DynBarsState()

    func tick(_ m: MasterChain, _ p: Project, now: Double) {
        comp.tick(m.compTele, bypass: p.cmpBypass, now: now)
        clip.tick(m.clipTele, bypass: p.clipBypass, now: now)
        lim.tick(m.limTele, bypass: p.limBypass, now: now)
    }
}

/// Индикация мастера при MST в окне сэмпла (в стиле Drambo): блоки COMP | CLIP | LIM в порядке цепочки, в каждом
/// стержни IN | GR | OUT (9 px, скругление 3, дорожка --meter-track, сплошная заливка): IN и OUT — снизу вверх,
/// −48…0 dBFS, жёлтые, выше 0 — красные; GR — сверху вниз, оранжевый (COMP — 18 dB, CLIP и LIM — 12 dB); риска
/// THRESHOLD / CEILING — только на IN; bypass — серые, GR ноль. Тап по блоку — окно модуля.
struct MasterIndicator: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            blocks(now: tl.date.timeIntervalSinceReferenceDate)
        }
        .padding(8)
    }

    private func blocks(now: Double) -> some View {
        let p: Project = model.project
        let d: MasterMeters = model.dynMeters
        return HStack(spacing: 8) {
            block("COMP", d.comp, bypass: p.cmpBypass, grMax: 18, mark: value(p, "cmp.threshold", -10), now: now)
                .onTapGesture { model.openMasterWindow(MasterScope.comp) }
            block("CLIP", d.clip, bypass: p.clipBypass, grMax: 12, mark: value(p, "clip.ceiling", -1), now: now)
                .onTapGesture { model.openMasterWindow(MasterScope.clip) }
            block("LIM", d.lim, bypass: p.limBypass, grMax: 12, mark: value(p, "lim.ceiling", -1), now: now)
                .onTapGesture { model.openMasterWindow(MasterScope.lim) }
        }
    }

    private func value(_ p: Project, _ id: String, _ def: Double) -> Float {
        return Float(p.master[id] ?? def)
    }

    private func block(_ title: String, _ s: DynBarsState, bypass: Bool, grMax: Float, mark: Float,
                       now: Double) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 10)).tracking(1).foregroundStyle(theme.dim)
            Canvas { ctx, size in
                MasterIndicator.draw(ctx, size, s, bypass: bypass, grMax: grMax, mark: mark, now: now, theme: theme)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    static let barW: CGFloat = 9
    static let labelH: CGFloat = 14

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ s: DynBarsState, bypass: Bool, grMax: Float,
                     mark: Float, now: Double, theme: Theme) {
        let barH: CGFloat = size.height - labelH
        if barH <= 0 { return }
        let cw: CGFloat = size.width
        let cx: [CGFloat] = [cw / 6, cw / 2, 5 * cw / 6]
        let off: Color = theme.meterTrack.mix(with: .white, by: 0.2)
        func frac(_ db: Float) -> CGFloat {
            return CGFloat(min(1, max(0, (db + 48) / 48)))
        }
        func levelColor(_ db: Float, _ until: Double) -> Color {
            if bypass { return off }
            return db > 0 || now < until ? theme.rec : theme.accent
        }
        func bar(_ k: Int, _ fill: Color, _ top: CGFloat, _ h: CGFloat) {
            let x: CGFloat = (cx[k] - barW / 2).rounded()
            let r = CGRect(x: x, y: 0, width: barW, height: barH)
            let shape = Path(roundedRect: r, cornerRadius: 3)
            ctx.fill(shape, with: .color(theme.meterTrack))
            if h > 0 {
                var c = ctx
                c.clip(to: shape)
                c.fill(Path(CGRect(x: x, y: top, width: barW, height: h)), with: .color(fill))
            }
        }
        let fIn: CGFloat = frac(s.inDb)
        let fOut: CGFloat = frac(s.outDb)
        bar(0, levelColor(s.inDb, s.inOverUntil), barH * (1 - fIn), barH * fIn)
        bar(2, levelColor(s.outDb, s.outOverUntil), barH * (1 - fOut), barH * fOut)
        let g: CGFloat = CGFloat(min(1, s.gr / grMax))
        bar(1, bypass ? off : theme.gr, 0, barH * g)
        // Риска порога — только на IN.
        let ry: CGFloat = (barH * (1 - frac(mark)) - 1).rounded()
        let x0: CGFloat = (cx[0] - barW / 2).rounded()
        let risk = CGRect(x: x0 - 6, y: max(0, min(barH - 2, ry)), width: barW + 12, height: 2)
        ctx.fill(Path(risk), with: .color(theme.meterThr))
        let names: [String] = ["IN", "GR", "OUT"]
        for k in 0..<3 {
            let t = ctx.resolve(Text(names[k]).font(.system(size: 9)).foregroundColor(theme.dim))
            ctx.draw(t, at: CGPoint(x: cx[k], y: size.height), anchor: .bottom)
        }
    }
}
