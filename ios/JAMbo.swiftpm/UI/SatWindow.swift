import SwiftUI

/// Дисплей окна сатуратора (saturator.ts веба; решение пользователя: из двух половин DISPLAY — только SPECTRUM):
/// TRANSFER (не шире 35 %) | SPECTRUM. Точки съёма спектра (вход и выход сатуратора) пишутся, только пока окно открыто.
struct SatDisplay: View {
    let model: AppModel
    @State private var spec = SatSpectrumState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w: CGFloat = min(geo.size.width * 0.35, geo.size.height)
                HStack(spacing: Layout.gap) {
                    SatTransfer(model: model, now: now).frame(width: w)
                    SatSpectrum(model: model, spec: spec, now: now)
                }
            }
        }
        .onAppear { model.audio.core.master.satOn.store(1) }
        .onDisappear { model.audio.core.master.satOn.store(0) }
    }
}

/// TRANSFER сатуратора: оси −1…+1, сетка через 0,5, диагональ, кривая (белая) = кривая(x·g) / c (без TONE и MIX);
/// точка текущего уровня — наибольший по модулю отсчёт входа последних ~20 мс, на кривой; ручка (28 px) на кривой при
/// входе 0,5 с подписью «DRIVE …». Палец в любом месте поля по вертикали — DRIVE (240 px на весь диапазон).
struct SatTransfer: View {
    static let handle: CGFloat = 28
    let model: AppModel
    let now: Double
    @State private var start: Double? = nil
    @State private var probe = SatProbe()
    @Environment(\.theme) private var theme

    private var driveP: ParamDef { return Params.masterColumns[0][0] }
    private var typeP: ParamDef { return Params.masterColumns[0][1] }

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in draw(ctx, size) }
                .contentShape(Rectangle())
                .gesture(drag)
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil {
                    start = driveP.toNorm(model.masterValue(driveP))
                    model.beginGesture()
                }
                guard let s = start else { return }
                let d: Double = Double(-g.translation.height / MasterField.travel)
                model.setMaster(driveP, driveP.fromNorm(s + d))
            }
            .onEnded { _ in
                if start != nil {
                    model.endGesture()
                }
                start = nil
            }
    }

    private func curve(_ x: Double) -> Double {
        let type: Int = Int(model.masterValue(typeP).rounded())
        return MasterTables.shared.satCurve(type, driveDb: model.masterValue(driveP), x)
    }

    private func pt(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        let px: CGFloat = (CGFloat(x) + 1) / 2 * size.width
        let py: CGFloat = (1 - CGFloat(y)) / 2 * size.height
        return CGPoint(x: px, y: min(size.height, max(0, py)))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        // Сетка через 0,5 и диагональ.
        for k in 1..<4 {
            let f: CGFloat = CGFloat(k) / 4
            ctx.fill(Path(CGRect(x: (f * w).rounded(), y: 0, width: 1, height: h)), with: .color(theme.line))
            ctx.fill(Path(CGRect(x: 0, y: (f * h).rounded(), width: w, height: 1)), with: .color(theme.line))
        }
        var diag = Path()
        diag.move(to: CGPoint(x: 0, y: h))
        diag.addLine(to: CGPoint(x: w, y: 0))
        ctx.stroke(diag, with: .color(theme.dim), lineWidth: 1)
        let bypass: Bool = model.project.satBypass
        var p = Path()
        let n: Int = max(2, Int(w))
        for i in 0...n {
            let x: Double = -1 + 2 * Double(i) / Double(n)
            let q: CGPoint = pt(x, curve(x), size)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        ctx.stroke(p, with: .color(bypass ? theme.dim : theme.text), lineWidth: 1.5)
        if !bypass { drawLive(ctx, size) }
        drawHandle(ctx, size)
        MasterDraw.title(ctx, "TRANSFER", size, theme)
    }

    /// Точка текущего уровня: наибольший по модулю отсчёт входа последних 1024 отсчётов (пока идёт сигнал).
    private func drawLive(_ ctx: GraphicsContext, _ size: CGSize) {
        let x: Float = probe.peak(model.audio.core.master.satIn)
        if abs(x) < 1e-4 { return }
        let xv: Double = Swift.max(-1, Swift.min(1, Double(x)))
        let q: CGPoint = pt(xv, curve(xv), size)
        ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)), with: .color(theme.accent))
    }

    /// Ручка на кривой при входе 0,5 с подписью DRIVE.
    private func drawHandle(_ ctx: GraphicsContext, _ size: CGSize) {
        let q: CGPoint = pt(0.5, curve(0.5), size)
        let col: Color = theme.text
        let rr: CGFloat = SatTransfer.handle / 2 - 1
        let circle = Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr))
        ctx.fill(circle, with: .color(theme.panel))
        ctx.stroke(circle, with: .color(col), lineWidth: 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)), with: .color(col))
        let s: String = "DRIVE " + driveP.format(model.masterValue(driveP)).replacingOccurrences(of: "\n", with: " ")
        let t = ctx.resolve(Text(s).font(.system(size: 10)).foregroundColor(col))
        ctx.draw(t, at: CGPoint(x: q.x, y: q.y + rr + 4), anchor: .top)
    }
}

/// Последние 1024 отсчёта входа сатуратора для точки текущего уровня (буфер — вне колбэка, один на окно).
final class SatProbe {
    static let count = 1024
    private let buf: UnsafeMutablePointer<Float>

    init() {
        buf = .allocate(capacity: SatProbe.count)
        buf.initialize(repeating: 0, count: SatProbe.count)
    }

    deinit { buf.deallocate() }

    /// Наибольший по модулю отсчёт (со знаком).
    func peak(_ tap: SpectrumTap) -> Float {
        tap.read(into: buf, count: SatProbe.count)
        var x: Float = 0
        var i: Int = 0
        while i < SatProbe.count {
            let v: Float = buf[i]
            if abs(v) > abs(x) { x = v }
            i += 1
        }
        return x
    }
}

/// Спектры входа и выхода сатуратора (как спектры EQ: среднее по 1/6 октавы, подъём сразу, спад 30 dB/s);
/// FREEZE — кривые не обновляются.
final class SatSpectrumState {
    static let step: CGFloat = 3
    static let bottom: Float = -96
    let pre = SpectrumAnalyzer()
    let post = SpectrumAnalyzer()
    var frozen: Bool = false
    private(set) var dIn: [Float] = []
    private(set) var dOut: [Float] = []
    private var cum = [Double](repeating: 0, count: SpectrumAnalyzer.bins + 1)
    private var last: Double = 0

    func update(_ m: MasterChain, size: CGSize, now: Double) {
        let n: Int = Int(size.width / SatSpectrumState.step) + 1
        if dIn.count != n {
            dIn = [Float](repeating: SatSpectrumState.bottom, count: n)
            dOut = dIn
        }
        let dt: Double = last > 0 ? min(0.1, now - last) : 0
        last = now
        if frozen { return }
        let fall: Float = 30 * Float(dt)
        let g = EqGeometry(size: size)
        pre.analyze(m.satIn)
        post.analyze(m.satOut)
        let a: [Float] = bands(pre, n, g)
        let b: [Float] = bands(post, n, g)
        for i in 0..<n {
            dIn[i] = a[i] > dIn[i] ? a[i] : max(a[i], dIn[i] - fall)
            dOut[i] = b[i] > dOut[i] ? b[i] : max(b[i], dOut[i] - fall)
        }
    }

    /// Средняя мощность по 1/6 октавы вокруг частоты каждого столбца, dB.
    private func bands(_ an: SpectrumAnalyzer, _ n: Int, _ g: EqGeometry) -> [Float] {
        let bins: Int = SpectrumAnalyzer.bins
        cum[0] = 0
        for i in 0..<bins { cum[i + 1] = cum[i] + pow(10, Double(an.db[i]) / 10) }
        let binHz: Double = 48000 / Double(SpectrumAnalyzer.size)
        var out = [Float](repeating: SatSpectrumState.bottom, count: n)
        for i in 0..<n {
            let f: Double = g.freq(CGFloat(i) * SatSpectrumState.step)
            let f0: Double = f / SpectrumDisplay.band
            let f1: Double = f * SpectrumDisplay.band
            let w: Double = max(1e-3, (f1 - f0) / binHz)
            let p: Double = (at(f1, binHz) - at(f0, binHz)) / w
            let db: Double = 10 * log10(max(1e-12, p))
            out[i] = max(SatSpectrumState.bottom, Float(db))
        }
        return out
    }

    private func at(_ f: Double, _ binHz: Double) -> Double {
        let bins: Int = SpectrumAnalyzer.bins
        let p: Double = min(Double(bins), max(0, f / binHz + 0.5))
        let i: Int = min(bins - 1, Int(p))
        return cum[i] + (cum[i + 1] - cum[i]) * (p - Double(i))
    }
}

/// SPECTRUM: 20 Hz…20 kHz (логарифмически), уровень 0…−96 dB (2·SCALE); вход — серая заливка, выход — белый контур;
/// белая линия FOCUS (на 20 Hz — у левого края, «FOCUS OFF») тянется по горизонтали (±22 px, 20…2000 Hz); двойной тап
/// мимо линии — FREEZE.
struct SatSpectrum: View {
    let model: AppModel
    let spec: SatSpectrumState
    let now: Double
    @State private var touching: Bool = false
    @State private var focusStart: CGFloat? = nil
    @State private var moved: Bool = false
    @State private var lastTap: Date = .distantPast
    @Environment(\.theme) private var theme

    private var focusP: ParamDef { return Params.byId["sat.focus"] ?? Params.masterColumns[0][0] }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx, size) }
                .contentShape(Rectangle())
                .gesture(drag(geo.size))
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let geo = EqGeometry(size: size)
                if !touching {
                    touching = true
                    moved = false
                    let fx: CGFloat = geo.x(model.masterValue(focusP))
                    if abs(g.startLocation.x - fx) <= MasterDraw.lineHit {
                        focusStart = fx
                        model.beginGesture()
                    } else {
                        focusStart = nil
                    }
                }
                if abs(g.translation.width) > 6 || abs(g.translation.height) > 6 { moved = true }
                guard let x0 = focusStart else { return }
                model.setMaster(focusP, geo.freq(x0 + g.translation.width))
            }
            .onEnded { _ in
                if focusStart != nil {
                    model.endGesture()
                } else if !moved {
                    // Двойной тап мимо линии — FREEZE.
                    let t = Date()
                    if t.timeIntervalSince(lastTap) < EqPlot.doubleTap {
                        spec.frozen.toggle()
                        lastTap = .distantPast
                    } else {
                        lastTap = t
                    }
                }
                touching = false
                focusStart = nil
            }
    }

    private func y(_ db: Float, _ h: CGFloat) -> CGFloat {
        let u: CGFloat = CGFloat(-db) / CGFloat(-SatSpectrumState.bottom)
        return min(h, max(0, u * h))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        spec.update(model.audio.core.master, size: size, now: now)
        let h: CGFloat = size.height
        let geo = EqGeometry(size: size)
        // Сетка: уровни через 12 dB, частоты 100 Hz, 1 kHz, 10 kHz.
        var db: Int = 0
        while db > Int(SatSpectrumState.bottom) {
            let yy: CGFloat = y(Float(db), h).rounded()
            ctx.fill(Path(CGRect(x: 0, y: yy, width: size.width, height: 1)), with: .color(theme.line))
            let s: String = db == 0 ? "0" : "\(db)"
            let t = ctx.resolve(Text(s).font(.system(size: 10)).foregroundColor(theme.dim))
            ctx.draw(t, at: CGPoint(x: 4, y: yy + 2), anchor: .topLeading)
            db -= 12
        }
        for (f, s) in [(100.0, "100"), (1000.0, "1k"), (10000.0, "10k")] {
            let xx: CGFloat = geo.x(f).rounded()
            ctx.fill(Path(CGRect(x: xx, y: 0, width: 1, height: h)), with: .color(theme.line))
            let t = ctx.resolve(Text(s).font(.system(size: 10)).foregroundColor(theme.dim))
            ctx.draw(t, at: CGPoint(x: xx + 3, y: h - 4), anchor: .bottomLeading)
        }
        let ysIn: [CGFloat] = spec.dIn.map { y($0, h) }
        let ysOut: [CGFloat] = spec.dOut.map { y($0, h) }
        ctx.fill(SpectrumDisplay.path(ysIn, filled: true, height: h), with: .color(theme.dim.opacity(0.35)))
        ctx.stroke(SpectrumDisplay.path(ysOut, filled: false, height: h), with: .color(theme.text), lineWidth: 1.5)
        drawFocus(ctx, size, geo)
        MasterDraw.title(ctx, "SPECTRUM", size, theme)
        if spec.frozen { MasterDraw.pauseLabel(ctx, "FREEZE", theme) }
    }

    /// Линия FOCUS с подписью.
    private func drawFocus(_ ctx: GraphicsContext, _ size: CGSize, _ geo: EqGeometry) {
        let v: Double = model.masterValue(focusP)
        let col: Color = theme.meterThr
        let fx: CGFloat = max(1, geo.x(v).rounded())
        ctx.fill(Path(CGRect(x: fx - 1, y: 0, width: 2, height: size.height)), with: .color(col))
        let s: String = "FOCUS " + focusP.format(v)
        let t = ctx.resolve(Text(s).font(.system(size: 11)).foregroundColor(col))
        ctx.draw(t, at: CGPoint(x: fx + 6, y: 24), anchor: .topLeading)
    }
}
