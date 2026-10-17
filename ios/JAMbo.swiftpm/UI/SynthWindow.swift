import SwiftUI

/// Окно синта (на месте формы волны, как synth-info в sample.ts веба): заголовок MI · <движок>, живая иконка
/// движка (до 120 pt, ужимается по высоте окна), полное имя и ручки 1.1–1.3 «подпись · значение» (значение ручки
/// дорожки, как в вебе). Пока зажат шаг со своим звуком — его движок.
struct SynthInfo: View {
    let model: AppModel
    let engine: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let e: SynthEngine = SynthEngines.all[engine]
        return VStack(alignment: .leading, spacing: 4) {
            Text(e.jambo ? e.name : "MI · \(e.name)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 8) {
                if engine == Jambo.wtable {
                    SynthTableFrame(model: model, values: model.iconValues(engine))
                        .frame(maxWidth: .infinity, maxHeight: 120)
                } else {
                    SynthIcon(engine: engine, values: model.iconValues(engine))
                        .frame(maxWidth: .infinity, maxHeight: 120)
                }
                // У WTABLE вместо полного имени — имя таблицы дорожки.
                Text(engine == Jambo.wtable ? WavetableKey.name(model.track.table) : e.full)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accentText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                rows
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        }
        .padding(8)
    }

    private var rows: some View {
        let grid: [ParamDef] = Params.synthGrids[engine]
        let params: [String: Double] = model.track.params
        return VStack(alignment: .leading, spacing: 8) {
            ForEach([0, 4, 8], id: \.self) { slot in
                let p: ParamDef = grid[slot]
                Text("\(p.label) · \(p.format(params[p.id] ?? p.def))")
                    .font(.system(size: 11))
                    .tracking(0.44)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
        }
    }
}

/// Кадр таблицы WTABLE (вместо иконки): POSITION и WARP — как у иконки (p-lock, игра); таблица ещё строится — пусто.
struct SynthTableFrame: View {
    let model: AppModel
    let values: IconValues
    @Environment(\.theme) private var theme

    var body: some View {
        // wavetableSerial — перерисовка, когда таблица достроилась.
        let serial: Int = model.wavetableSerial
        let table: WtTable? = model.wavetables.ready[model.track.table]
        let els: [IconElement] = table.map { EngineIcons.tableFrame($0, position: values.h, warp: values.t) } ?? []
        let ink: Color = theme.icon
        return Canvas { ctx, size in
            _ = serial
            SynthIcon.draw(ctx, size, els, ink)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Иконка движка: элементы EngineIcons (поле 64×64) на Canvas, один цвет темы, линия 1,4 (в единицах поля).
struct SynthIcon: View {
    let engine: Int
    let values: IconValues
    @Environment(\.theme) private var theme

    var body: some View {
        let els: [IconElement] = EngineIcons.elements(engine, values)
        let ink: Color = theme.icon
        return Canvas { ctx, size in
            SynthIcon.draw(ctx, size, els, ink)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ els: [IconElement], _ ink: Color) {
        let side: CGFloat = min(size.width, size.height)
        let k: CGFloat = side / CGFloat(EngineIcons.size)
        var g = ctx
        g.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let width: CGFloat = CGFloat(EngineIcons.stroke) * k
        for e in els {
            let color: Color = ink.opacity(e.opacity ?? 1)
            if let text = e.text {
                let label = Text(text)
                    .font(.system(size: CGFloat(e.textSize) * k, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                // Подпись по центру, y — базовая линия (как text-anchor middle в SVG).
                g.draw(label, at: CGPoint(x: CGFloat(e.textX) * k, y: CGFloat(e.textY) * k), anchor: UnitPoint(x: 0.5, y: 0.8))
                continue
            }
            let path: Path = e.circle.map { c in circlePath(c, k) } ?? cmdPath(e.cmds, k)
            if e.fill {
                g.fill(path, with: .color(color))
            } else {
                let dash: [CGFloat] = e.dash ? [2 * k, 2.4 * k] : []
                g.stroke(path, with: .color(color),
                         style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
            }
        }
    }

    static func circlePath(_ c: (Double, Double, Double), _ k: CGFloat) -> Path {
        let r: CGFloat = CGFloat(c.2) * k
        return Path(ellipseIn: CGRect(x: CGFloat(c.0) * k - r, y: CGFloat(c.1) * k - r, width: 2 * r, height: 2 * r))
    }

    static func cmdPath(_ cmds: [IconCmd], _ k: CGFloat) -> Path {
        var path = Path()
        var x: CGFloat = 0
        var y: CGFloat = 0
        for c in cmds {
            switch c {
            case .move(let a, let b):
                x = CGFloat(a) * k
                y = CGFloat(b) * k
                path.move(to: CGPoint(x: x, y: y))
            case .line(let a, let b):
                x = CGFloat(a) * k
                y = CGFloat(b) * k
                path.addLine(to: CGPoint(x: x, y: y))
            case .hTo(let a):
                x = CGFloat(a) * k
                path.addLine(to: CGPoint(x: x, y: y))
            case .vTo(let b):
                y = CGFloat(b) * k
                path.addLine(to: CGPoint(x: x, y: y))
            case .hBy(let a):
                x += CGFloat(a) * k
                path.addLine(to: CGPoint(x: x, y: y))
            case .vBy(let b):
                y += CGFloat(b) * k
                path.addLine(to: CGPoint(x: x, y: y))
            case .arc(let r, _, let ex, let ey, let cx, let cy, let a0, let a1):
                // Экранные координаты (y вниз): рост угла — по часовой на экране, это clockwise: false.
                path.addArc(center: CGPoint(x: CGFloat(cx) * k, y: CGFloat(cy) * k), radius: CGFloat(r) * k,
                            startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
                x = CGFloat(ex) * k
                y = CGFloat(ey) * k
            case .arcBy(let rx, let ry, _, let sweep, let dx, _):
                // Половина эллипса: центр — середина хорды; sweep false — угол убывает (против часовой на экране).
                let cx: CGFloat = x + CGFloat(dx) * k / 2
                let a0: Double = dx > 0 ? Double.pi : 0
                let a1: Double = sweep ? a0 + Double.pi : a0 - Double.pi
                for s in 1...24 {
                    let a: Double = a0 + (a1 - a0) * Double(s) / 24
                    path.addLine(to: CGPoint(x: cx + CGFloat(rx * cos(a)) * k, y: y + CGFloat(ry * sin(a)) * k))
                }
                x += CGFloat(dx) * k
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}
