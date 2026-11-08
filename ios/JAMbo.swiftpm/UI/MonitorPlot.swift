import SwiftUI

/// Кривые окна коррекции наушников поверх поля EQ: PHONE CURVE (профиль наушников, белая), CORRECT CURVE (своя
/// правка, жёлтая), RESULT (что звучит: профиль · CORRECTION + правка, серая пунктиром). Правится выбранная кривая
/// (PHONE CURVE / CORRECT CURVE в строке EQ): она толще и сплошная, у неё точки; другая — тоньше и пунктиром, поэтому
/// совпадающие кривые видны обе. Подписи — у левого края, выбранная — с точкой.
struct MonitorCurves: View {
    let model: AppModel
    let g: EqGeometry

    var body: some View {
        let n: Int = Int(g.size.width / 2) + 1
        let freqs: [Double] = (0..<n).map { min(24000, g.freq(CGFloat($0) * 2)) }
        let phone: Eq = model.phonesEq
        let s: Double = model.monitor.strength
        let profile: [Double] = MonitorCurves.sum(MonitorCurves.scaled(phone, 1), freqs)
        let scaled: [Double] = MonitorCurves.sum(MonitorCurves.scaled(phone, s), freqs)
        let correct: [Double] = MonitorCurves.sum(MonitorCurves.scaled(model.correctEq, 1), freqs)
        let result: [Double] = (0..<n).map { scaled[$0] + correct[$0] }
        let a: Double = phone.on ? 1 : 0.35
        let edit: Bool = model.monitor.editCorrect
        let pct: String = String(format: "%.0f %%", s * 100)
        return Canvas { ctx, _ in
            stroke(ctx, result, theme.dim.opacity(a), width: 1.5, dash: [2, 3])
            // Сначала невыбранная (тонкая, пунктир), сверху — выбранная.
            if edit {
                stroke(ctx, profile, theme.text.opacity(0.7 * a), width: 1.5, dash: [6, 4])
                stroke(ctx, correct, theme.accent.opacity(a), width: 2.5, dash: [])
            } else {
                stroke(ctx, correct, theme.accent.opacity(0.8 * a), width: 1.5, dash: [6, 4])
                stroke(ctx, profile, theme.text.opacity(a), width: 2.5, dash: [])
            }
            legend(ctx, "PHONE CURVE", theme.text, 0, !edit)
            legend(ctx, "CORRECT CURVE", theme.accent, 1, edit)
            legend(ctx, "RESULT · CORRECTION " + pct, theme.dim, 2, false)
        }
        .allowsHitTesting(false)
    }

    /// Включённые полосы с силой s (как MonitorDesign.correction: ±12 dB · s; срезы и notch — при s > 0).
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

    static func sum(_ bands: [EqBand], _ freqs: [Double]) -> [Double] {
        var s = [Double](repeating: 0, count: freqs.count)
        for b in bands {
            let r: [Double] = EqCoeffs.response(b, hz: freqs)
            for i in 0..<freqs.count { s[i] += r[i] }
        }
        return s
    }

    private func stroke(_ ctx: GraphicsContext, _ db: [Double], _ color: Color, width: CGFloat, dash: [CGFloat]) {
        guard let first = db.first else { return }
        let lim: Double = EqGeometry.dbRange * 1.2
        var p = Path()
        p.move(to: CGPoint(x: 0, y: g.y(max(-lim, min(lim, first)))))
        for i in 1..<db.count { p.addLine(to: CGPoint(x: CGFloat(i) * 2, y: g.y(max(-lim, min(lim, db[i]))))) }
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    /// Подпись у левого края: отрезок линии и имя; выбранная (правится) — с точкой справа.
    private func legend(_ ctx: GraphicsContext, _ s: String, _ color: Color, _ row: Int, _ sel: Bool) {
        let y: CGFloat = 12 + CGFloat(row) * 15
        let line = Path { $0.move(to: CGPoint(x: 8, y: y)); $0.addLine(to: CGPoint(x: 24, y: y)) }
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: row == 2 ? [2, 3] : []))
        let t: Text = Text(s).font(.system(size: 10, weight: sel ? .heavy : .semibold)).foregroundColor(color)
        ctx.draw(t, at: CGPoint(x: 30, y: y), anchor: .leading)
        if sel { ctx.fill(Path(ellipseIn: CGRect(x: 16 - 4, y: y - 4, width: 8, height: 8)), with: .color(color)) }
    }
}
