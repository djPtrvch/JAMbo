import SwiftUI

/// Окно сэмпла (левая колонка, как sample.ts веба): имя, определённая высота и ST/M, форма волны сэмпла выбранной
/// дорожки (стерео — L и R), Start и End затемняют отрезанное, полосы воспроизведения звучащих нот.
/// У синта — окно синта (SynthInfo: иконка движка, имя, ручки 1.1–1.3).
/// Тап — меню звука (с зажатым шагом — звук этих шагов); удержание 0,5 с (без зажатого шага, не у синта) — редактор.
/// MIX — заголовок MIXER (● MASTER — под окном, LeftColumn); MST — индикация мастера (MasterIndicator).
struct SampleWindow: View {
    let model: AppModel
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var heldOpen: Bool = false
    @State private var downY: CGFloat? = nil
    @State private var cache = PeakCache()
    @Environment(\.theme) private var theme

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            // При MST касания — блокам индикации (тап — окно модуля), общий жест окна выключен.
            .gesture(press, including: model.channel == .master ? .subviews : .all)
    }

    @ViewBuilder
    private var content: some View {
        switch model.channel {
        case .track: trackView
        case .mix: mixView
        case .master: MasterIndicator(model: model)
        }
    }

    @ViewBuilder
    private var trackView: some View {
        if model.modPreview {
            ModPreview(model: model)
        } else if let e = SynthKey.engine(model.shownSound) {
            SynthInfo(model: model, engine: e)
        } else {
            sampleView
        }
    }

    private var sampleView: some View {
        let key: String = model.shownSound
        let data: SampleData? = model.sample(key)
        let _ = model.samplesVersion
        return VStack(alignment: .leading, spacing: 4) {
            SoundTitle(main: key.isEmpty ? "No sample" : model.sampleName(key), detail: detail(key, data))
            WaveStrip(model: model, key: key, data: data, cache: cache)
            Text("\(model.track.name) · tap to choose sound")
                .font(.system(size: 10))
                .foregroundStyle(theme.dim)
                .lineLimit(1)
        }
        .padding(8)
    }

    /// После имени сэмпла: нота и ST/M.
    private func detail(_ key: String, _ data: SampleData?) -> String? {
        if key.isEmpty { return nil }
        let root: String = model.sampleRoot(key).map { Params.noteName($0) } ?? "—"
        let ch: String = data.map { $0.channels == 2 ? "ST" : "M" } ?? ""
        return ch.isEmpty ? root : "\(root) · \(ch)"
    }

    private var mixView: some View {
        VStack(spacing: 8) {
            Text("MIXER").font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(theme.dim)
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    /// Тап — меню звука; удержание без движения — редактор (у дорожки с сэмплом или без звука).
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if downY == nil {
                    downY = g.startLocation.y
                    begin()
                }
                if abs(g.translation.height) > 10 { holdTask?.cancel() }
            }
            .onEnded { g in
                holdTask?.cancel()
                downY = nil
                if heldOpen {
                    heldOpen = false
                    return
                }
                if abs(g.translation.height) > 10 { return }
                model.ensureAudio()
                model.openSoundMenu()
            }
    }

    private func begin() {
        heldOpen = false
        holdTask?.cancel()
        guard model.channel == .track, model.heldSteps.isEmpty, SynthKey.engine(model.track.sample) == nil else { return }
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            heldOpen = true
            model.openEditor()
        }
    }
}

/// Форма волны окна сэмпла: огибающая (по 100 столбцов на канал), отрезанное Start/End затемнено, полосы
/// воспроизведения — жёлтые линии (тают за 1,2 с), пока звучат голоса.
struct WaveStrip: View {
    let model: AppModel
    let key: String
    let data: SampleData?
    let cache: PeakCache
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.headCount == 0)) { _ in
            canvas
        }
    }

    private var canvas: some View {
        let lanes: [[Float]] = data.map { cache.small($0, key: key) } ?? []
        let p = model.track.params
        let start: Double = (p["start"] ?? 0) / 100
        let end: Double = max(start, (p["end"] ?? 100) / 100)
        let heads = model.playheads(track: model.selectedTrack, key: key)
        let ink: Color = theme.text
        let accent: Color = theme.accent
        let scrim: Color = theme.bg.opacity(0.6)
        return Canvas { ctx, size in
            WaveStrip.draw(ctx, size, lanes, ink)
            if !lanes.isEmpty {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width * start, height: size.height)), with: .color(scrim))
                let x1: CGFloat = size.width * end
                ctx.fill(Path(CGRect(x: x1, y: 0, width: size.width - x1, height: size.height)), with: .color(scrim))
            }
            for h in heads {
                let x: CGFloat = size.width * h.f
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(accent.opacity(h.a)))
            }
        }
    }

    /// Огибающая — сплошная фигура (верхний край слева направо, нижний обратно): тонкие штрихи с зазорами
    /// давали рябь (муар).
    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ lanes: [[Float]], _ ink: Color) {
        if lanes.isEmpty { return }
        let laneH: CGFloat = size.height / CGFloat(lanes.count)
        var path = Path()
        for (li, lane) in lanes.enumerated() {
            let mid: CGFloat = laneH * (CGFloat(li) + 0.5)
            let amp: CGFloat = laneH / 2 * 0.9
            let n: Int = lane.count
            if n == 0 { continue }
            let dx: CGFloat = size.width / CGFloat(n)
            path.move(to: CGPoint(x: 0, y: mid))
            for (i, v) in lane.enumerated() {
                let h: CGFloat = max(0.5, CGFloat(v) * amp)
                path.addLine(to: CGPoint(x: CGFloat(i) * dx, y: mid - h))
                path.addLine(to: CGPoint(x: CGFloat(i + 1) * dx, y: mid - h))
            }
            path.addLine(to: CGPoint(x: size.width, y: mid))
            var i: Int = n - 1
            while i >= 0 {
                let h: CGFloat = max(0.5, CGFloat(lane[i]) * amp)
                path.addLine(to: CGPoint(x: CGFloat(i + 1) * dx, y: mid + h))
                path.addLine(to: CGPoint(x: CGFloat(i) * dx, y: mid + h))
                i -= 1
            }
            path.closeSubpath()
        }
        ctx.fill(path, with: .color(ink))
    }
}

/// Огибающие сэмплов для рисования (кэш: пересчёт только при смене сэмпла, ширины или окна масштаба).
final class PeakCache {
    private var smallKey: String = ""
    private var smallLanes: [[Float]] = []
    private var bigSig: String = ""
    private var bigLanes: [[(Float, Float)]] = []

    /// Окно сэмпла: 100 столбцов на канал, пик по модулю.
    func small(_ s: SampleData, key: String) -> [[Float]] {
        let sig = "\(key)|\(s.frames)"
        if sig == smallKey { return smallLanes }
        smallKey = sig
        smallLanes = (0..<s.channels).map { c in
            SampleEdit.peaks(s, channel: c, from: 0, to: Double(s.frames), n: 160).map { max(abs($0.0), abs($0.1)) }
        }
        return smallLanes
    }

    /// Редактор: w столбцов на канал в окне a…a+span (доли длины) — наименьшее и наибольшее значение.
    func big(_ s: SampleData, key: String, width w: Int, a: Double, span: Double) -> [[(Float, Float)]] {
        let sig = "\(key)|\(s.frames)|\(w)|\(a)|\(span)"
        if sig == bigSig { return bigLanes }
        bigSig = sig
        let f = Double(s.frames)
        bigLanes = (0..<s.channels).map { c in
            SampleEdit.peaks(s, channel: c, from: a * f, to: (a + span) * f, n: max(1, w))
        }
        return bigLanes
    }
}
