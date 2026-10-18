import SwiftUI

/// История телеметрии модуля мастера для дисплея окна (historyColumns и Freeze веба): последние 4 с кадров DynTele
/// (раз в 256 отсчётов — 187,5 кадра в секунду), каждый столбец — максимум своего отрезка; FREEZE — снимок кольца.
final class TeleHistory {
    /// Кадров на 4 с.
    static let frames: Int = 750
    /// Кадров не было дольше — дисплей пуст (звук остановлен).
    static let liveTime: Double = 0.3
    private(set) var frozen: Bool = false
    private let sIn: UnsafeMutablePointer<Float>
    private let sGr: UnsafeMutablePointer<Float>
    private let sOut: UnsafeMutablePointer<Float>
    private var sWritten: Int = 0
    private var lastWritten: Int = -1
    private var lastAt: Double = -1e9

    struct Columns {
        var inDb: [Float]
        var outDb: [Float]
        var gr: [Float]
    }

    init() {
        let n: Int = DynTele.capacity
        sIn = .allocate(capacity: n)
        sGr = .allocate(capacity: n)
        sOut = .allocate(capacity: n)
        sIn.initialize(repeating: 0, count: n)
        sGr.initialize(repeating: 0, count: n)
        sOut.initialize(repeating: 0, count: n)
    }

    deinit {
        sIn.deallocate()
        sGr.deallocate()
        sOut.deallocate()
    }

    /// FREEZE: включение снимает копию кольца, выключение возвращает живую историю.
    func setFrozen(_ on: Bool, _ t: DynTele) {
        frozen = on
        if !on { return }
        let n: Int = DynTele.capacity
        sIn.update(from: t.inPeak, count: n)
        sGr.update(from: t.gr, count: n)
        sOut.update(from: t.outPeak, count: n)
        sWritten = t.written.load()
    }

    /// Кадры приходят (звук идёт); обновляется в columns.
    func isLive(_ now: Double) -> Bool {
        return now - lastAt < TeleHistory.liveTime
    }

    /// Последний кадр модуля (живой, не снимок FREEZE): уровень детектора в dB и GR; nil — кадров нет.
    func latest(_ t: DynTele, now: Double) -> (det: Float, gr: Float)? {
        let w: Int = t.written.load()
        if w == 0 || !isLive(now) { return nil }
        let q: Int = (w - 1) & (DynTele.capacity - 1)
        return (t.det[q], t.gr[q])
    }

    /// Столбцы за 4 с: вход и выход в dB (−200 — нет сигнала), GR в dB ≥ 0.
    func columns(_ t: DynTele, cols: Int, now: Double) -> Columns {
        let w: Int = t.written.load()
        if w != lastWritten {
            lastWritten = w
            lastAt = now
        }
        let n: Int = max(0, cols)
        var c = Columns(inDb: [Float](repeating: -200, count: n), outDb: [Float](repeating: -200, count: n),
                        gr: [Float](repeating: 0, count: n))
        let live: Bool = frozen || now - lastAt < TeleHistory.liveTime
        if !live || n == 0 { return c }
        let pIn: UnsafeMutablePointer<Float> = frozen ? sIn : t.inPeak
        let pGr: UnsafeMutablePointer<Float> = frozen ? sGr : t.gr
        let pOut: UnsafeMutablePointer<Float> = frozen ? sOut : t.outPeak
        let end: Int = frozen ? sWritten : w
        let f: Int = TeleHistory.frames
        let mask: Int = DynTele.capacity - 1
        let lo: Int = max(0, end - DynTele.capacity + 1)
        var x: Int = 0
        while x < n {
            let a: Int = end - f + x * f / n
            let b: Int = end - f + (x + 1) * f / n
            var k: Int = max(a, lo)
            let stop: Int = min(max(b, a + 1), end)
            var mi: Float = 0
            var mo: Float = 0
            var mg: Float = 0
            while k < stop {
                let q: Int = k & mask
                mi = max(mi, pIn[q])
                mo = max(mo, pOut[q])
                mg = max(mg, pGr[q])
                k += 1
            }
            c.inDb[x] = mi > 0 ? 20 * log10(mi) : -200
            c.outDb[x] = mo > 0 ? 20 * log10(mo) : -200
            c.gr[x] = mg
            x += 1
        }
        return c
    }
}

/// Рисование дисплеев окон модулей мастера (masterwin.ts веба): шкала dB (верх 0 dBFS, низ −48 — SCALE всегда
/// 48 dB, S5a), сетка через 6 dB с подписями, подписи пиков GR, надпись FREEZE.
enum MasterDraw {
    static let scale: CGFloat = 48
    static let gridStep: Int = 6
    /// Зона касания линии (CEILING, THRESHOLD), px (±).
    static let lineHit: CGFloat = 22

    /// dB → y на высоте h.
    static func y(_ db: Double, _ h: CGFloat) -> CGFloat {
        let v: CGFloat = CGFloat(-db) / scale * h
        return min(h, max(0, v))
    }

    static func grid(_ ctx: GraphicsContext, _ size: CGSize, _ theme: Theme, labels: Bool = true) {
        var db: Int = 0
        while CGFloat(-db) < scale {
            let y: CGFloat = (CGFloat(-db) / scale * size.height).rounded()
            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(theme.line))
            if labels {
                let s: String = db == 0 ? "0" : "\(db)"
                let t = ctx.resolve(Text(s).font(.system(size: 10)).foregroundColor(theme.dim))
                ctx.draw(t, at: CGPoint(x: 4, y: y + 2), anchor: .topLeading)
            }
            db -= gridStep
        }
    }

    /// Подписи пиков GR: локальные максимумы ≥ 1 dB, не чаще gapMs, до 6 самых сильных (оранжевые «-3.1»).
    static func grPeaks(_ ctx: GraphicsContext, _ gr: [Float], _ size: CGSize, gapMs: Double, _ theme: Theme) {
        let cols: Int = gr.count
        if cols < 3 { return }
        let gapCols: Int = max(1, Int((gapMs / 1000 / 4 * Double(cols)).rounded()))
        var peaks: [(x: Int, v: Float)] = []
        var x: Int = 1
        while x < cols - 1 {
            let v: Float = gr[x]
            if v >= 1 && v >= gr[x - 1] && v >= gr[x + 1] {
                if let last = peaks.last, x - last.x < gapCols {
                    if v > last.v { peaks[peaks.count - 1] = (x, v) }
                } else {
                    peaks.append((x, v))
                }
            }
            x += 1
        }
        peaks.sort { $0.v > $1.v }
        for p in peaks.prefix(6) {
            let y: CGFloat = min(size.height - 12, CGFloat(p.v) / scale * size.height + 3)
            let px: CGFloat = min(size.width - 14, max(14, CGFloat(p.x)))
            let s: String = String(format: "-%.1f", p.v)
            let t = ctx.resolve(Text(s).font(.system(size: 10)).foregroundColor(theme.gr))
            ctx.draw(t, at: CGPoint(x: px, y: y), anchor: .top)
        }
    }

    /// Надпись паузы слева вверху (правее подписей сетки).
    static func pauseLabel(_ ctx: GraphicsContext, _ text: String, _ theme: Theme) {
        let t = ctx.resolve(Text(text).font(.system(size: 11, weight: .semibold)).foregroundColor(theme.accent))
        ctx.draw(t, at: CGPoint(x: 30, y: 6), anchor: .topLeading)
    }

    /// Ломаная по столбцам: заливка от низа (closed) или линия.
    static func levelPath(_ data: [Float], _ h: CGFloat, closed: Bool) -> Path {
        var p = Path()
        let n: Int = data.count
        if closed { p.move(to: CGPoint(x: 0, y: h)) }
        var x: Int = 0
        while x < n {
            let pt = CGPoint(x: CGFloat(x), y: y(Double(data[x]), h))
            if x == 0 && !closed { p.move(to: pt) } else { p.addLine(to: pt) }
            x += 1
        }
        if closed {
            p.addLine(to: CGPoint(x: CGFloat(n), y: h))
            p.closeSubpath()
        }
        return p
    }

    /// GR сверху вниз (высота — GR в dB по шкале).
    static func grPath(_ gr: [Float], _ h: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        var x: Int = 0
        while x < gr.count {
            let y: CGFloat = min(h, CGFloat(gr[x]) / scale * h)
            p.addLine(to: CGPoint(x: CGFloat(x), y: y))
            p.addLine(to: CGPoint(x: CGFloat(x + 1), y: y))
            x += 1
        }
        p.addLine(to: CGPoint(x: CGFloat(gr.count), y: 0))
        p.closeSubpath()
        return p
    }

    /// Вход выше 0 dBFS — светлая полоса 3 px у верхней кромки.
    static func overMarks(_ ctx: GraphicsContext, _ inDb: [Float], _ theme: Theme) {
        var x: Int = 0
        while x < inDb.count {
            if inDb[x] > 0 {
                var e: Int = x
                while e + 1 < inDb.count && inDb[e + 1] > 0 { e += 1 }
                let r = CGRect(x: CGFloat(x), y: 0, width: CGFloat(e - x + 1), height: 3)
                ctx.fill(Path(r), with: .color(theme.text.opacity(0.7)))
                x = e
            }
            x += 1
        }
    }

    /// Пунктир (порог компрессора): жёлтый и толще, пока параметр меняют.
    static func dashed(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, hot: Bool, _ theme: Theme) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        let st = StrokeStyle(lineWidth: hot ? 1.5 : 1, dash: [4, 4])
        ctx.stroke(p, with: .color(hot ? theme.accent : theme.meterThr), style: st)
    }

    /// Подпись дисплея справа внизу (TRANSFER, LEVEL).
    static func title(_ ctx: GraphicsContext, _ text: String, _ size: CGSize, _ theme: Theme) {
        let t = ctx.resolve(Text(text).font(.system(size: 9)).tracking(1).foregroundColor(theme.dim))
        ctx.draw(t, at: CGPoint(x: size.width - 6, y: size.height - 4), anchor: .bottomTrailing)
    }

    /// Линия потолка или порога (2 px, --meter-thr) с числом справа.
    static func line(_ ctx: GraphicsContext, _ db: Double, _ size: CGSize, _ theme: Theme) {
        let cy: CGFloat = y(db, size.height).rounded()
        ctx.fill(Path(CGRect(x: 0, y: cy - 1, width: size.width, height: 2)), with: .color(theme.meterThr))
        let t = ctx.resolve(Text(String(format: "%.1f", db)).font(.system(size: 11)).foregroundColor(theme.meterThr))
        let below: Bool = cy <= 16
        ctx.draw(t, at: CGPoint(x: size.width - 6, y: below ? cy + 3 : cy - 3), anchor: below ? .topTrailing : .bottomTrailing)
    }
}

/// Блок индикации модуля справа в окне (LevelBars — тот же компонент и данные, что слева при MST).
struct DynBlock: View {
    let model: AppModel
    let module: Int
    let now: Double
    @Environment(\.theme) private var theme

    var body: some View {
        let title: String = MasterPresetBook.titles[module]
        return VStack(spacing: 4) {
            Text(title).font(.system(size: 10)).tracking(1).foregroundStyle(theme.dim)
            Canvas { ctx, size in draw(ctx, size) }
        }
        .padding(8)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let d: MasterMeters = model.dynMeters
        let bypass: Bool = model.masterBypass(module)
        let cols: [[ParamDef]] = Params.masterColumns
        switch module {
        case MasterScope.comp:
            let mark: Float = Float(model.masterValue(cols[1][0]))
            MasterIndicator.draw(ctx, size, d.comp, bypass: bypass, grMax: 18, mark: mark, now: now, theme: theme)
        case MasterScope.clip:
            let mark: Float = Float(model.masterValue(cols[2][1]))
            MasterIndicator.draw(ctx, size, d.clip, bypass: bypass, grMax: 12, mark: mark, now: now, theme: theme)
        default:
            let mark: Float = Float(model.masterValue(cols[3][1]))
            MasterIndicator.draw(ctx, size, d.lim, bypass: bypass, grMax: 12, mark: mark, now: now, theme: theme)
        }
    }
}

/// Дисплей уровня за 4 с (LEVEL компрессора, дисплей лимитера): столбцы истории рисует draw; линия параметра line
/// (THRESHOLD, CEILING) тянется пальцем (±22 px, приоритет над FREEZE), тап мимо линии — FREEZE.
struct LevelPlot: View {
    let model: AppModel
    let tele: DynTele
    let hist: TeleHistory
    let line: ParamDef
    let now: Double
    /// Жёлтая рамка дисплея, пока линию меняют (у лимитера — как в вебе; у LEVEL компрессора нет).
    var lit: Bool = true
    let draw: (GraphicsContext, CGSize, TeleHistory.Columns) -> Void
    @State private var touching: Bool = false
    @State private var lineStart: Double? = nil
    @State private var moved: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let cols: Int = max(1, Int(size.width))
                let c: TeleHistory.Columns = hist.columns(tele, cols: cols, now: now)
                draw(ctx, size, c)
            }
            .contentShape(Rectangle())
            .gesture(drag(geo.size.height))
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
        .overlay { if lit { HotFrame(model: model, id: line.id) } }
    }

    private func drag(_ h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !touching {
                    touching = true
                    moved = false
                    let v: Double = model.masterValue(line)
                    let cy: CGFloat = MasterDraw.y(v, h)
                    if abs(g.startLocation.y - cy) <= MasterDraw.lineHit {
                        lineStart = v
                        model.beginGesture()
                        model.masterHot.hold(line.id)
                    } else {
                        lineStart = nil
                    }
                }
                if abs(g.translation.height) > 6 { moved = true }
                guard let v0 = lineStart, h > 0 else { return }
                // Линия идёт за пальцем по шкале дисплея.
                let d: Double = Double(g.translation.height / h * MasterDraw.scale)
                model.setMaster(line, v0 - d)
            }
            .onEnded { _ in
                if lineStart != nil {
                    model.masterHot.release(line.id)
                    model.endGesture()
                } else if !moved {
                    hist.setFrozen(!hist.frozen, tele)
                }
                touching = false
                lineStart = nil
            }
    }
}
