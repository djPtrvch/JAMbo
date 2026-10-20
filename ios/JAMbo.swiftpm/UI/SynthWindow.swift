import SwiftUI

/// Окно синта (на месте формы волны, как synth-info в sample.ts веба): заголовок — имя движка (у WTABLE — и имя
/// таблицы), живая иконка движка (до 120 pt, ужимается по высоте окна) и ручки 1.1–1.4 «подпись · значение»
/// (значение ручки дорожки, как в вебе). Пока зажат шаг со своим звуком — его движок.
struct SynthInfo: View {
    let model: AppModel
    let engine: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let e: SynthEngine? = SynthEngines.engine(engine)
        // У WTABLE после имени движка — имя таблицы дорожки.
        let table: String? = engine == Jambo.wtable ? SoundTitle.capitalized(WavetableKey.name(model.track.table)) : nil
        return VStack(alignment: .leading, spacing: 4) {
            SoundTitle(main: e?.name ?? "", detail: table)
            VStack(alignment: .leading, spacing: 8) {
                // Иконка чуть выше своего места; ручки под ней не сдвигаются.
                SynthIcon(model: model, engine: engine)
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .offset(y: -12)
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
            ForEach([0, 4, 8, 12], id: \.self) { slot in
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

/// Заголовок окна звука — один стиль у движков и сэмплов: main заглавными жёлтым, после тире detail цветом текста
/// (у WTABLE — имя таблицы, у сэмпла — нота и ST/M).
struct SoundTitle: View {
    let main: String
    let detail: String?
    @Environment(\.theme) private var theme

    var body: some View {
        var t: Text = Text(main.uppercased()).foregroundStyle(theme.accentText)
        if let d = detail, !d.isEmpty {
            t = t + Text(" — " + d).foregroundStyle(theme.text)
        }
        return t
            // Как подписи движков в меню звука.
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// «METAL» → «Metal»: первая буква заглавная, остальные малые.
    static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst().lowercased()
    }
}

/// Иконка движка: элементы EngineIcons (поле 64×64) на Canvas двумя цветами темы (icon — звук, icon2 — серый).
/// Ручки сглажены (~90 мс, как в прототипе превью); у ударных по удару дорожки — подсветка, бегущая слева направо.
/// У WTABLE — кадр таблицы дорожки (таблица ещё строится — пусто). Пока ничего не движется, кадры не идут.
struct SynthIcon: View {
    let model: AppModel
    let engine: Int
    @State private var motion = IconMotion()
    @State private var animating = false
    @State private var stopTask: Task<Void, Never>? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let target: IconValues = model.iconValues(engine)
        let drum: Bool = engine == Jambo.drum || (engine >= Jambo.snare && engine <= Jambo.perc)
        // Чтение flashing — подписка на удары; только у ударных.
        let hit: Bool = drum && model.live.flashing[model.selectedTrack]
        let frame: ((Double, Double) -> Double)? = tableSource
        // Кадры идут, пока сглаживание не дошло до значений ручек или идёт подсветка.
        let live: Bool = animating || motion.differs(target)
        let ink: Color = theme.icon
        let ink2: Color = theme.icon2
        return TimelineView(.animation(paused: !live)) { tl in
            Canvas { ctx, size in
                let now: Double = tl.date.timeIntervalSinceReferenceDate
                let v: IconValues = motion.step(target, now)
                let els: [IconElement] = SynthIcon.elements(engine, v, motion.hx(now, drum && live), frame)
                SynthIcon.draw(ctx, size, els, ink, ink2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: target) { run(0.6) }
        .onChange(of: hit) { _, on in
            if on {
                motion.hitAt = Date().timeIntervalSinceReferenceDate
                run(0.9)
            }
        }
    }

    /// Кадр таблицы WTABLE; wavetableSerial — перерисовка, когда таблица достроилась.
    private var tableSource: ((Double, Double) -> Double)? {
        guard engine == Jambo.wtable else { return nil }
        _ = model.wavetableSerial
        guard let tb: WtTable = model.wavetables.ready[model.track.table] else { return { _, _ in .nan } }
        return EngineIcons.tableFrame(tb)
    }

    /// Кадры идут seconds после последнего изменения (сглаживание и подсветка успевают закончиться).
    private func run(_ seconds: Double) {
        animating = true
        stopTask?.cancel()
        stopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            if !Task.isCancelled { animating = false }
        }
    }

    static func elements(_ engine: Int, _ v: IconValues, _ hx: Double?, _ frame: ((Double, Double) -> Double)?) -> [IconElement] {
        if let f = frame {
            // Таблица ещё строится (NaN) — пусто.
            return f(0, 0).isNaN ? [] : EngineIcons.wtableIcon(v, f)
        }
        return EngineIcons.elements(engine, v, hx: hx)
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ els: [IconElement], _ ink: Color, _ ink2: Color) {
        let side: CGFloat = min(size.width, size.height)
        let k: CGFloat = side / CGFloat(EngineIcons.size)
        var g = ctx
        g.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let width: CGFloat = CGFloat(EngineIcons.stroke) * k
        for e in els {
            let base: Color = e.ink == .secondary ? ink2 : ink
            let color: Color = base.opacity(e.opacity ?? 1)
            if let text = e.text {
                let label = Text(text)
                    .font(.system(size: CGFloat(e.textSize) * k, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                // Подпись по центру, y — базовая линия (как text-anchor middle в SVG).
                g.draw(label, at: CGPoint(x: CGFloat(e.textX) * k, y: CGFloat(e.textY) * k), anchor: UnitPoint(x: 0.5, y: 0.8))
                continue
            }
            if !e.rects.isEmpty {
                g.fill(rectsPath(e.rects, k), with: .color(color))
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

    /// Колонки одним путём: перекрытия не темнеют (ненулевое правило, все прямоугольники в одну сторону).
    static func rectsPath(_ rects: [IconRect], _ k: CGFloat) -> Path {
        var path = Path()
        for r in rects {
            path.addRect(CGRect(x: CGFloat(r.x) * k, y: CGFloat(r.y) * k, width: CGFloat(r.w) * k, height: CGFloat(r.h) * k))
        }
        return path
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

/// Сглаженные значения иконки (как k.v в прототипе: шаг 1 − exp(−dt / 0,09), dt не больше 0,05 с) и время удара.
/// Класс, а не @State-значение: меняется при рисовании Canvas без перерисовки вида.
final class IconMotion {
    private var shown: IconValues? = nil
    private var last: Double = 0
    var hitAt: Double = -100

    /// Сглаженное ещё не дошло до target.
    func differs(_ target: IconValues) -> Bool {
        return shown.map { $0 != target } ?? false
    }

    /// Следующее значение к target (первое — сразу target); почти дошло — ровно target.
    func step(_ target: IconValues, _ now: Double) -> IconValues {
        guard var s = shown else {
            shown = target
            last = now
            return target
        }
        let dt: Double = min(0.05, max(0, now - last))
        last = now
        let a: Double = 1 - exp(-dt / 0.09)
        s.h += (target.h - s.h) * a
        s.t += (target.t - s.t) * a
        s.m += (target.m - s.m) * a
        s.q += (target.q - s.q) * a
        s.d += (target.d - s.d) * a
        var far: Double = abs(target.h - s.h)
        far = max(far, abs(target.t - s.t))
        far = max(far, abs(target.m - s.m))
        far = max(far, abs(target.q - s.q))
        far = max(far, abs(target.d - s.d))
        if far < 0.0005 { s = target }
        shown = s
        return s
    }

    /// Центр подсветки удара (x на поле 64): 0,8 с слева направо после удара, потом nil.
    func hx(_ now: Double, _ on: Bool) -> Double? {
        let tau: Double = now - hitAt
        guard on, tau >= 0, tau < 0.85 else { return nil }
        let u: Double = min(1, tau / 0.8)
        return -10 + 84 * u * u * (3 - 2 * u)
    }
}
