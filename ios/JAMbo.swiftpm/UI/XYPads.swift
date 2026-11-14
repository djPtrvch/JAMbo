import SwiftUI

/// Раскладка площадок XY на поле сетки ручек: 4 квадрата 2×2; подпись X — полоса у нижнего края, Y — у левого.
enum XYLayout {
    static let strip: CGFloat = 24

    /// Площадка под точкой (0…3, ряд за рядом).
    static func pad(at p: CGPoint, _ size: CGSize) -> Int {
        let col: Int = p.x < size.width / 2 ? 0 : 1
        let row: Int = p.y < size.height / 2 ? 0 : 1
        return row * 2 + col
    }

    static func rect(_ pad: Int, _ size: CGSize) -> CGRect {
        let sp: CGFloat = KnobGrid.spacing
        let w: CGFloat = (size.width - sp) / 2
        let h: CGFloat = (size.height - sp) / 2
        let x: CGFloat = CGFloat(pad % 2) * (w + sp)
        let y: CGFloat = CGFloat(pad / 2) * (h + sp)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Подпись оси под точкой (0…7: площадка × 2, X — чётные); nil — поле площадки.
    static func label(at p: CGPoint, _ size: CGSize) -> Int? {
        let pd: Int = pad(at: p, size)
        let r: CGRect = rect(pd, size)
        if p.y > r.maxY - strip { return pd * 2 }
        if p.x < r.minX + strip { return pd * 2 + 1 }
        return nil
    }
}

/// Четыре площадки XY вместо ручек дорожки (касания — у KnobGrid).
struct XYPadsView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: KnobGrid.spacing) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: KnobGrid.spacing) {
                    ForEach(0..<2, id: \.self) { col in
                        XYPadCell(model: model, pad: row * 2 + col)
                    }
                }
            }
        }
    }
}

/// Площадка: точка — текущие значения осей (со знаком степени — по направлению пальца); с LFO/ENV — вторая,
/// полупрозрачная, каждый кадр. Подписи: X — снизу, Y — слева (не назначена — серая).
struct XYPadCell: View {
    let model: AppModel
    let pad: Int

    var body: some View {
        let live: Bool = model.xyModNorm(pad * 2) != nil || model.xyModNorm(pad * 2 + 1) != nil
        return ZStack(alignment: .bottomLeading) {
            if live {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in field }
            } else {
                field
            }
            labels
        }
    }

    private var field: some View {
        let xs: [Double?] = [dot(pad * 2, mod: false), dot(pad * 2 + 1, mod: false)]
        let ms: [Double?] = [dot(pad * 2, mod: true), dot(pad * 2 + 1, mod: true)]
        return Canvas { ctx, size in
            XYPadCell.draw(ctx, size, xs, ms)
        }
    }

    /// Положение точки по оси k (0…1, по направлению пальца); nil — ось не назначена.
    private func dot(_ k: Int, mod: Bool) -> Double? {
        guard let a = model.project.xyAxis(k) else { return nil }
        let n: Double? = mod ? model.xyModNorm(k) : model.xyNorm(k)
        guard let v = n else { return nil }
        return a.amount < 0 ? 1 - v : v
    }

    private var labels: some View {
        let x: String = model.xyLabel(pad * 2)
        let y: String = model.xyLabel(pad * 2 + 1)
        let xOn: Bool = model.project.xyAxis(pad * 2) != nil
        let yOn: Bool = model.project.xyAxis(pad * 2 + 1) != nil
        return GeometryReader { geo in
            let h: CGFloat = geo.size.height
            Text(x)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(xOn ? theme.text : theme.dim)
                .lineLimit(1)
                .frame(width: geo.size.width - XYLayout.strip * 2, height: XYLayout.strip)
                .position(x: geo.size.width / 2, y: h - XYLayout.strip / 2)
            Text(y)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(yOn ? theme.text : theme.dim)
                .lineLimit(1)
                .frame(width: h - XYLayout.strip * 2, height: XYLayout.strip)
                .rotationEffect(.degrees(-90))
                .position(x: XYLayout.strip / 2, y: h / 2)
        }
        .allowsHitTesting(false)
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ xs: [Double?], _ ms: [Double?]) {
        let s: CGFloat = XYLayout.strip
        let box = CGRect(origin: .zero, size: size)
        ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(theme.panel))
        // Поле точки — без полос подписей.
        let f = CGRect(x: s, y: 6, width: size.width - s - 6, height: size.height - s - 6)
        var cross = Path()
        cross.move(to: CGPoint(x: f.midX, y: f.minY))
        cross.addLine(to: CGPoint(x: f.midX, y: f.maxY))
        cross.move(to: CGPoint(x: f.minX, y: f.midY))
        cross.addLine(to: CGPoint(x: f.maxX, y: f.midY))
        ctx.stroke(cross, with: .color(theme.line), lineWidth: 1)
        ctx.stroke(Path(roundedRect: f, cornerRadius: 4), with: .color(theme.line), lineWidth: 1)
        if xs[0] == nil && xs[1] == nil { return }
        if ms[0] != nil || ms[1] != nil {
            let mp = XYPadCell.point(f, ms[0] ?? xs[0], ms[1] ?? xs[1])
            ctx.fill(Path(ellipseIn: CGRect(x: mp.x - 9, y: mp.y - 9, width: 18, height: 18)),
                     with: .color(theme.text.opacity(0.35)))
        }
        let p = XYPadCell.point(f, xs[0], xs[1])
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)), with: .color(theme.text))
    }

    /// Точка в поле f: ось без назначения — по середине.
    static func point(_ f: CGRect, _ x: Double?, _ y: Double?) -> CGPoint {
        let nx: CGFloat = CGFloat(x ?? 0.5)
        let ny: CGFloat = CGFloat(y ?? 0.5)
        return CGPoint(x: f.minX + nx * f.width, y: f.maxY - ny * f.height)
    }
}
