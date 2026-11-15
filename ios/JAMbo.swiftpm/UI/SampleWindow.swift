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
/// справа пусто); заглушённая — серая. Вид — кнопками слева внизу (MixMode, 10.11): LEVEL — уровень (наибольший из
/// L и R) снизу вверх по шкале метров (−60…0 dBFS), выше 0 dBFS — красный, пик-холд — линия цвета текста; PAN —
/// баланс сигнала (не ручка Pan): от средней линии вверх — вправо, вниз — влево, (R − L) / (R + L); FREQ — диапазон
/// частот дорожки (снизу 20 Гц, сверху 20 кГц; красная черта с коротким градиентом — самая сильная частота).
/// LEVEL с LOUD (15.11): снизу сплошной слой до громкости по восприятию, выше до пика — полупрозрачный. MASK —
/// конфликты частот (ось FREQ): диапазон серый, поверх жёлтым — полосы, где мешают остальные, над ним номер того,
/// кто мешает больше всех. Приглушение Duck не показывается.
struct MixOverview: View {
    let model: AppModel

    var body: some View {
        let mode: Int = model.mixMode
        return TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            ScopeCanvas(now: tl.date) { ctx, size in MixOverview.draw(ctx, size, model, mode) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ model: AppModel, _ mode: Int) {
        let h: CGFloat = size.height
        let cy: CGFloat = (h / 2).rounded()
        // Сетка и подписи справа: PAN — R, L; FREQ — 100, 1k, 10k.
        if mode == MixMode.pan {
            ctx.fill(Path(CGRect(x: 0, y: cy, width: size.width, height: 1)), with: .color(theme.gridStrong))
            dimText(ctx, "R", CGPoint(x: size.width, y: 0), .topTrailing)
            dimText(ctx, "L", CGPoint(x: size.width, y: h), .bottomTrailing)
        } else if mode == MixMode.freq || mode == MixMode.mask {
            let names: [String] = ["100", "1k", "10k"]
            let ys: [CGFloat] = [0.2330, 0.5663, 0.8997]
            for k in 0..<3 {
                let y: CGFloat = (h - ys[k] * h).rounded()
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(theme.grid))
                dimText(ctx, names[k], CGPoint(x: size.width, y: y - 1), .bottomTrailing)
            }
        }
        let cell: CGFloat = size.width / 16
        let w: CGFloat = MeterBars.width
        let n: Int = min(Params.maxTracks, model.project.tracks.count)
        let m: MeterState = model.meters
        let an: MixAnalysis = model.mixAn
        if mode == MixMode.mask {
            drawMask(ctx, size, model, n)
            return
        }
        for t in 0..<n {
            let x: CGFloat = cell * (CGFloat(t) + 0.5) - w / 2
            let mute: Bool = !model.project.audible(t)
            let lr = m.bars(t, stereo: true)
            if lr.count < 2 { continue }
            let l: Float = lr[0].level, r: Float = lr[1].level
            var rect = CGRect.zero
            let col: Color = mute ? theme.muteGrey : theme.accent
            if mode == MixMode.pan {
                if max(l, r) < 0.001 { continue }
                let b: CGFloat = CGFloat((r - l) / (r + l))
                let bh: CGFloat = max(2, abs(b) * h / 2)
                rect = CGRect(x: x, y: b >= 0 ? cy + 1 - bh : cy, width: w, height: bh)
            } else if mode == MixMode.freq {
                guard let sp = an.span(t) else { continue }
                rect = CGRect(x: x, y: h - sp.hi * h, width: w, height: max(3, (sp.hi - sp.lo) * h))
                // Самая сильная частота — красная черта, от неё вверх и вниз — короткий градиент (решение пользователя).
                let shape = Path(roundedRect: rect, cornerRadius: 3)
                ctx.fill(shape, with: .color(col))
                if !mute {
                    let py: CGFloat = h - sp.peak * h
                    let g = Gradient(colors: [theme.rec.opacity(0), theme.rec, theme.rec.opacity(0)])
                    var c = ctx
                    c.clip(to: shape)
                    c.fill(Path(CGRect(x: x, y: py - 14, width: w, height: 28)),
                           with: .linearGradient(g, startPoint: CGPoint(x: x, y: py - 14), endPoint: CGPoint(x: x, y: py + 14)))
                    c.fill(Path(CGRect(x: x, y: py - 1, width: w, height: 2)), with: .color(theme.rec))
                }
                continue
            } else {
                // LEVEL: пик — полупрозрачный (выше 0 dBFS — красный), LOUD — сплошной снизу, пик-холд — линия.
                let lv: Float = max(l, r)
                let f: CGFloat = MeterState.frac(lv)
                let lf: CGFloat = MeterState.frac(an.loud(t))
                let over: Bool = !mute && lv >= MeterState.over
                if f > 0 {
                    let pr = CGRect(x: x, y: h - f * h, width: w, height: f * h)
                    ctx.fill(Path(roundedRect: pr, cornerRadius: 3), with: .color(over ? theme.rec : col.opacity(0.4)))
                }
                if lf > 0 {
                    let lr2 = CGRect(x: x, y: h - lf * h, width: w, height: lf * h)
                    ctx.fill(Path(roundedRect: lr2, cornerRadius: 3), with: .color(col))
                }
                let hf: CGFloat = MeterState.frac(max(lr[0].hold, lr[1].hold))
                if hf > 0.01 {
                    ctx.fill(Path(CGRect(x: x, y: max(0, h - hf * h - 1), width: w, height: 2)), with: .color(theme.text))
                }
                continue
            }
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(col))
        }
    }

    /// MASK: диапазон дорожки (как FREQ) — серый, полосы конфликта — жёлтые (ярче — сильнее), где дорожку
    /// заглушают — жёлтые шире полосы; номер мешающей —
    /// над полосой (полоса до верха — под ней); заглушённые — серые, без конфликтов.
    static func drawMask(_ ctx: GraphicsContext, _ size: CGSize, _ model: AppModel, _ n: Int) {
        let h: CGFloat = size.height
        let cell: CGFloat = size.width / 16
        // Полоса MASK уже метра (5 pt), чтобы «заглушают» на ширину места дорожки было видно (место ~13 pt).
        let w: CGFloat = 5
        let an: MixAnalysis = model.mixAn
        var audible: [Bool] = []
        for t in 0..<n { audible.append(model.project.audible(t)) }
        let nb = CGFloat(MixAnalysis.bands)
        let bh: CGFloat = h / nb
        for t in 0..<n {
            guard let sp = an.span(t) else { continue }
            let x: CGFloat = cell * (CGFloat(t) + 0.5) - w / 2
            let rect = CGRect(x: x, y: h - sp.hi * h, width: w, height: max(3, (sp.hi - sp.lo) * h))
            let shape = Path(roundedRect: rect, cornerRadius: 2)
            if !audible[t] {
                ctx.fill(shape, with: .color(theme.muteGrey))
                continue
            }
            ctx.fill(shape, with: .color(theme.meterTrack))
            let m = an.mask(t, audible)
            var c = ctx
            c.clip(to: shape)
            for j in 0..<m.strength.count where m.strength[j] > 0.02 && !m.buried[j] {
                let y: CGFloat = h - CGFloat(j + 1) * bh
                c.fill(Path(CGRect(x: x, y: y, width: w, height: bh)), with: .color(theme.accent.opacity(Double(m.strength[j]))))
            }
            // Где дорожку заглушают — жёлтым на ширину места дорожки без 2 pt (решение пользователя 15.11), подряд —
            // одним блоком.
            let ww: CGFloat = max(w + 4, cell - 2)
            var j = 0
            while j < m.buried.count {
                if !m.buried[j] {
                    j += 1
                    continue
                }
                var k: Int = j
                while k + 1 < m.buried.count && m.buried[k + 1] { k += 1 }
                let top: CGFloat = h - CGFloat(k + 1) * bh
                let run = CGRect(x: x + w / 2 - ww / 2, y: top, width: ww, height: CGFloat(k - j + 1) * bh)
                ctx.fill(Path(roundedRect: run, cornerRadius: 3), with: .color(theme.accent))
                j = k + 1
            }
            if m.who < 0 { continue }
            let label: String = String(m.who + 1)
            let cx: CGFloat = x + w / 2
            if rect.minY >= 12 {
                dimText(ctx, label, CGPoint(x: cx, y: rect.minY - 2), .bottom)
            } else {
                dimText(ctx, label, CGPoint(x: cx, y: rect.maxY + 2), .top)
            }
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
