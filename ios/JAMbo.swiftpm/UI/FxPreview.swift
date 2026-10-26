import SwiftUI

// Картинка FX в окне сэмпла (docs/ai/fx-eq.md «Анимация FX»): пока палец на ручке FX (или ручку FX крутят с MIDI),
// поверх превью сэмпла или синта — картинка её колонки: Reverb, Delay, Drive, Duck. Раскладка и поле — как у окна
// синта (SynthInfo): заголовок, поле 64×64 (до 144 pt, элементы в 4…60 × 8…56), линии толщиной иконок. Неподвижна,
// меняется только от ручек (кроме точки Duck). Цвета — как у иконок движков: звук — icon, второстепенное (контуры,
// серые копии, огибающая фильтра) — icon2. Геометрия — FxPicture (Core).

struct FxPreview: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    static let titles: [String] = ["REVERB", "DELAY", "DRIVE", "DUCK"]

    var body: some View {
        let col: Int = min(3, max(0, model.fxPicCol))
        return VStack(alignment: .leading, spacing: 4) {
            header(col)
                .padding(.top, 6)
            // Поле — на том же месте, что иконка движка: под ним место строк ручек окна синта (пустое).
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    picture(col)
                    if col < 3 { FxCutPic(cut: cut(col)).equatable() }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 144)
                .offset(y: 3)
                FxPreview.rowsSpace
                    .padding(.top, 14)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .allowsHitTesting(false)
    }

    /// Место четырёх строк ручек окна синта (та же высота, без текста).
    static var rowsSpace: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<4, id: \.self) { _ in Text(" ").font(.system(size: 11)) }
        }
        .hidden()
    }

    private func header(_ col: Int) -> some View {
        HStack(spacing: 4) {
            Text(FxPreview.titles[col])
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
            Spacer(minLength: 4)
            if col == 3 {
                Text(sourceName)
                    .font(.system(size: 11))
                    .tracking(0.44)
                    .foregroundStyle(theme.text)
            }
        }
        .lineLimit(1)
    }

    /// Источник Duck — имя дорожки, как на ручке SOURCE.
    private var sourceName: String {
        let i: Int = Int(model.fxShown("sc.source").rounded())
        let tracks = model.project.tracks
        return i >= 0 && i < tracks.count ? tracks[i].name : ""
    }

    @ViewBuilder
    private func picture(_ col: Int) -> some View {
        let m: AppModel = model
        switch col {
        case 0:
            FxReverbPic(r: FxPicture.reverb(size: m.fxShown("rev.size"), decay: m.fxShown("rev.decay"),
                                            tone: m.fxShown("rev.tone")))
                .equatable()
        case 1:
            FxDelayPic(echoes: FxPicture.delayEchoes(time: m.fxShown("dly.time"), synced: m.delaySynced,
                                                     feedback: m.fxShown("dly.feedback")),
                       spread: m.fxShown("dly.spread") / 100)
                .equatable()
        case 2:
            FxDrivePic(type: Int(m.fxShown("od.type").rounded()), drive: m.fxShown("od.drive"), tone: m.fxShown("od.tone"))
                .equatable()
        default:
            FxDuckPic(d: FxPicture.duck(attack: m.fxShown("sc.attack"), release: m.fxShown("sc.release"),
                                        curve: m.fxShown("sc.curve")))
        }
    }

    private func cut(_ col: Int) -> FxPicture.Cut? {
        switch col {
        case 0: return FxPicture.reverbCut(model.fxShown("rev.hpf"))
        case 1: return FxPicture.delayCut(model.fxShown("dly.filter"))
        default: return FxPicture.driveCut(model.fxShown("od.lowcut"))
        }
    }
}

/// Поле 64×64 по центру холста (как SynthIcon.draw): дальше рисуется в единицах поля.
enum FxField {
    static let size: CGFloat = 64
    static let stroke: CGFloat = 1.4
    static let x0: CGFloat = 4
    static let x1: CGFloat = 60
    static let top: CGFloat = 8
    static let bottom: CGFloat = 56

    static func begin(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let side: CGFloat = min(size.width, size.height)
        ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        ctx.scaleBy(x: side / FxField.size, y: side / FxField.size)
    }
}

/// Огибающая фильтра поверх картинки (частота слева направо, лог 20 Гц — 20 кГц; 0 dB — верх поля, −30 dB — низ):
/// отрезанное — серая полупрозрачная заливка над кривой, кривая — серой линией. Без среза — ничего.
struct FxCutPic: View, Equatable {
    let cut: FxPicture.Cut?
    @Environment(\.theme) private var theme

    static func == (a: FxCutPic, b: FxCutPic) -> Bool { return a.cut == b.cut }

    var body: some View {
        let ink2: Color = theme.icon2
        let cut: FxPicture.Cut? = self.cut
        return Canvas { ctx, size in
            guard let c = cut else { return }
            FxField.begin(&ctx, size)
            let pts = FxPicture.cutEnvelope(c)
            var line = Path()
            for (i, p) in pts.enumerated() {
                let pt = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            var area: Path = line
            area.addLine(to: CGPoint(x: FxField.x1, y: FxField.top))
            area.addLine(to: CGPoint(x: FxField.x0, y: FxField.top))
            area.closeSubpath()
            ctx.fill(area, with: .color(ink2.opacity(0.45)))
            ctx.stroke(line, with: .color(ink2), style: StrokeStyle(lineWidth: FxField.stroke, lineJoin: .round))
        }
    }
}

/// Reverb: полупрозрачный куб (изометрия), вокруг — контуры DECAY.
struct FxReverbPic: View, Equatable {
    let r: FxPicture.Reverb
    @Environment(\.theme) private var theme

    static func == (a: FxReverbPic, b: FxReverbPic) -> Bool { return a.r == b.r }

    var body: some View {
        let ink: Color = theme.icon
        let ink2: Color = theme.icon2
        let r: FxPicture.Reverb = self.r
        return Canvas { ctx, size in
            FxField.begin(&ctx, size)
            let c = CGPoint(x: 32, y: 32)
            // Радиус силуэта 6,4…16; контуры DECAY — до 6, шаг 0,7…1,9, крайний не дальше 27,5 (поле 4…60).
            let s: CGFloat = 32 * CGFloat(r.size)
            if r.contours > 0 {
                for k in 1...r.contours {
                    let rad: CGFloat = s + CGFloat(k) * CGFloat(r.spread) * 12
                    let a: Double = 1 - Double(k) / Double(r.contours + 1)
                    ctx.stroke(FxReverbPic.hexagon(c, rad), with: .color(ink2.opacity(a)), lineWidth: FxField.stroke * 0.7)
                }
            }
            FxReverbPic.cube(ctx, c, s, r.fill, ink)
        }
    }

    /// Вершина силуэта k (0 — верх, по часовой через 60°).
    static func corner(_ c: CGPoint, _ rad: CGFloat, _ k: Int) -> CGPoint {
        let a: Double = (Double(k) * 60 - 90) * Double.pi / 180
        return CGPoint(x: c.x + rad * CGFloat(cos(a)), y: c.y + rad * CGFloat(sin(a)))
    }

    static func hexagon(_ c: CGPoint, _ rad: CGFloat) -> Path {
        var p = Path()
        p.move(to: corner(c, rad, 0))
        for k in 1..<6 { p.addLine(to: corner(c, rad, k)) }
        p.closeSubpath()
        return p
    }

    /// Грани: верх (светлее), правая и левая (темнее), рёбра — линией.
    static func cube(_ ctx: GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ fill: Double, _ ink: Color) {
        let h: [CGPoint] = (0..<6).map { corner(c, s, $0) }
        let faces: [([CGPoint], Double)] = [
            ([h[5], h[0], h[1], c], 1.0),
            ([c, h[1], h[2], h[3]], 0.7),
            ([h[5], c, h[3], h[4]], 0.45),
        ]
        for (pts, k) in faces {
            var p = Path()
            p.addLines(pts)
            p.closeSubpath()
            ctx.fill(p, with: .color(ink.opacity(fill * k)))
            ctx.stroke(p, with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: FxField.stroke, lineJoin: .round))
        }
    }
}

/// Delay: серая риска удара у левого края, повторы — белые линии (ниже и тусклее по FEEDBACK); SPREAD — серые копии
/// повторов попеременно вверх (L) и вниз (R).
struct FxDelayPic: View, Equatable {
    let echoes: [FxPicture.Echo]
    let spread: Double
    @Environment(\.theme) private var theme

    static func == (a: FxDelayPic, b: FxDelayPic) -> Bool { return a.spread == b.spread && a.echoes == b.echoes }

    var body: some View {
        let ink: Color = theme.icon
        let ink2: Color = theme.icon2
        let echoes: [FxPicture.Echo] = self.echoes
        let spread: Double = self.spread
        return Canvas { ctx, size in
            FxField.begin(&ctx, size)
            let mid: CGFloat = 32
            let x0: CGFloat = FxField.x0 + 1
            let w: CGFloat = FxField.x1 - 1 - x0
            // Линия полной высоты — 32 (16…48); копии SPREAD — до ±8 (поле 8…56).
            let full: CGFloat = 32
            let bw: CGFloat = FxField.stroke * 1.4
            ctx.fill(Path(CGRect(x: FxField.x0, y: mid - 0.35, width: FxField.x1 - FxField.x0, height: 0.7)),
                     with: .color(ink2.opacity(0.6)))
            ctx.fill(Path(CGRect(x: x0 - bw / 2, y: mid - full / 2, width: bw, height: full)), with: .color(ink2))
            for e in echoes {
                let x: CGFloat = x0 + w * CGFloat(e.x)
                let hh: CGFloat = full * CGFloat(e.h)
                if spread > 0.005 {
                    let dy: CGFloat = CGFloat(e.side) * CGFloat(spread) * 8
                    let r = CGRect(x: x - bw / 2, y: mid - hh / 2 + dy, width: bw, height: hh)
                    ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: .color(ink2.opacity(e.a)))
                }
                let r = CGRect(x: x - bw / 2, y: mid - hh / 2, width: bw, height: hh)
                ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: .color(ink.opacity(e.a)))
            }
        }
    }
}

/// Drive: волна (синус через TYPE и DRIVE) с заливкой до средней линии, под ней — серый чистый синус; TONE —
/// непрозрачность волны.
struct FxDrivePic: View, Equatable {
    let type: Int
    let drive: Double
    let tone: Double
    @Environment(\.theme) private var theme

    static func == (a: FxDrivePic, b: FxDrivePic) -> Bool {
        return a.type == b.type && a.drive == b.drive && a.tone == b.tone
    }

    var body: some View {
        let ink: Color = theme.icon
        let ink2: Color = theme.icon2
        let wave: [Double] = FxPicture.driveWave(type: type, drive: drive)
        let clean: [Double] = FxPicture.cleanWave(FxPicture.drivePoints)
        let stepped: Bool = type >= 5
        let t: Double = min(1, max(0, tone / 100))
        return Canvas { ctx, size in
            FxField.begin(&ctx, size)
            let line: Path = FxDrivePic.curve(wave, stepped)
            var area: Path = line
            area.addLine(to: CGPoint(x: FxField.x1, y: 32))
            area.addLine(to: CGPoint(x: FxField.x0, y: 32))
            area.closeSubpath()
            ctx.fill(area, with: .color(ink.opacity(0.1 + 0.45 * t)))
            ctx.stroke(FxDrivePic.curve(clean, false), with: .color(ink2), lineWidth: FxField.stroke * 0.7)
            ctx.stroke(line, with: .color(ink.opacity(0.35 + 0.65 * t)),
                       style: StrokeStyle(lineWidth: FxField.stroke, lineJoin: .round))
        }
    }

    /// Кривая по отсчётам в поле: x 4…60, середина 32, ±24 (8…56); CRUSH — ступенями.
    static func curve(_ v: [Double], _ stepped: Bool) -> Path {
        var p = Path()
        let n: Int = v.count - 1
        if n < 1 { return p }
        let amp: CGFloat = 24
        let dx: CGFloat = (FxField.x1 - FxField.x0) / CGFloat(n)
        p.move(to: CGPoint(x: FxField.x0, y: 32 - CGFloat(v[0]) * amp))
        for i in 1...n {
            let x: CGFloat = FxField.x0 + CGFloat(i) * dx
            if stepped { p.addLine(to: CGPoint(x: x, y: 32 - CGFloat(v[i - 1]) * amp)) }
            p.addLine(to: CGPoint(x: x, y: 32 - CGFloat(v[i]) * amp))
        }
        return p
    }
}

/// Duck: огибающая громкости (вверху — 0 dB), по ней бежит точка.
struct FxDuckPic: View {
    let d: FxPicture.Duck

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            FxDuckFrame(d: d, dot: FxPicture.duckDot(tl.date.timeIntervalSinceReferenceDate))
        }
    }
}

struct FxDuckFrame: View {
    let d: FxPicture.Duck
    let dot: Double
    @Environment(\.theme) private var theme

    var body: some View {
        let ink: Color = theme.icon
        let d: FxPicture.Duck = self.d
        let dot: Double = self.dot
        return Canvas { ctx, size in
            FxField.begin(&ctx, size)
            let w: CGFloat = FxField.x1 - FxField.x0
            let hh: CGFloat = FxField.bottom - FxField.top
            let n: Int = 240
            var line = Path()
            for i in 0...n {
                let x: Double = Double(i) / Double(n)
                let y: CGFloat = FxField.top + hh * CGFloat(1 - FxPicture.duckVolume(d, x))
                let pt = CGPoint(x: FxField.x0 + w * CGFloat(x), y: y)
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            var area: Path = line
            area.addLine(to: CGPoint(x: FxField.x1, y: FxField.bottom))
            area.addLine(to: CGPoint(x: FxField.x0, y: FxField.bottom))
            area.closeSubpath()
            ctx.fill(area, with: .color(ink.opacity(0.18)))
            ctx.stroke(line, with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: FxField.stroke, lineJoin: .round))
            let px: CGFloat = FxField.x0 + w * CGFloat(dot)
            let py: CGFloat = FxField.top + hh * CGFloat(1 - FxPicture.duckVolume(d, dot))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 2.2, y: py - 2.2, width: 4.4, height: 4.4)), with: .color(ink))
        }
    }
}
