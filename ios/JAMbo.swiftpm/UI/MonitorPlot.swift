import SwiftUI

/// Кривые Headphone Monitor поверх поля EQ в окне коррекции наушников: белая (основная кривая EQ с точками) — профиль
/// наушников на 100 %; серая пунктиром — TRIM; жёлтая — RESULT: профиль · CORRECTION + TRIM (то, что звучит). Подписи —
/// в левом верхнем углу.
struct MonitorCurves: View {
    let model: AppModel
    let g: EqGeometry
    @Environment(\.theme) private var theme

    var body: some View {
        let n: Int = Int(g.size.width / 2) + 1
        let freqs: [Double] = (0..<n).map { min(24000, g.freq(CGFloat($0) * 2)) }
        let trim: [Double] = MonitorCurves.sum(MonitorCurves.trimBands(model.phonesTrim), freqs)
        let corr: [Double] = MonitorCurves.sum(MonitorCurves.scaled(model.phonesEq, model.monitor.strength), freqs)
        let result: [Double] = (0..<n).map { corr[$0] + trim[$0] }
        let on: Bool = model.phonesEq.on
        let pct: String = String(format: "%.0f %%", model.monitor.strength * 100)
        return Canvas { ctx, _ in
            stroke(ctx, trim, theme.dim, dash: [4, 4])
            stroke(ctx, result, theme.accent.opacity(on ? 1 : 0.35), dash: [])
            legend(ctx, "PROFILE 100 %", theme.text, 0)
            legend(ctx, "TRIM", theme.dim, 1)
            legend(ctx, "RESULT · CORRECTION " + pct, theme.accent, 2)
        }
        .allowsHitTesting(false)
    }

    /// Полосы профиля с CORRECTION (как MonitorDesign.correction: ±12 dB · s; срезы и notch — при s > 0).
    static func scaled(_ eq: Eq, _ s: Double) -> [EqBand] {
        if s <= 0 { return [] }
        var out: [EqBand] = []
        for case let b? in eq.bands where b.on {
            var c: EqBand = b
            if EqSpec.hasGain(b.type) { c.gain = max(-MonitorSpec.filterMax, min(MonitorSpec.filterMax, b.gain)) * s }
            out.append(c)
        }
        return out
    }

    static func trimBands(_ t: [Double]) -> [EqBand] {
        var out: [EqBand] = []
        for k in 0..<min(t.count, MonitorSpec.trimHz.count) where t[k] != 0 {
            out.append(EqBand(type: EqSpec.bell, freq: MonitorSpec.trimHz[k], gain: t[k], q: MonitorSpec.trimQ))
        }
        return out
    }

    static func sum(_ bands: [EqBand], _ freqs: [Double]) -> [Double] {
        var s = [Double](repeating: 0, count: freqs.count)
        for b in bands {
            let r: [Double] = EqCoeffs.response(b, hz: freqs)
            for i in 0..<freqs.count { s[i] += r[i] }
        }
        return s
    }

    private func stroke(_ ctx: GraphicsContext, _ db: [Double], _ color: Color, dash: [CGFloat]) {
        guard let first = db.first else { return }
        let lim: Double = EqGeometry.dbRange * 1.2
        var p = Path()
        p.move(to: CGPoint(x: 0, y: g.y(max(-lim, min(lim, first)))))
        for i in 1..<db.count { p.addLine(to: CGPoint(x: CGFloat(i) * 2, y: g.y(max(-lim, min(lim, db[i]))))) }
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: dash))
    }

    private func legend(_ ctx: GraphicsContext, _ s: String, _ color: Color, _ row: Int) {
        let y: CGFloat = 10 + CGFloat(row) * 14
        let line = Path { $0.move(to: CGPoint(x: 70, y: y)); $0.addLine(to: CGPoint(x: 86, y: y)) }
        ctx.stroke(line, with: .color(color), lineWidth: 2)
        let t: Text = Text(s).font(.system(size: 10, weight: .semibold)).foregroundColor(color)
        ctx.draw(t, at: CGPoint(x: 92, y: y), anchor: .leading)
    }
}

/// Миниатюра Crossfeed: голова и две колонки под углом ANGLE (каждая — на ±ANGLE от центра); линии к дальнему уху —
/// AMOUNT (насквозь не видны — Crossfeed выключен); подпись — угол.
struct MonitorSpeakers: View {
    let angle: Double
    let amount: Double
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { ctx, size in
            let head = CGPoint(x: size.width / 2, y: size.height - 16)
            let r: CGFloat = size.height - 30
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14)), with: .color(theme.dim))
            for side in [-1.0, 1.0] {
                let a: Double = side * angle * Double.pi / 180
                let sp = CGPoint(x: head.x + r * CGFloat(sin(a)), y: head.y - r * CGFloat(cos(a)))
                // К дальнему уху — Crossfeed.
                let far = CGPoint(x: head.x - CGFloat(side) * 7, y: head.y)
                let near = CGPoint(x: head.x + CGFloat(side) * 7, y: head.y)
                ctx.stroke(Path { $0.move(to: sp); $0.addLine(to: near) }, with: .color(theme.text.opacity(0.5)), lineWidth: 1)
                ctx.stroke(Path { $0.move(to: sp); $0.addLine(to: far) },
                           with: .color(theme.accent.opacity(amount)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                var box = ctx
                box.translateBy(x: sp.x, y: sp.y)
                box.rotate(by: .radians(a))
                box.fill(Path(roundedRect: CGRect(x: -6, y: -8, width: 12, height: 16), cornerRadius: 2), with: .color(theme.text))
            }
            let t: Text = Text(String(format: "%.0f°", angle)).font(.system(size: 10, weight: .semibold)).foregroundColor(theme.dim)
            ctx.draw(t, at: CGPoint(x: size.width / 2, y: size.height - 2), anchor: .bottom)
        }
        .frame(width: 110, height: 84)
        .allowsHitTesting(false)
    }
}
