import SwiftUI

// REC в редакторе сэмпла (S11e): кнопка, меню RECORD FROM, форма волны во время записи.

/// REC: красная точка, красный текст и окантовка; во время записи — красная, ■ и время; неактивная — серая.
struct SampleRecButton: View {
    let model: AppModel
    @State private var frame: CGRect = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        let rec = model.sampleRec
        let on: Bool = rec.take != nil
        let enabled: Bool = on || model.channel == .track
        let fg: Color = on ? .white : (enabled ? theme.rec : theme.off)
        return Button { model.tapRec(frame) } label: {
            HStack(spacing: 6) {
                if on {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 9, height: 9)
                    Text(Capture.time(Double(rec.seconds))).monospacedDigit()
                } else {
                    Circle().fill(fg).frame(width: 10, height: 10)
                    Text("REC")
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.rec : theme.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(enabled && !on ? theme.rec : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
    }
}

/// Меню RECORD FROM (под кнопкой REC): входы, дорожки (в два столбца), мастер, пояснение; тап мимо — закрыть.
struct RecSourceMenu: View {
    static let width: CGFloat = 320
    let model: AppModel
    let anchor: CGRect
    /// Низ меню — не ниже верха кнопок дорожек.
    let bottom: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let left: CGFloat = max(8, anchor.maxX - RecSourceMenu.width)
        let top: CGFloat = anchor.maxY + 4
        let room: CGFloat = max(160, bottom - top - 40)
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.sampleRec.menu = nil }
            VStack(alignment: .leading, spacing: 6) {
                MenuHead(title: "RECORD FROM")
                MenuScroll { items }.frame(height: min(room, need))
            }
            .padding(8)
            .frame(width: RecSourceMenu.width)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .offset(x: left, y: top)
        }
    }

    /// Высота содержимого: подписи, входы, ряды дорожек (по 40 и зазор 4), MASTER, пояснение.
    private var need: CGFloat {
        let ports: CGFloat = CGFloat(model.sampleRec.ports.count)
        let rows: CGFloat = CGFloat((model.project.tracks.count + 1) / 2)
        let labels: CGFloat = 3 * 20
        let hint: CGFloat = InputCapture.granted ? 0 : 40
        return labels + ports * 46 + rows * 44 + 6 + 46 + 64 + hint
    }

    private var items: some View {
        let ports: [InputPort] = model.sampleRec.ports
        let names: [String] = model.project.tracks.map { $0.name }
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 2)
        return VStack(alignment: .leading, spacing: 6) {
            label("INPUT")
            ForEach(ports) { p in
                MenuItem(title: p.label) { model.beginRec(.input(uid: p.uid), name: p.name) }
            }
            if !InputCapture.granted {
                SettingsNote(text: "USB devices and audio interfaces appear here after access to the input is allowed.")
            }
            label("TRACK")
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(0..<names.count, id: \.self) { i in
                    MenuItem(title: names[i]) { model.beginRec(.channel(i), name: names[i]) }
                }
            }
            label("MASTER")
            MenuItem(title: "MASTER") { model.beginRec(.channel(StemRing.master), name: "MASTER") }
            SettingsNote(text: "Recording stops by tapping REC again or after \(Capture.maxSeconds) s. "
                + "Tracks are recorded after their own processing, the master after the master effects.")
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 9)).tracking(0.9).foregroundStyle(theme.dim).padding(.top, 2)
    }
}

/// Форма волны во время записи: пики по 128 отсчётов, L сверху, R снизу; по ширине — записанное (не меньше 5 с);
/// красная линия — текущее место.
struct RecordingPlot: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let p: RecPeaks = model.sampleRec.peaks
        let ink: Color = theme.text
        let line: Color = theme.line
        let red: Color = theme.rec
        return Canvas { ctx, size in
            RecordingPlot.draw(ctx, size, p, ink: ink, line: line, red: red)
        }
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ p: RecPeaks, ink: Color, line: Color, red: Color) {
        let top: CGFloat = SampleEditor.top
        let w: CGFloat = size.width
        let lh: CGFloat = (size.height - top) / 2
        let n: Int = p.count
        let span: Int = p.span
        let cols: Int = max(1, Int(w))
        for c in 0..<2 {
            let mid: CGFloat = top + lh * CGFloat(c) + lh / 2
            let amp: CGFloat = lh / 2 - 6
            ctx.fill(Path(CGRect(x: 0, y: mid, width: w, height: 1)), with: .color(line))
            var path = Path()
            var x = 0
            while x < cols {
                let k0: Int = x * span / cols
                if k0 >= n { break }
                let k1: Int = max(k0 + 1, (x + 1) * span / cols)
                let r = p.range(c, k0, k1)
                let y0: CGFloat = mid - CGFloat(r.hi) * amp
                let h: CGFloat = max(1, CGFloat(r.hi - r.lo) * amp)
                path.addRect(CGRect(x: CGFloat(x), y: y0, width: 1, height: h))
                x += 1
            }
            ctx.fill(path, with: .color(ink))
        }
        let rx: CGFloat = min(w - 2, CGFloat(n) / CGFloat(span) * w)
        ctx.fill(Path(CGRect(x: rx, y: top, width: 2, height: size.height - top)), with: .color(red))
    }
}
