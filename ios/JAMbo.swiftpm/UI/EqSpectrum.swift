import SwiftUI

/// Спектры на поле EQ (как drawSpectrum в src/ui/eq.ts): плавные, как в FabFilter — среднее по 1/6 октавы, подъём
/// сразу, спад 30 dB/s, линия через середины отрезков. До EQ — серая линия; после EQ — серая полупрозрачная заливка
/// = линия до EQ + действие EQ (разница «после − до», сглаженная за ~50 мс: заливка сразу следует за полосами).
/// Дорожка для сравнения (решение пользователя на S5b, в вебе нет) — после её EQ, прозрачнее основного, с именем.
/// Выход мастера (тап по надписи у EQ мастера) — заливка с красным контуром. Шкала 6…−90 dBFS.
final class SpectrumDisplay {
    static let top: Float = 6
    static let bottom: Float = -90
    static let step: CGFloat = 3
    static let band: Double = pow(2, 1.0 / 12)
    static let fall: Float = 30
    static let diffTau: Double = 0.05
    let pre = SpectrumAnalyzer()
    let post = SpectrumAnalyzer()
    let compare = SpectrumAnalyzer()
    let out = SpectrumAnalyzer()
    private var cum = [Double](repeating: 0, count: SpectrumAnalyzer.bins + 1)
    private var dPre: [Float] = []
    private var dPost: [Float] = []
    private var dDiff: [Float] = []
    private var dCompare: [Float] = []
    private var dOut: [Float] = []
    private var last: Date? = nil

    /// Кривые (y в точках поля) на этот кадр.
    struct Frame {
        var pre: [CGFloat] = []
        var post: [CGFloat] = []
        var compare: [CGFloat]? = nil
        var out: [CGFloat]? = nil
    }

    func frame(_ spectra: Spectra, size: CGSize, compare cmp: Bool, out showOut: Bool, now: Date) -> Frame {
        let n: Int = Int(size.width / SpectrumDisplay.step) + 1
        let dt: Double = min(0.1, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        if dPre.count != n {
            dPre = [Float](repeating: SpectrumDisplay.bottom, count: n)
            dPost = dPre
            dCompare = dPre
            dOut = dPre
            dDiff = [Float](repeating: 0, count: n)
        }
        let fall: Float = SpectrumDisplay.fall * Float(dt)
        let k: Float = Float(1 - exp(-dt / SpectrumDisplay.diffTau))
        let g = EqGeometry(size: size, low: EqGeometry.viewLow)
        pre.analyze(spectra.pre)
        post.analyze(spectra.post)
        let a: [Float] = bands(pre, n, g)
        let b: [Float] = bands(post, n, g)
        var f = Frame()
        for i in 0..<n {
            dPre[i] = a[i] > dPre[i] ? a[i] : max(a[i], dPre[i] - fall)
            dDiff[i] += (b[i] - a[i] - dDiff[i]) * k
            dPost[i] = max(SpectrumDisplay.bottom, dPre[i] + dDiff[i])
        }
        f.pre = dPre.map { y($0, size) }
        f.post = dPost.map { y($0, size) }
        if cmp {
            compare.analyze(spectra.compare)
            f.compare = follow(&dCompare, bands(compare, n, g), fall, size)
        }
        if showOut {
            out.analyze(spectra.out)
            f.out = follow(&dOut, bands(out, n, g), fall, size)
        }
        return f
    }

    /// Подъём сразу, спад fall dB за кадр.
    private func follow(_ d: inout [Float], _ v: [Float], _ fall: Float, _ size: CGSize) -> [CGFloat] {
        for i in 0..<d.count { d[i] = v[i] > d[i] ? v[i] : max(v[i], d[i] - fall) }
        return d.map { y($0, size) }
    }

    private func y(_ db: Float, _ size: CGSize) -> CGFloat {
        let range: Float = SpectrumDisplay.top - SpectrumDisplay.bottom
        let u: Float = (SpectrumDisplay.top - db) / range
        return size.height * CGFloat(u)
    }

    /// Средняя мощность по 1/6 октавы вокруг частоты каждого столбца, dB (не ниже нижнего края шкалы).
    private func bands(_ an: SpectrumAnalyzer, _ n: Int, _ g: EqGeometry) -> [Float] {
        let bins: Int = SpectrumAnalyzer.bins
        cum[0] = 0
        for i in 0..<bins { cum[i + 1] = cum[i] + pow(10, Double(an.db[i]) / 10) }
        let binHz: Double = 48000 / Double(SpectrumAnalyzer.size)
        func at(_ f: Double) -> Double {
            let p: Double = min(Double(bins), max(0, f / binHz + 0.5))
            let i: Int = min(bins - 1, Int(p))
            let a: Double = cum[i]
            let b: Double = cum[i + 1]
            return a + (b - a) * (p - Double(i))
        }
        return (0..<n).map { i in
            let f: Double = g.freq(CGFloat(i) * SpectrumDisplay.step)
            let f0: Double = f / SpectrumDisplay.band
            let f1: Double = f * SpectrumDisplay.band
            let w: Double = max(1e-3, (f1 - f0) / binHz)
            let p: Double = (at(f1) - at(f0)) / w
            let db: Double = 10 * log10(max(1e-12, p))
            return max(SpectrumDisplay.bottom, Float(db))
        }
    }

    /// Плавная линия через точки (квадратичные кривые через середины отрезков).
    static func path(_ ys: [CGFloat], filled: Bool, height: CGFloat) -> Path {
        var p = Path()
        guard ys.count > 1 else { return p }
        let s: CGFloat = SpectrumDisplay.step
        if filled {
            p.move(to: CGPoint(x: 0, y: height))
            p.addLine(to: CGPoint(x: 0, y: ys[0]))
        } else {
            p.move(to: CGPoint(x: 0, y: ys[0]))
        }
        for i in 1..<(ys.count - 1) {
            let x: CGFloat = CGFloat(i) * s
            p.addQuadCurve(to: CGPoint(x: x + s / 2, y: (ys[i] + ys[i + 1]) / 2), control: CGPoint(x: x, y: ys[i]))
        }
        let lastX: CGFloat = CGFloat(ys.count - 1) * s
        p.addLine(to: CGPoint(x: lastX, y: ys[ys.count - 1]))
        if filled {
            p.addLine(to: CGPoint(x: lastX, y: height))
            p.closeSubpath()
        }
        return p
    }
}

/// Слой спектров под кривой и точками: перерисовка ~30 раз в секунду, пока открыт EQ.
struct EqSpectrumLayer: View {
    let model: AppModel
    let display: SpectrumDisplay
    @Environment(\.theme) private var theme

    var body: some View {
        let cmp: Int? = model.eqCompareShown
        let out: Bool = model.eqOutShown
        let name: String = cmp.map { $0 < model.project.tracks.count ? model.project.tracks[$0].name : "" } ?? ""
        return TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let _ = RedrawMeter.hit(.eqSpec)
            Canvas { ctx, size in
                let f = display.frame(model.audio.core.spectra, size: size, compare: cmp != nil, out: out, now: tl.date)
                draw(ctx, f, size, name)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: GraphicsContext, _ f: SpectrumDisplay.Frame, _ size: CGSize, _ name: String) {
        let h: CGFloat = size.height
        ctx.fill(SpectrumDisplay.path(f.post, filled: true, height: h), with: .color(theme.dim.opacity(0.22)))
        ctx.stroke(SpectrumDisplay.path(f.pre, filled: false, height: h), with: .color(theme.dim.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        if let c = f.compare {
            ctx.fill(SpectrumDisplay.path(c, filled: true, height: h), with: .color(theme.dim.opacity(0.1)))
            ctx.stroke(SpectrumDisplay.path(c, filled: false, height: h), with: .color(theme.dim.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            let label: Text = Text("vs \(name)").font(.system(size: 11, weight: .semibold)).foregroundColor(theme.dim)
            ctx.draw(label, at: CGPoint(x: size.width - 8, y: 8), anchor: .topTrailing)
        }
        if let o = f.out {
            ctx.fill(SpectrumDisplay.path(o, filled: true, height: h), with: .color(theme.dim.opacity(0.22)))
            ctx.stroke(SpectrumDisplay.path(o, filled: false, height: h), with: .color(theme.rec),
                       style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
    }
}

/// Меню дорожек для сравнения (тап по имени у EQ дорожки): под строкой, над полем EQ; OFF и дорожки (своя — серая)
/// в 2 столбца; тап мимо — закрыть. Кнопки по 44; если не помещаются — меню ровно по высоте поля EQ, кнопки ниже.
struct EqCompareMenu: View {
    static let rowH: CGFloat = 44
    static let gap: CGFloat = 4
    /// Заголовок с зазором и поля сверху и снизу (примерно; для выбора, помещаются ли кнопки по 44).
    static let chrome: CGFloat = 40
    let model: AppModel
    let width: CGFloat
    /// Высота поля EQ.
    let height: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let rows: Int = (model.project.tracks.count + 2) / 2
        let fits: Bool = EqCompareMenu.need(rows) <= height
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture { model.eqCompareMenu = false }
            box(rows, fits: fits)
                .padding(.top, 48 + Layout.gap)
        }
    }

    /// Высота меню с кнопками по 44.
    static func need(_ rows: Int) -> CGFloat {
        let buttons: CGFloat = CGFloat(rows) * rowH
        let gaps: CGFloat = CGFloat(rows - 1) * gap
        return buttons + gaps + chrome
    }

    private func box(_ rows: Int, fits: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMPARE").font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(theme.text)
            VStack(spacing: EqCompareMenu.gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: EqCompareMenu.gap) {
                        cell(2 * r - 1)
                        cell(2 * r)
                    }
                    .frame(height: fits ? EqCompareMenu.rowH : nil)
                    .frame(maxHeight: fits ? nil : .infinity)
                }
            }
        }
        .padding(8)
        .frame(width: width, height: fits ? nil : height, alignment: .top)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
    }

    /// Пункт i: −1 — OFF, 0… — дорожки; за последней дорожкой — пусто.
    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        if i < 0 {
            item("OFF", -1, enabled: true)
        } else if i < model.project.tracks.count {
            item(model.project.tracks[i].name, i, enabled: i != model.selectedTrack)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    private func item(_ title: String, _ t: Int, enabled: Bool) -> some View {
        let cur: Bool = t < 0 ? model.eqCompareShown == nil : model.eqCompareShown == t
        let fg: Color = !enabled ? theme.off : (cur ? theme.onAccent : theme.text)
        return Text(title)
            .font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cur ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { model.setEqCompare(t) } }
    }
}
