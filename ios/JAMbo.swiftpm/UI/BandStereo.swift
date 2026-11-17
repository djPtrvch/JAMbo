import SwiftUI
import Accelerate

/// Стерео по полосам при MIX (16.11, решение пользователя; вне колбэка): новые отсчёты конечного выхода мастера
/// (кольца гониометра) делятся на LOW (до 150 Гц, LR4), MID (150 Гц…2 кГц, 12 dB/окт.) и HIGH (выше 2 кГц, LR4);
/// по полосе — сглаженные (~0,3 с) мощности L, R и L·R: корреляция и ширина (0 % — моно, 100 % — L и R
/// независимы, 200 % — противофаза). Фильтры — vDSP (интерфейс, не Core).
final class BandStereo {
    static let cap = 4096
    static let names: [String] = ["LOW", "MID", "HIGH"]
    /// По полосе: корреляция −1…+1 и ширина 0…200 %; live false — тишина (ниже −70 dBFS).
    private(set) var corr = [Float](repeating: 0, count: 3)
    private(set) var width = [Float](repeating: 0, count: 3)
    private(set) var live = [Bool](repeating: false, count: 3)
    private var ll = [Float](repeating: 0, count: 3)
    private var rr = [Float](repeating: 0, count: 3)
    private var lr = [Float](repeating: 0, count: 3)
    private var seen: Int = -1
    private let inL = UnsafeMutablePointer<Float>.allocate(capacity: BandStereo.cap)
    private let inR = UnsafeMutablePointer<Float>.allocate(capacity: BandStereo.cap)
    private let bL = UnsafeMutablePointer<Float>.allocate(capacity: BandStereo.cap)
    private let bR = UnsafeMutablePointer<Float>.allocate(capacity: BandStereo.cap)
    /// Фильтр полосы b канала c — setups[b * 2 + c], его задержки — delays[b * 2 + c] (по 2 секции).
    private var setups: [vDSP_biquad_Setup] = []
    private let delays: [UnsafeMutablePointer<Float>]

    init() {
        let lp150: [Double] = BandStereo.coeffs(150, low: true)
        let hp150: [Double] = BandStereo.coeffs(150, low: false)
        let lp2k: [Double] = BandStereo.coeffs(2000, low: true)
        let hp2k: [Double] = BandStereo.coeffs(2000, low: false)
        let bands: [[Double]] = [lp150 + lp150, hp150 + lp2k, hp2k + hp2k]
        var d: [UnsafeMutablePointer<Float>] = []
        for b in 0..<3 {
            for _ in 0..<2 {
                if let s = vDSP_biquad_CreateSetup(bands[b], 2) { setups.append(s) }
                let p = UnsafeMutablePointer<Float>.allocate(capacity: 6)
                p.initialize(repeating: 0, count: 6)
                d.append(p)
            }
        }
        delays = d
    }

    deinit {
        for s in setups { vDSP_biquad_DestroySetup(s) }
        for p in delays + [inL, inR, bL, bR] { p.deallocate() }
    }

    /// Баттерворт 2-го порядка (RBJ, Q 0,7071): b0, b1, b2, a1, a2.
    private static func coeffs(_ f: Double, low: Bool) -> [Double] {
        let w: Double = 2 * Double.pi * f / 48000
        let alpha: Double = sin(w) / (2 * 0.70710678)
        let c: Double = cos(w)
        let a0: Double = 1 + alpha
        let b1: Double = low ? 1 - c : -(1 + c)
        let b0: Double = low ? (1 - c) / 2 : (1 + c) / 2
        return [b0 / a0, b1 / a0, b0 / a0, -2 * c / a0, (1 - alpha) / a0]
    }

    /// Кадр (при MIX): новые отсчёты колец гониометра.
    func tick(_ s: MasterScope) {
        if setups.count < 6 { return }
        let end: Int = s.gonioL.written.load()
        let n: Int = seen < 0 ? 0 : min(BandStereo.cap, end - seen)
        seen = end
        if n <= 0 { return }
        s.gonioL.read(into: inL, count: n, end: end)
        s.gonioR.read(into: inR, count: n, end: end)
        let a: Float = Float(exp(-Double(n) / (0.3 * 48000)))
        let len = vDSP_Length(n)
        for b in 0..<3 {
            vDSP_biquad(setups[b * 2], delays[b * 2], inL, 1, bL, 1, len)
            vDSP_biquad(setups[b * 2 + 1], delays[b * 2 + 1], inR, 1, bR, 1, len)
            var sl: Float = 0, sr: Float = 0, slr: Float = 0
            vDSP_svesq(bL, 1, &sl, len)
            vDSP_svesq(bR, 1, &sr, len)
            vDSP_dotpr(bL, 1, bR, 1, &slr, len)
            let k: Float = (1 - a) / Float(n)
            ll[b] = ll[b] * a + sl * k
            rr[b] = rr[b] * a + sr * k
            lr[b] = lr[b] * a + slr * k
            measure(b)
        }
    }

    private func measure(_ b: Int) {
        let p: Float = ll[b] + rr[b]
        // −70 dBFS по мощности полосы.
        live[b] = p > 2e-7
        if !live[b] { return }
        let c: Float = lr[b] / max(1e-20, (ll[b] * rr[b]).squareRoot())
        corr[b] = max(-1, min(1, c))
        let mid: Float = max(0, p + 2 * lr[b])
        let side: Float = max(0, p - 2 * lr[b])
        width[b] = 200 * side / max(1e-20, mid + side)
    }

    /// Сброс (тап): заново от текущего сигнала.
    func reset() {
        for b in 0..<3 {
            ll[b] = 0; rr[b] = 0; lr[b] = 0
            live[b] = false
        }
    }
}

/// Панель стерео по полосам при MIX (на месте осциллоскопа): три ячейки LOW, MID, HIGH WIDTH — подпись в две
/// строки и ширина в %, под ними — полоса корреляции −1…+1 (от середины): жёлтая — норма, оранжевая — у LOW ниже
/// 0,7 (бас расползается), красная — ниже 0 (противофаза, в моно пропадёт). Тап — сброс.
struct BandStereoView: View {
    let model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: LoadAnim.frame(30), paused: LoadAnim.stop)) { tl in
            ScopeCanvas(now: tl.date) { ctx, size in draw(ctx, size) }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .onTapGesture { model.bandStereo.reset() }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let s: BandStereo = model.bandStereo
        let cell: CGFloat = size.width / 3
        let barY: CGFloat = max(48, (size.height + 40) / 2 - 6)
        for b in 0..<3 {
            let x: CGFloat = cell * (CGFloat(b) + 0.5)
            let on: Bool = s.live[b]
            let col: Color = color(b, s)
            let value: String = on ? String(format: "%.0f%%", s.width[b]) : "—"
            label(ctx, BandStereo.names[b] + "\nWIDTH", x)
            let v = Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundColor(on && col != theme.accent ? col : theme.text)
            ctx.draw(v, at: CGPoint(x: x, y: 27), anchor: .top)
            bar(ctx, CGRect(x: x - cell / 2 + 10, y: barY, width: cell - 20, height: 4.5), on ? s.corr[b] : nil, col)
        }
    }

    private func color(_ b: Int, _ s: BandStereo) -> Color {
        let c: Float = s.corr[b]
        if c < 0 { return theme.rec }
        if b == 0 && c < 0.7 { return theme.gr }
        return theme.accent
    }

    private func label(_ ctx: GraphicsContext, _ s: String, _ x: CGFloat) {
        let lines: [Substring] = s.split(separator: "\n")
        var k: Int = 0
        while k < lines.count {
            let l = Text(String(lines[k])).font(.system(size: 9)).foregroundColor(theme.dim)
            ctx.draw(l, at: CGPoint(x: x, y: 4 + CGFloat(k) * 11), anchor: .top)
            k += 1
        }
    }

    /// Полоса корреляции (как под гониометром): от середины вправо — к +1, влево — к −1; подписи −1 и +1 снизу.
    private func bar(_ ctx: GraphicsContext, _ r: CGRect, _ c: Float?, _ col: Color) {
        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(theme.meterTrack))
        let mid: CGFloat = r.midX
        if let c = c {
            let x: CGFloat = mid + CGFloat(c) * r.width / 2
            let f = CGRect(x: min(mid, x), y: r.minY, width: max(2, abs(x - mid)), height: r.height)
            var cc = ctx
            cc.clip(to: Path(roundedRect: r, cornerRadius: 2))
            cc.fill(Path(f), with: .color(col))
        }
        ctx.fill(Path(CGRect(x: mid - 0.5, y: r.minY - 2, width: 1, height: r.height + 4)), with: .color(theme.dim))
        dimText(ctx, "−1", CGPoint(x: r.minX, y: r.maxY + 3), .topLeading)
        dimText(ctx, "+1", CGPoint(x: r.maxX, y: r.maxY + 3), .topTrailing)
    }
}
