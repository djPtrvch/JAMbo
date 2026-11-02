import SwiftUI

/// Дисплей WAVE окон COMP и CLIP (решение пользователя: один дисплей с волной вместо TRANSFER и LEVEL): история
/// за 4 с — волна, зеркальная от середины (пик кадра в dB: 0 dBFS — у кромок, −48 — на середине); вход — серым,
/// выход — цветом модуля поверх; GR — оранжевым от верхней кромки (шкала 48 dB на полвысоты), подписи пиков; линия
/// THRESHOLD (пунктир) или CEILING (2 px), с числом, — сверху и снизу, тянется пальцем; двойной тап мимо линии — FREEZE.
/// Поверх — кривая прежнего окна TRANSFER (решение пользователя: окно убрано, наклонная линия осталась): по ширине
/// вход −48…0 dB, по высоте выход в шкале волны, сверху и зеркально снизу; белая 1,5 px, при BYPASS — серая.
enum MasterWave {
    static let gridStep: Int = 12

    /// dB → y верхней (lower — нижней) половины на высоте h.
    static func y(_ db: Double, _ h: CGFloat, lower: Bool) -> CGFloat {
        let mid: CGFloat = h / 2
        let a: CGFloat = min(1, max(0, 1 + CGFloat(db) / MasterDraw.scale))
        return lower ? mid + a * mid : mid - a * mid
    }

    /// Сетка через 12 dB по обеим половинам, середина — ярче; подписи — у верхней половины.
    static func grid(_ ctx: GraphicsContext, _ size: CGSize, _ theme: Theme) {
        let h: CGFloat = size.height
        var db: Int = 0
        while CGFloat(-db) < MasterDraw.scale {
            for lower in [false, true] {
                let y: CGFloat = MasterWave.y(Double(db), h, lower: lower).rounded()
                let yy: CGFloat = lower ? y - 1 : y
                ctx.fill(Path(CGRect(x: 0, y: yy, width: size.width, height: 1)), with: .color(theme.line))
            }
            let s: String = db == 0 ? "0" : "\(db)"
            let t = ctx.resolve(Text(s).font(.system(size: 10)).foregroundColor(theme.dim))
            ctx.draw(t, at: CGPoint(x: 4, y: MasterWave.y(Double(db), h, lower: false) + 2), anchor: .topLeading)
            db -= gridStep
        }
        ctx.fill(Path(CGRect(x: 0, y: (h / 2).rounded(), width: size.width, height: 1)), with: .color(theme.dim.opacity(0.6)))
    }

    /// Волна по столбцам: замкнутая фигура от верхней огибающей к нижней.
    static func path(_ data: [Float], _ h: CGFloat) -> Path {
        var p = Path()
        let n: Int = data.count
        if n == 0 { return p }
        var x: Int = 0
        while x < n {
            let pt = CGPoint(x: CGFloat(x), y: y(Double(data[x]), h, lower: false))
            if x == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            x += 1
        }
        x = n - 1
        while x >= 0 {
            p.addLine(to: CGPoint(x: CGFloat(x), y: y(Double(data[x]), h, lower: true)))
            x -= 1
        }
        p.closeSubpath()
        return p
    }

    /// Кривая TRANSFER: вход (x) → выход (y) по обеим половинам, шаг 2 px.
    static func curvePath(_ size: CGSize, _ curve: (Double) -> Double) -> Path {
        var p = Path()
        let w: CGFloat = max(1, size.width)
        for lower in [false, true] {
            var x: CGFloat = 0
            var first: Bool = true
            while x <= w {
                let l: Double = Double(-MasterDraw.scale + x / w * MasterDraw.scale)
                let pt = CGPoint(x: x, y: y(curve(l), size.height, lower: lower))
                if first { p.move(to: pt) } else { p.addLine(to: pt) }
                first = false
                x += 2
            }
        }
        return p
    }

    /// Весь дисплей: сетка, вход, выход, GR, линия параметра, надписи.
    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ c: TeleHistory.Columns, out: Color, bypass: Bool,
                     line: Double, dashed: Bool, frozen: Bool, curve: (Double) -> Double, _ theme: Theme) {
        let h: CGFloat = size.height
        grid(ctx, size, theme)
        let inWave: Path = path(c.inDb, h)
        ctx.fill(inWave, with: .color(theme.dim.opacity(0.35)))
        ctx.stroke(inWave, with: .color(theme.dim), lineWidth: 1)
        let outWave: Path = path(c.outDb, h)
        ctx.fill(outWave, with: .color(out.opacity(0.3)))
        ctx.stroke(outWave, with: .color(out), lineWidth: 1.5)
        if !bypass {
            let half: CGSize = CGSize(width: size.width, height: h / 2)
            ctx.fill(MasterDraw.grPath(c.gr, h / 2), with: .color(theme.gr.opacity(0.25)))
            MasterDraw.grPeaks(ctx, c.gr, half, gapMs: 100, theme)
        }
        let cp: Path = curvePath(size, curve)
        ctx.stroke(cp, with: .color(bypass ? theme.dim : theme.text), lineWidth: 1.5)
        let top: CGFloat = y(line, h, lower: false)
        let bottom: CGFloat = y(line, h, lower: true)
        for ly in [top, bottom] {
            if dashed {
                MasterDraw.dashed(ctx, CGPoint(x: 0, y: ly), CGPoint(x: size.width, y: ly), theme)
            } else {
                ctx.fill(Path(CGRect(x: 0, y: ly.rounded() - 1, width: size.width, height: 2)), with: .color(theme.meterThr))
            }
        }
        let col: Color = theme.meterThr
        let t = ctx.resolve(Text(String(format: "%.1f", line)).font(.system(size: 11)).foregroundColor(col))
        let below: Bool = top <= 16
        ctx.draw(t, at: CGPoint(x: size.width - 6, y: below ? top + 3 : top - 3), anchor: below ? .topTrailing : .bottomTrailing)
        MasterDraw.title(ctx, "WAVE", size, theme)
        if frozen { MasterDraw.pauseLabel(ctx, "FREEZE", theme) }
    }
}
