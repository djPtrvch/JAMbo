import SwiftUI

/// Окно сэмпла (левая колонка): имя, форма волны сэмпла выбранной дорожки (стерео — L и R; Start и End затемняют
/// отрезанное, полосы воспроизведения звучащих нот), под ней определённая высота.
/// У синта — окно синта (SynthInfo: иконка движка, имя, ручки 1.1–1.3).
/// Тап — меню звука (с зажатым шагом — звук этих шагов); удержание 0,5 с (без зажатого шага, не у синта) — редактор.
/// MIX — полосы уровня дорожек без заголовка (● MASTER — под окном, LeftColumn; панда убрана 7.11);
/// MST — индикация мастера (MasterIndicator).
struct SampleWindow: View {
    let model: AppModel
    @State private var holdTask: LaterTask? = nil
    @State private var heldOpen: Bool = false
    @State private var downY: CGFloat? = nil
    @State private var cache = PeakCache()

    var body: some View {
        content
            .tile(theme.panel)
            .contentShape(Rectangle())
            // При MST касания — блокам индикации (тап — окно модуля), общий жест окна выключен.
            .gesture(press, including: model.channel == .master ? .subviews : .all)
    }

    private var content: AnyView {
        switch model.channel {
        case .track:
            return AnyView(trackView)
        case .mix:
            return AnyView(mixView)
        case .master:
            return AnyView(MasterIndicator(model: model))
        }
    }

    /// Поверх превью — картинка FX, пока регулируют ручку FX (появляется и гаснет за 0,2 с).
    private var trackView: some View {
        ZStack {
            preview
            if model.fxPicture {
                FxPreview(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.fxPicture)
    }

    private var preview: AnyView {
        if model.modPreview {
            return AnyView(ModPreview(model: model))
        } else if let e = SynthKey.engine(model.shownSound) {
            return AnyView(SynthInfo(model: model, engine: e))
        } else {
            return AnyView(sampleView)
        }
    }

    /// Как окно синта: заголовок — только имя сэмпла (жёлтым), на месте иконки — форма волны, под ней строки
    /// «подпись · значение» (нота); подписи внизу окна нет.
    private var sampleView: some View {
        let key: String = model.shownSound
        let data: SampleData? = model.sample(key)
        let _ = model.samplesVersion
        return VStack(alignment: .leading, spacing: 4) {
            SoundTitle(main: key.isEmpty ? "No sample" : model.sampleName(key), detail: nil)
                .padding(.top, 6)
            // Три одинаковых промежутка (над волной, между волной и нотой, под нотой): волна ровно посередине
            // между заголовком и нотой.
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 8)
                WaveStrip(model: model, key: key, data: data, cache: cache)
                    .frame(maxWidth: .infinity, maxHeight: 144)
                Spacer(minLength: 8)
                rows(key)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        }
        .padding(8)
    }

    /// Под формой волны: нота сэмпла, в стиле строк ручек окна синта.
    @ViewBuilder
    private func rows(_ key: String) -> some View {
        if !key.isEmpty {
            let root: String = model.sampleRoot(key).map { Params.noteName($0) } ?? "—"
            Text("Note · \(root)")
                .font(.system(size: 11))
                .tracking(0.44)
                .foregroundStyle(theme.text)
                .lineLimit(1)
        }
    }

    /// Полосы уровня дорожек.
    private var mixView: AnyView {
        return AnyView(MixOverview(model: model).padding(10))
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
        holdTask = Later.run(0.5) {
            heldOpen = true
            model.openEditor()
        }
    }
}

/// Превью MIXER (решение пользователя): по полосе на дорожку, 16 одинаковых мест на всю ширину (дорожек меньше —
/// справа пусто); заглушённая — серая. Вид — кнопками слева внизу (MixMode, 10.11): LEVEL — уровень (стерео —
/// наибольший из L и R) снизу вверх по шкале метров (−60…0 dBFS), выше 0 dBFS — красный, пик-холд — линия цвета
/// текста; PAN — баланс сигнала (не ручка Pan): от средней линии вверх — вправо, вниз — влево, (R − L) / (R + L);
/// FREQ — диапазон частот дорожки (снизу 20 Гц, сверху 20 кГц, белая черта — пик); DYN — пик к RMS (0…30 dB).
/// Приглушение Duck не показывается.
struct MixOverview: View {
    let model: AppModel

    var body: some View {
        let mode: Int = model.mixMode
        return TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            MixOverviewBars(bars: bars, muted: muted, mode: mode, an: model.mixAn, now: tl.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// По дорожке: стерео L и R (уровень и пик-холд).
    private var bars: [[(level: Float, hold: Float)]] {
        let n: Int = min(Params.maxTracks, model.project.tracks.count)
        return (0..<n).map { t in model.meters.bars(t, stereo: true) }
    }

    private var muted: [Bool] {
        let n: Int = min(Params.maxTracks, model.project.tracks.count)
        return (0..<n).map { t in !model.project.audible(t) }
    }
}

struct MixOverviewBars: View {
    let bars: [[(level: Float, hold: Float)]]
    let muted: [Bool]
    let mode: Int
    let an: MixAnalysis
    let now: Date

    var body: some View {
        Canvas { ctx, size in
            if mode == MixMode.pan {
                drawPan(ctx, size)
            } else if mode == MixMode.freq {
                drawFreq(ctx, size)
            } else if mode == MixMode.dyn {
                drawDyn(ctx, size)
            } else {
                drawLevel(ctx, size)
            }
        }
    }

    /// Подпись шкалы справа (9 px, --dim) и линия сетки.
    private func mark(_ ctx: GraphicsContext, _ size: CGSize, _ y: CGFloat, _ s: String) {
        ctx.fill(Path(CGRect(x: 0, y: y.rounded(), width: size.width, height: 1)), with: .color(theme.grid))
        let t = ctx.resolve(Text(s).font(.system(size: 9)).foregroundColor(theme.dim))
        ctx.draw(t, at: CGPoint(x: size.width, y: y - 1), anchor: .bottomTrailing)
    }

    private func drawFreq(_ ctx: GraphicsContext, _ size: CGSize) {
        let h: CGFloat = size.height
        // Ось 20 Гц…20 кГц — три декады: 100 Гц, 1 кГц, 10 кГц.
        let marks: [(CGFloat, String)] = [(0.2330, "100"), (0.5663, "1k"), (0.8997, "10k")]
        for (f, s) in marks { mark(ctx, size, h - f * h, s) }
        let cell: CGFloat = size.width / 16
        let w: CGFloat = MeterBars.width
        for t in 0..<bars.count {
            guard let sp = an.span(t) else { continue }
            let x: CGFloat = cell * (CGFloat(t) + 0.5) - w / 2
            let mute: Bool = t < muted.count && muted[t]
            let c: Color = mute ? theme.muteGrey : theme.accent
            let y0: CGFloat = h - sp.hi * h
            let r = CGRect(x: x, y: y0, width: w, height: max(3, (sp.hi - sp.lo) * h))
            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(c))
            let py: CGFloat = h - sp.peak * h
            ctx.fill(Path(CGRect(x: x, y: py - 1, width: w, height: 2)), with: .color(theme.text))
        }
    }

    private func drawDyn(_ ctx: GraphicsContext, _ size: CGSize) {
        let h: CGFloat = size.height
        let k: CGFloat = h / 30
        for v in [6, 12, 18, 24] { mark(ctx, size, h - CGFloat(v) * k, "\(v)") }
        let cell: CGFloat = size.width / 16
        let w: CGFloat = MeterBars.width
        for t in 0..<bars.count {
            let c: Float = t < an.crest.count ? an.crest[t] : -1
            if c < 0 { continue }
            let bh: CGFloat = max(2, min(30, CGFloat(c)) * k)
            let x: CGFloat = cell * (CGFloat(t) + 0.5) - w / 2
            let mute: Bool = t < muted.count && muted[t]
            let col: Color = mute ? theme.muteGrey : theme.accent
            ctx.fill(Path(roundedRect: CGRect(x: x, y: h - bh, width: w, height: bh), cornerRadius: 3), with: .color(col))
        }
    }

    private func drawLevel(_ ctx: GraphicsContext, _ size: CGSize) {
        let cell: CGFloat = size.width / 16
        let w: CGFloat = MeterBars.width
        for (t, lr) in bars.enumerated() where lr.count == 2 {
            let lv: Float = max(lr[0].level, lr[1].level)
            let hold: Float = max(lr[0].hold, lr[1].hold)
            let x: CGFloat = cell * (CGFloat(t) + 0.5) - w / 2
            let mute: Bool = t < muted.count && muted[t]
            let f: CGFloat = MeterState.frac(lv)
            if f > 0 {
                let h: CGFloat = f * size.height
                let r = CGRect(x: x, y: size.height - h, width: w, height: h)
                let c: Color = mute ? theme.muteGrey : (lv >= MeterState.over ? theme.rec : theme.accent)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(c))
            }
            let hf: CGFloat = MeterState.frac(hold)
            if hf > 0.01 {
                let y: CGFloat = size.height - hf * size.height
                ctx.fill(Path(CGRect(x: x, y: max(0, y - 1), width: w, height: 2)), with: .color(theme.text))
            }
        }
    }

    private func drawPan(_ ctx: GraphicsContext, _ size: CGSize) {
        let cell: CGFloat = size.width / 16
        let w: CGFloat = MeterBars.width
        let cy: CGFloat = (size.height / 2).rounded()
        let half: CGFloat = size.height / 2
        ctx.fill(Path(CGRect(x: 0, y: cy, width: size.width, height: 1)), with: .color(theme.gridStrong))
        let fr = ctx.resolve(Text("R").font(.system(size: 9)).foregroundColor(theme.dim))
        let fl = ctx.resolve(Text("L").font(.system(size: 9)).foregroundColor(theme.dim))
        ctx.draw(fr, at: CGPoint(x: size.width, y: 0), anchor: .topTrailing)
        ctx.draw(fl, at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
        let floor: Float = 0.001
        for (t, lr) in bars.enumerated() where lr.count == 2 {
            let l: Float = lr[0].level, r: Float = lr[1].level
            if max(l, r) < floor { continue }
            let b: CGFloat = CGFloat((r - l) / (r + l))
            let x: CGFloat = cell * (CGFloat(t) + 0.5) - w / 2
            let mute: Bool = t < muted.count && muted[t]
            let c: Color = mute ? theme.muteGrey : theme.accent
            let h: CGFloat = max(2, abs(b) * half)
            let y: CGFloat = b >= 0 ? cy + 1 - h : cy
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 3), with: .color(c))
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

    /// Волна и затемнение Start/End рисуются только при их изменении; каждый кадр — лишь полосы воспроизведения,
    /// пока звучат голоса (S14c: вся волна перерисовывалась 60 раз в секунду всю игру).
    var body: some View {
        ZStack {
            wave
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.headCount == 0)) { _ in
                heads
            }
        }
    }

    private var wave: some View {
        let lanes: [[Float]] = data.map { cache.small($0, key: key) } ?? []
        let p = model.track.params
        let start: Double = (p["start"] ?? 0) / 100
        let end: Double = max(start, (p["end"] ?? 100) / 100)
        return WaveShape(lanes: lanes, start: start, end: end).equatable()
    }

    private var heads: some View {
        let heads = model.playheads(track: model.selectedTrack, key: key)
        let accent: Color = theme.accent
        return Canvas { ctx, size in
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

/// Волна окна сэмпла с затемнением Start/End — перерисовка только при смене сэмпла или Start/End (S14c).
struct WaveShape: View, Equatable {
    let lanes: [[Float]]
    let start: Double
    let end: Double

    static func == (a: WaveShape, b: WaveShape) -> Bool {
        return a.start == b.start && a.end == b.end && a.lanes == b.lanes
    }

    var body: some View {
        let ink: Color = theme.text
        let scrim: Color = theme.bg.opacity(0.6)
        let lanes: [[Float]] = self.lanes
        let start: Double = self.start
        let end: Double = self.end
        return Canvas { ctx, size in
            WaveStrip.draw(ctx, size, lanes, ink)
            if !lanes.isEmpty {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width * start, height: size.height)), with: .color(scrim))
                let x1: CGFloat = size.width * end
                ctx.fill(Path(CGRect(x: x1, y: 0, width: size.width - x1, height: size.height)), with: .color(scrim))
            }
        }
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
