import SwiftUI

/// Измеритель справа и метры MIX вне колбэка: 60 раз в секунду (drain) — новые блоки
/// из Levels, спад полосы ×0,9 за кадр, пик-холд 1,5 с (затем ×0,95 за кадр), метка клиппинга 2 с, наибольший
/// пик с последнего сброса; канал измерителя — выбранная дорожка, при MIX и MST — выход мастера.
final class MeterState {
    static let channels = Levels.channels
    /// Пик ≥ этого — перегруз.
    static let over: Float = 0.999
    private(set) var disp = [Float](repeating: 0, count: MeterState.channels * 2)
    private(set) var hold = [Float](repeating: 0, count: MeterState.channels * 2)
    private var holdAt = [Double](repeating: 0, count: MeterState.channels * 2)
    /// Приглушение Sidechain (amount·e, 0…1) за последний кадр.
    private(set) var duck = [Float](repeating: 0, count: MeterState.channels)
    private(set) var maxPeak = [Float](repeating: 0, count: MeterState.channels)
    private var clipUntil = [Double](repeating: 0, count: MeterState.channels)
    private var peak = [Float](repeating: 0, count: MeterState.channels * 2)
    private var newDuck = [Float](repeating: 0, count: MeterState.channels)
    private var count = 0
    /// Канал измерителя (дорожка или Levels.master); −1 — ещё не выбран.
    private(set) var shown = -1
    /// Палец на регуляторе громкости измерителя: снизу вместо пика — его значение.
    var volDrag = false

    /// Кадр: блоки колбэка с прошлого кадра.
    func tick(_ lv: Levels, now: Double) {
        let n = MeterState.channels
        for k in 0..<(n * 2) { peak[k] = 0 }
        for c in 0..<n { newDuck[c] = 0 }
        count = lv.read(since: count) { b in
            for c in 0..<n {
                let l: Float = Levels.value(b, c, 0)
                let r: Float = Levels.value(b, c, 1)
                let d: Float = Levels.value(b, c, 2)
                if l > peak[c * 2] { peak[c * 2] = l }
                if r > peak[c * 2 + 1] { peak[c * 2 + 1] = r }
                if d > newDuck[c] { newDuck[c] = d }
            }
        }
        for c in 0..<n {
            duck[c] = newDuck[c]
            for k in 0..<2 {
                let i = c * 2 + k
                let p = peak[i]
                disp[i] = max(p, disp[i] * 0.9)
                if p >= hold[i] {
                    hold[i] = p
                    holdAt[i] = now
                } else if now - holdAt[i] > 1.5 {
                    hold[i] *= 0.95
                }
                if p > maxPeak[c] { maxPeak[c] = p }
            }
            if max(peak[c * 2], peak[c * 2 + 1]) >= MeterState.over { clipUntil[c] = now + 2 }
        }
    }

    /// Канал измерителя сменился: пик и LUFS — заново.
    func show(_ ch: Int, _ lv: Levels) {
        if ch == shown { return }
        shown = ch
        maxPeak[ch] = 0
        lv.loudness.source.store(ch)
    }

    /// Пик канала за последний кадр (L и R).
    func framePeak(_ ch: Int) -> Float {
        return max(peak[ch * 2], peak[ch * 2 + 1])
    }

    func resetPeak(_ ch: Int) {
        if ch >= 0 && ch < MeterState.channels { maxPeak[ch] = 0 }
    }

    /// Канал молчит и на измерителе нечего показывать: полосы и пик-холды ниже шкалы (−60 dB), метки клиппинга
    /// нет, палец не на регуляторе (17.11: измеритель спит).
    func quiet(_ ch: Int, now: Double) -> Bool {
        guard ch >= 0 && ch < MeterState.channels else { return true }
        if volDrag || now < clipUntil[ch] { return false }
        let floor: Float = 0.001
        let i: Int = ch * 2
        return disp[i] < floor && disp[i + 1] < floor && hold[i] < floor && hold[i + 1] < floor
    }

    func clip(_ ch: Int, now: Double) -> Bool {
        return ch >= 0 && ch < MeterState.channels && now < clipUntil[ch]
    }

    /// Пики и холды канала: стерео — L и R, моно — наибольший.
    func bars(_ ch: Int, stereo: Bool) -> [(level: Float, hold: Float)] {
        guard ch >= 0 && ch < MeterState.channels else { return [] }
        let l: (level: Float, hold: Float) = (disp[ch * 2], hold[ch * 2])
        let r: (level: Float, hold: Float) = (disp[ch * 2 + 1], hold[ch * 2 + 1])
        if stereo { return [l, r] }
        let m: (level: Float, hold: Float) = (max(l.level, r.level), max(l.hold, r.hold))
        return [m]
    }

    /// Снижение громкости от Sidechain, dB (≤ 0).
    func duckDb(_ ch: Int) -> Float {
        guard ch >= 0 && ch < MeterState.channels else { return 0 }
        let g: Float = 1 - duck[ch]
        return g < 0.999 ? 20 * log10(max(1e-4, g)) : 0
    }

    /// Пик (0…1+) → доля высоты полосы (шкала −60…0 dBFS).
    static func frac(_ peak: Float) -> CGFloat {
        if peak <= 0 { return 0 }
        let db: Float = 20 * log10(peak)
        return CGFloat(min(1, max(0, (db + 60) / 60)))
    }
}

/// Полосы метра в общем стиле (полоса 9 px, скругление 3, зазор 3, дорожка --meter-track): заливка жёлтая, выше
/// 0 dBFS — красная (заглушённая — серая), пик-холд — тонкая линия цвета текста, приглушение Sidechain — оранжевым
/// сверху (gr — доля высоты).
enum MeterBars {
    static let width: CGFloat = 9
    static let gap: CGFloat = 3

    static func draw(_ ctx: GraphicsContext, _ r: CGRect, _ bars: [(level: Float, hold: Float)], theme: Theme,
                     muted: Bool = false, gr: CGFloat = 0) {
        for (k, b) in bars.enumerated() {
            let x: CGFloat = r.minX + CGFloat(k) * (width + gap)
            let bar = CGRect(x: x, y: r.minY, width: width, height: r.height)
            let shape = Path(roundedRect: bar, cornerRadius: 3)
            ctx.fill(shape, with: .color(theme.meterTrack))
            var c = ctx
            c.clip(to: shape)
            let f: CGFloat = MeterState.frac(b.level)
            let fill: Color = muted ? theme.muteGrey : (b.level >= MeterState.over ? theme.rec : theme.accent)
            c.fill(Path(CGRect(x: x, y: bar.maxY - f * bar.height, width: width, height: f * bar.height)), with: .color(fill))
            if gr > 0 {
                let h: CGFloat = min(1, gr) * bar.height
                c.fill(Path(CGRect(x: x, y: bar.minY, width: width, height: h)), with: .color(theme.gr.opacity(0.85)))
            }
            let hf: CGFloat = MeterState.frac(b.hold)
            if hf > 0.01 {
                let y: CGFloat = bar.maxY - hf * bar.height
                c.fill(Path(CGRect(x: x, y: max(bar.minY, y - 1), width: width, height: 2)), with: .color(theme.text))
            }
        }
    }

    /// То же по горизонтали (заголовки аранжировщика): полосы друг под другом, уровень — слева направо, приглушение
    /// Sidechain — справа, пик-холд — вертикальная линия.
    static func drawRow(_ ctx: GraphicsContext, _ r: CGRect, _ bars: [(level: Float, hold: Float)], theme: Theme,
                        muted: Bool = false, gr: CGFloat = 0) {
        for (k, b) in bars.enumerated() {
            let y: CGFloat = r.minY + CGFloat(k) * (width + gap)
            let bar = CGRect(x: r.minX, y: y, width: r.width, height: width)
            let shape = Path(roundedRect: bar, cornerRadius: 3)
            ctx.fill(shape, with: .color(theme.meterTrack))
            var c = ctx
            c.clip(to: shape)
            let f: CGFloat = MeterState.frac(b.level)
            let fill: Color = muted ? theme.muteGrey : (b.level >= MeterState.over ? theme.rec : theme.accent)
            c.fill(Path(CGRect(x: bar.minX, y: y, width: f * bar.width, height: width)), with: .color(fill))
            if gr > 0 {
                let w: CGFloat = min(1, gr) * bar.width
                c.fill(Path(CGRect(x: bar.maxX - w, y: y, width: w, height: width)), with: .color(theme.gr.opacity(0.85)))
            }
            let hf: CGFloat = MeterState.frac(b.hold)
            if hf > 0.01 {
                let x: CGFloat = bar.minX + hf * bar.width
                c.fill(Path(CGRect(x: min(bar.maxX - 2, x - 1), y: y, width: 2, height: width)), with: .color(theme.text))
            }
        }
    }

    /// Ширина полос (одна или две).
    static func span(_ count: Int) -> CGFloat {
        return count <= 1 ? width : 2 * width + gap
    }
}

/// Полосы измерителя справа обычными прямоугольниками (17.11, нагрузка): их двигает видеочип (масштаб и сдвиг слоёв),
/// без растеризации Canvas на главном потоке каждый кадр. Вид как у MeterBars.draw: дорожка, заливка снизу (выше
/// 0 dBFS — красная, заглушённая — серая), пик-холд — белая черта 2 px.
struct MeterBarsView: View {
    let bars: [(level: Float, hold: Float)]
    let muted: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: MeterBars.gap) {
            ForEach(0..<bars.count, id: \.self) { k in
                bar(bars[k])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bar(_ b: (level: Float, hold: Float)) -> some View {
        let h: CGFloat = max(1, height)
        let f: CGFloat = MeterState.frac(b.level)
        let hf: CGFloat = MeterState.frac(b.hold)
        let fill: Color = muted ? theme.muteGrey : (b.level >= MeterState.over ? theme.rec : theme.accent)
        // Черта холда: низ — на hf·h + 1 от низа, верх не выше полосы.
        let lift: CGFloat = min(h - 2, max(0, hf * h - 1))
        return ZStack(alignment: .bottom) {
            Rectangle().fill(theme.meterTrack)
            // Масштаб 0 — вырожденное преобразование: не меньше 0,001, пустая — прозрачная.
            Rectangle().fill(fill).scaleEffect(x: 1, y: max(0.001, f), anchor: .bottom).opacity(f > 0 ? 1 : 0)
            if hf > 0.01 {
                Rectangle().fill(theme.text).frame(height: 2).offset(y: -lift)
            }
        }
        .frame(width: MeterBars.width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
