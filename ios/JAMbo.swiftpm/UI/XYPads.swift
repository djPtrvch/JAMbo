import SwiftUI

/// Раскладка площадок XY на поле сетки ручек: 4 квадрата 2×2; поле точки — весь квадрат.
enum XYLayout {
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
}

/// Четыре площадки XY выбранной дорожки вместо ручек (касания — у KnobGrid).
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

/// Площадка: точка — текущие значения ручек осей; с LFO/ENV — вторая, полупрозрачная, каждый кадр. Подписи поверх
/// поля: X — снизу по центру, Y — у левого края; без назначений — подсказка DOUBLE-TAP TO ASSIGN.
struct XYPadCell: View {
    let model: AppModel
    let pad: Int

    var body: some View {
        let live: Bool = model.xyModNorm(pad * 2) != nil || model.xyModNorm(pad * 2 + 1) != nil
        return ZStack {
            if live {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in field }
            } else {
                field
            }
            labels.allowsHitTesting(false)
        }
    }

    private var field: some View {
        let xs: [Double?] = [model.xyNorm(pad * 2), model.xyNorm(pad * 2 + 1)]
        let ms: [Double?] = [model.xyModNorm(pad * 2), model.xyModNorm(pad * 2 + 1)]
        return Canvas { ctx, size in
            XYPadCell.draw(ctx, size, xs, ms)
        }
    }

    private var labels: some View {
        let x: String = model.xyLabel(pad * 2)
        let y: String = model.xyLabel(pad * 2 + 1)
        return GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            if x.isEmpty && y.isEmpty {
                XYPadCell.caption("DOUBLE-TAP TO ASSIGN", theme.dim).position(x: w / 2, y: h / 2)
            } else {
                XYPadCell.caption("X  " + (x.isEmpty ? "—" : x), x.isEmpty ? theme.dim : theme.text)
                    .position(x: w / 2, y: h - 12)
                XYPadCell.caption("Y  " + (y.isEmpty ? "—" : y), y.isEmpty ? theme.dim : theme.text)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .position(x: 12, y: h / 2)
            }
        }
    }

    static func caption(_ s: String, _ c: Color) -> some View {
        return Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(c).lineLimit(1)
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ xs: [Double?], _ ms: [Double?]) {
        let f = CGRect(origin: .zero, size: size)
        ctx.fill(Path(roundedRect: f, cornerRadius: Layout.radius), with: .color(theme.panel))
        var cross = Path()
        cross.move(to: CGPoint(x: f.midX, y: f.minY))
        cross.addLine(to: CGPoint(x: f.midX, y: f.maxY))
        cross.move(to: CGPoint(x: f.minX, y: f.midY))
        cross.addLine(to: CGPoint(x: f.maxX, y: f.midY))
        ctx.stroke(cross, with: .color(theme.line), lineWidth: 1)
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

/// Меню площадки (двойной тап): ось X или Y, ниже 16 ручек выбранной дорожки (4×4, как на сетке) и NONE. Выбор X
/// переключает на Y, выбор Y закрывает меню; тап мимо — закрыть.
struct XYMenu: View {
    let model: AppModel
    let size: CGSize
    @State private var axisY: Bool = false

    static let width: CGFloat = 400
    static let height: CGFloat = 6 * 40 + 5 * 6 + 16

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let pad = model.xyMenu {
                Color.black.opacity(0.001)
                    .frame(width: size.width, height: size.height)
                    .onTapGesture { model.xyMenu = nil }
                AnyView(panel(pad).offset(offset(pad)))
            }
        }
        .onChange(of: model.xyMenu) { axisY = false }
    }

    private func panel(_ pad: Int) -> some View {
        let m: AppModel = model
        let k: Int = pad * 2 + (axisY ? 1 : 0)
        let cur: Int? = m.xySlot(k)
        let axes: [MenuChoice] = [
            MenuChoice(title: "X  " + m.xyLabel(pad * 2), current: !axisY) { axisY = false },
            MenuChoice(title: "Y  " + m.xyLabel(pad * 2 + 1), current: axisY) { axisY = true },
        ]
        let rows: [[MenuChoice]] = (0..<4).map { (r: Int) -> [MenuChoice] in
            (0..<4).map { (c: Int) -> MenuChoice in
                let s: Int = r * 4 + c
                let p: ParamDef? = m.param(s)
                return MenuChoice(title: p?.label ?? "", enabled: p != nil, current: cur == s) { pick(k, s) }
            }
        }
        let none: [MenuChoice] = [MenuChoice(title: "NONE", current: cur == nil) { pick(k, nil) }]
        return VStack(spacing: 6) {
            MenuChoiceButtons(items: axes)
            ForEach(0..<4, id: \.self) { r in MenuChoiceButtons(items: rows[r]) }
            MenuChoiceButtons(items: none)
        }
        .frame(width: XYMenu.width - 16)
        .menuPanel()
    }

    private func pick(_ k: Int, _ slot: Int?) {
        model.xyAssign(k, slot: slot)
        if k % 2 == 0 {
            axisY = true
        } else {
            model.xyMenu = nil
            axisY = false
        }
    }

    /// Над площадкой по центру, в пределах сетки.
    private func offset(_ pad: Int) -> CGSize {
        let r: CGRect = XYLayout.rect(pad, size)
        let x: CGFloat = min(max(0, r.midX - XYMenu.width / 2), max(0, size.width - XYMenu.width))
        let y: CGFloat = min(max(0, r.midY - XYMenu.height / 2), max(0, size.height - XYMenu.height))
        return CGSize(width: x, height: y)
    }
}
