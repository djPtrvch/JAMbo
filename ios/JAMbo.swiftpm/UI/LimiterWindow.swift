import SwiftUI

/// Дисплей окна лимитера (limiter.ts веба): пик в dB за 4 с (справа новое), 60 кадров в секунду; справа блок LIM.
/// Слои: сетка; вход после INPUT — серая заливка с тонким контуром (выше 0 dBFS — светлая метка у кромки); выход —
/// красный контур и заливка ~20 %; GR — оранжевая заливка сверху; линия CEILING с числом — тянется пальцем (±22 px,
/// приоритет над FREEZE); подписи пиков GR; красная точка — выход выше CEILING больше чем на 0,1 dB. Тап — FREEZE.
struct LimiterDisplay: View {
    let model: AppModel
    @State private var hist = TeleHistory()
    /// Касание: значение CEILING в начале (линия) или nil — не линия; сдвинулся ли палец.
    @State private var touching: Bool = false
    @State private var lineStart: Double? = nil
    @State private var moved: Bool = false
    @Environment(\.theme) private var theme

    private var ceilingParam: ParamDef { return Params.masterColumns[3][1] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let now: Double = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: Layout.gap) {
                GeometryReader { geo in
                    Canvas { ctx, size in draw(ctx, size, now) }
                        .contentShape(Rectangle())
                        .gesture(drag(geo.size.height))
                }
                .background(theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(HotFrame(model: model, id: ceilingParam.id))
                DynBlock(model: model, module: MasterScope.lim, now: now)
                    .frame(width: 96)
            }
        }
    }

    private func drag(_ h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let p: ParamDef = ceilingParam
                if !touching {
                    touching = true
                    moved = false
                    let v: Double = model.masterValue(p)
                    let cy: CGFloat = MasterDraw.y(v, h)
                    if abs(g.startLocation.y - cy) <= MasterDraw.lineHit {
                        lineStart = v
                        model.beginGesture()
                        model.masterHot.hold(p.id)
                    } else {
                        lineStart = nil
                    }
                }
                if abs(g.translation.height) > 6 { moved = true }
                guard let v0 = lineStart, h > 0 else { return }
                // Линия идёт за пальцем по шкале дисплея.
                let d: Double = Double(g.translation.height / h * MasterDraw.scale)
                model.setMaster(p, v0 - d)
            }
            .onEnded { _ in
                if lineStart != nil {
                    model.masterHot.release(ceilingParam.id)
                    model.endGesture()
                } else if !moved {
                    hist.setFrozen(!hist.frozen, model.audio.core.master.limTele)
                }
                touching = false
                lineStart = nil
            }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ now: Double) {
        let h: CGFloat = size.height
        MasterDraw.grid(ctx, size, theme)
        let cols: Int = max(1, Int(size.width))
        let c: TeleHistory.Columns = hist.columns(model.audio.core.master.limTele, cols: cols, now: now)
        let bypass: Bool = model.project.limBypass
        // Вход после INPUT: серая заливка с тонким контуром; выше 0 dBFS — светлая метка у верхней кромки.
        let inFill: Path = MasterDraw.levelPath(c.inDb, h, closed: true)
        ctx.fill(inFill, with: .color(theme.dim.opacity(0.35)))
        ctx.stroke(MasterDraw.levelPath(c.inDb, h, closed: false), with: .color(theme.dim), lineWidth: 1)
        overMarks(ctx, c.inDb)
        if !bypass {
            // Выход — красный контур и заливка ~20 %; GR — оранжевая заливка сверху вниз.
            ctx.fill(MasterDraw.levelPath(c.outDb, h, closed: true), with: .color(theme.rec.opacity(0.2)))
            ctx.stroke(MasterDraw.levelPath(c.outDb, h, closed: false), with: .color(theme.rec), lineWidth: 1.5)
            ctx.fill(MasterDraw.grPath(c.gr, h), with: .color(theme.gr))
        }
        let ceil: Double = model.masterValue(ceilingParam)
        MasterDraw.line(ctx, ceil, size, theme)
        if !bypass {
            MasterDraw.grPeaks(ctx, c.gr, size, gapMs: 80, theme)
            overDots(ctx, c.outDb, ceil)
        }
        if hist.frozen { MasterDraw.pauseLabel(ctx, "FREEZE", theme) }
    }

    /// Вход выше 0 dBFS — светлая полоса 3 px у верхней кромки.
    private func overMarks(_ ctx: GraphicsContext, _ inDb: [Float]) {
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

    /// Выход выше CEILING больше чем на 0,1 dB — красная точка у верхней кромки.
    private func overDots(_ ctx: GraphicsContext, _ outDb: [Float], _ ceil: Double) {
        let lim: Float = Float(ceil + 0.1)
        var x: Int = 0
        while x < outDb.count {
            if outDb[x] > lim {
                let r = CGRect(x: CGFloat(x) - 3, y: 1, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: r), with: .color(theme.rec))
            }
            x += 1
        }
    }
}
