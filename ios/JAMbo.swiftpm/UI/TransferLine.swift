import SwiftUI

/// Наклонные линии прежнего окна TRANSFER поверх дисплея LEVEL у COMP и CLIP (решение пользователя: окно TRANSFER
/// убрано, линии остались): по ширине дисплея — вход −48…0 dB, по высоте — выход в шкале LEVEL; диагональ 1:1
/// (серая), полоса колена (серая, прозрачнее), кривая (белая 1,5 px, при BYPASS серая), участок сжатия или среза —
/// оранжевый 2,5 px, живая точка 6 px.
enum TransferLine {
    static func x(_ db: Double, _ w: CGFloat) -> CGFloat {
        let v: CGFloat = (1 + CGFloat(db) / MasterDraw.scale) * w
        return min(w, max(0, v))
    }

    /// Кривая на отрезке входа a…b dB.
    static func path(_ size: CGSize, _ curve: (Double) -> Double, from a: Double, to b: Double) -> Path {
        var p = Path()
        let w: CGFloat = max(1, size.width)
        var px: CGFloat = x(a, w).rounded(.down)
        let end: CGFloat = x(b, w).rounded(.up)
        var first: Bool = true
        while px <= end {
            let l: Double = Double(-MasterDraw.scale + px / w * MasterDraw.scale)
            let pt = CGPoint(x: px, y: MasterDraw.y(curve(l), size.height))
            if first { p.move(to: pt) } else { p.addLine(to: pt) }
            first = false
            px += 1
        }
        return p
    }

    /// knee — полоса колена (вход, dB); seg — оранжевый участок; dot — вход живой точки.
    static func draw(_ ctx: GraphicsContext, _ size: CGSize, curve: (Double) -> Double, knee: (Double, Double),
                     seg: (Double, Double)?, dot: Double?, bypass: Bool, _ theme: Theme) {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let ka: CGFloat = x(knee.0, w)
        let kb: CGFloat = x(knee.1, w)
        if kb > ka { ctx.fill(Path(CGRect(x: ka, y: 0, width: kb - ka, height: h)), with: .color(theme.dim.opacity(0.18))) }
        var diag = Path()
        diag.move(to: CGPoint(x: 0, y: h))
        diag.addLine(to: CGPoint(x: w, y: 0))
        ctx.stroke(diag, with: .color(theme.dim), lineWidth: 1)
        let lo: Double = -Double(MasterDraw.scale)
        ctx.stroke(path(size, curve, from: lo, to: 0), with: .color(bypass ? theme.dim : theme.text), lineWidth: 1.5)
        if bypass { return }
        if let s = seg, s.1 > s.0 { ctx.stroke(path(size, curve, from: s.0, to: s.1), with: .color(theme.gr), lineWidth: 2.5) }
        if let d = dot, d > lo {
            let pt = CGPoint(x: x(d, w), y: MasterDraw.y(curve(d), h))
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)), with: .color(theme.text))
        }
    }
}
