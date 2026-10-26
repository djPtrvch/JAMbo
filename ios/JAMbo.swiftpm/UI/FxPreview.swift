import SwiftUI

// Картинка FX в окне сэмпла (docs/ai/fx-eq.md «Анимация FX»): пока палец на ручке FX (или ручку FX крутят с MIDI),
// поверх превью сэмпла или синта — картинка её колонки: Reverb, Delay, Drive, Duck. Неподвижна, меняется только от
// ручек (кроме точки Duck). Цвета — как у иконок движков: звук — icon, второстепенное (контуры, серые копии, фильтр) —
// icon2. Геометрия — FxPicture (Core).

struct FxPreview: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    static let titles: [String] = ["REVERB", "DELAY", "DRIVE", "DUCK"]

    var body: some View {
        let col: Int = min(3, max(0, model.fxPicCol))
        return VStack(alignment: .leading, spacing: 8) {
            header(col)
            picture(col)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if col < 3 {
                FxFilterStrip(cut: cut(col))
                    .equatable()
                    .frame(height: 12)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .allowsHitTesting(false)
    }

    private func header(_ col: Int) -> some View {
        HStack(spacing: 4) {
            Text(FxPreview.titles[col]).foregroundStyle(theme.dim)
            Spacer(minLength: 4)
            if col == 3 { Text(sourceName).foregroundStyle(theme.text) }
        }
        .font(.system(size: 10))
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

/// Полоса фильтра (лог 20 Гц — 20 кГц): срез НЧ — заливка слева до частоты, срез ВЧ — справа; край — скатом.
struct FxFilterStrip: View, Equatable {
    let cut: FxPicture.Cut?
    @Environment(\.theme) private var theme

    static func == (a: FxFilterStrip, b: FxFilterStrip) -> Bool { return a.cut == b.cut }

    var body: some View {
        let track: Color = theme.meterTrack
        let ink: Color = theme.icon2
        let cut: FxPicture.Cut? = self.cut
        return Canvas { ctx, size in
            let w: CGFloat = size.width
            let h: CGFloat = size.height
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 3), with: .color(track))
            guard let c = cut else { return }
            let xc: CGFloat = w * CGFloat(c.x)
            let ramp: CGFloat = w * 0.06
            var p = Path()
            if c.low {
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: max(0, xc - ramp), y: 0))
                p.addLine(to: CGPoint(x: xc, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
            } else {
                p.move(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: min(w, xc + ramp), y: 0))
                p.addLine(to: CGPoint(x: xc, y: h))
                p.addLine(to: CGPoint(x: w, y: h))
            }
            p.closeSubpath()
            ctx.clip(to: Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 3))
            ctx.fill(p, with: .color(ink.opacity(0.9)))
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
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let m: CGFloat = min(size.width, size.height)
            let s: CGFloat = m * CGFloat(r.size) / 2
            // Контуры DECAY: шестиугольник силуэта куба, бледнеют наружу.
            if r.contours > 0 {
                for k in 1...r.contours {
                    let rad: CGFloat = s + CGFloat(k) * CGFloat(r.spread) * m * 0.25
                    let a: Double = 1 - Double(k) / Double(r.contours + 1)
                    ctx.stroke(FxReverbPic.hexagon(c, rad), with: .color(ink2.opacity(a)), lineWidth: 1)
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
            ctx.stroke(p, with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
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
            let mid: CGFloat = size.height / 2
            let pad: CGFloat = 4
            let w: CGFloat = size.width - 2 * pad
            let full: CGFloat = size.height * 0.62
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(ink2.opacity(0.6)))
            ctx.fill(Path(CGRect(x: pad - 1, y: mid - full / 2, width: 2, height: full)), with: .color(ink2))
            for e in echoes {
                let x: CGFloat = pad + w * CGFloat(e.x)
                let hh: CGFloat = full * CGFloat(e.h)
                if spread > 0.005 {
                    let dy: CGFloat = CGFloat(e.side) * CGFloat(spread) * size.height * 0.19
                    let r = CGRect(x: x - 1.5, y: mid - hh / 2 + dy, width: 3, height: hh)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(ink2.opacity(e.a)))
                }
                let r = CGRect(x: x - 1.5, y: mid - hh / 2, width: 3, height: hh)
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(ink.opacity(e.a)))
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
            let mid: CGFloat = size.height / 2
            let amp: CGFloat = size.height * 0.45
            let line: Path = FxDrivePic.curve(wave, size, mid, amp, stepped)
            var area: Path = line
            area.addLine(to: CGPoint(x: size.width, y: mid))
            area.addLine(to: CGPoint(x: 0, y: mid))
            area.closeSubpath()
            ctx.fill(area, with: .color(ink.opacity(0.1 + 0.45 * t)))
            ctx.stroke(FxDrivePic.curve(clean, size, mid, amp, false), with: .color(ink2), lineWidth: 1)
            ctx.stroke(line, with: .color(ink.opacity(0.35 + 0.65 * t)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }

    /// Кривая по отсчётам (CRUSH — ступенями).
    static func curve(_ v: [Double], _ size: CGSize, _ mid: CGFloat, _ amp: CGFloat, _ stepped: Bool) -> Path {
        var p = Path()
        let n: Int = v.count - 1
        if n < 1 { return p }
        let dx: CGFloat = size.width / CGFloat(n)
        p.move(to: CGPoint(x: 0, y: mid - CGFloat(v[0]) * amp))
        for i in 1...n {
            let x: CGFloat = CGFloat(i) * dx
            let y: CGFloat = mid - CGFloat(v[i]) * amp
            if stepped { p.addLine(to: CGPoint(x: x, y: mid - CGFloat(v[i - 1]) * amp)) }
            p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }
}

/// Duck: огибающая громкости (вверху — 0 dB), по ней бежит точка.
struct FxDuckPic: View {
    let d: FxPicture.Duck
    @Environment(\.theme) private var theme

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
            let top: CGFloat = size.height * 0.12
            let hh: CGFloat = size.height * 0.76
            let n: Int = 240
            var line = Path()
            for i in 0...n {
                let x: Double = Double(i) / Double(n)
                let y: CGFloat = top + hh * CGFloat(1 - FxPicture.duckVolume(d, x))
                let pt = CGPoint(x: size.width * CGFloat(x), y: y)
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            var area: Path = line
            area.addLine(to: CGPoint(x: size.width, y: top + hh))
            area.addLine(to: CGPoint(x: 0, y: top + hh))
            area.closeSubpath()
            ctx.fill(area, with: .color(ink.opacity(0.18)))
            ctx.stroke(line, with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            let px: CGFloat = size.width * CGFloat(dot)
            let py: CGFloat = top + hh * CGFloat(1 - FxPicture.duckVolume(d, dot))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 4, y: py - 4, width: 8, height: 8)), with: .color(ink))
        }
    }
}
