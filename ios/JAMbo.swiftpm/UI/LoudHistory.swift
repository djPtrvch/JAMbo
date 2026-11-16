import SwiftUI

/// История громкости мастера при MIX (под осциллоскопом): short-term (3 с) за последние 60 с игры, пунктир —
/// интегральная; числа SHORT TERM (short-term сейчас), LOUDNESS RANGE (LRA, разброс громкости, EBU Tech 3342: short-term за всю игру,
/// пороги −70 LUFS и −20 LU, 10…95 %), PEAK TO LOUDNESS (PLR, пик отсчётов с начала минус интегральная). Копится только во время
/// игры (тишина между джемами не портит LRA); тап по окну — с нуля (и LUFS измерителя).
final class LoudHistory {
    static let points: Int = 300
    static let step: Double = 0.2
    static let bins: Int = 800
    private(set) var values = [Float](repeating: -Float.infinity, count: LoudHistory.points)
    /// Индекс следующей записи (самое старое значение).
    private(set) var head: Int = 0
    private var hist = [Int](repeating: 0, count: LoudHistory.bins)
    private(set) var peak: Float = 0
    private var last: Double = 0
    private(set) var lra: Double = -1
    private var lraAt: Double = 0

    /// Кадр метров: раз в 0,2 с во время игры — значение short-term и пик отсчётов мастера.
    func tick(_ l: Loudness, framePeak: Float, playing: Bool, now: Double) {
        if !playing { return }
        if framePeak > peak { peak = framePeak }
        if now - last < LoudHistory.step { return }
        last = now
        let st: Float = l.shortTerm.load()
        values[head] = st
        head = (head + 1) % LoudHistory.points
        if st.isFinite && st > -70 {
            let b: Int = Int(((Double(st) + 70) * 10).rounded(.down))
            hist[max(0, min(LoudHistory.bins - 1, b))] += 1
        }
        if now - lraAt > 0.5 {
            lraAt = now
            lra = computeLra()
        }
    }

    func reset() {
        for i in 0..<values.count { values[i] = -Float.infinity }
        for i in 0..<hist.count { hist[i] = 0 }
        head = 0
        peak = 0
        lra = -1
    }

    /// LRA: относительный порог −20 LU от среднего (по энергии) short-term, затем 95-й минус 10-й процентиль.
    private func computeLra() -> Double {
        var n: Int = 0
        var e: Double = 0
        var b: Int = 0
        while b < LoudHistory.bins {
            let c: Int = hist[b]
            if c > 0 {
                n += c
                e += Double(c) * pow(10, LoudHistory.level(b) / 10)
            }
            b += 1
        }
        if n < 10 { return -1 }
        let gate: Double = 10 * log10(e / Double(n)) - 20
        var kept: Int = 0
        b = 0
        while b < LoudHistory.bins {
            if LoudHistory.level(b) >= gate { kept += hist[b] }
            b += 1
        }
        if kept < 10 { return -1 }
        let lo: Double = percentile(gate, kept, 0.10)
        let hi: Double = percentile(gate, kept, 0.95)
        return max(0, hi - lo)
    }

    private func percentile(_ gate: Double, _ kept: Int, _ q: Double) -> Double {
        let target: Double = q * Double(kept - 1)
        var acc: Int = 0
        var b: Int = 0
        while b < LoudHistory.bins {
            if LoudHistory.level(b) >= gate {
                acc += hist[b]
                if Double(acc) > target { return LoudHistory.level(b) }
            }
            b += 1
        }
        return LoudHistory.level(LoudHistory.bins - 1)
    }

    /// Середина корзины b, LUFS.
    static func level(_ b: Int) -> Double {
        return -70 + (Double(b) + 0.5) / 10
    }
}

/// Окно истории громкости (под осциллоскопом при MIX).
struct LoudHistoryView: View {
    let model: AppModel
    static let top: Float = -6
    static let bottom: Float = -36

    var body: some View {
        TimelineView(.animation(minimumInterval: LoudHistory.step)) { tl in
            ScopeCanvas(now: tl.date) { ctx, size in draw(ctx, size) }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .onTapGesture { model.resetLoudHistory() }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let h: LoudHistory = model.loudHist
        let ml: Loudness = model.audio.core.levels.mixLoudness
        let st: Float = ml.shortTerm.load()
        let int: Float = ml.integrated.load()
        let pk: Float = h.peak
        let plr: Float = pk > 0 && int.isFinite ? 20 * log10(pk) - int : -Float.infinity
        let row: CGFloat = 44
        let cell: CGFloat = size.width / 3
        cellText(ctx, "SHORT\nTERM", fmt(st), cell * 0.5, 4)
        cellText(ctx, "LOUDNESS\nRANGE", h.lra >= 0 ? String(format: "%.1f", h.lra) : "—", cell * 1.5, 4)
        cellText(ctx, "PEAK TO\nLOUDNESS", fmt(plr), cell * 2.5, 4)
        let plot = CGRect(x: 6, y: row + 4, width: size.width - 12, height: max(1, size.height - row - 10))
        grid(ctx, plot)
        if int.isFinite { intLine(ctx, plot, int) }
        curve(ctx, plot, h)
    }

    private func fmt(_ v: Float) -> String {
        return v.isFinite ? String(format: "%.1f", v) : "—"
    }

    /// Подпись в две строки (каждая по центру) и значение под ней.
    private func cellText(_ ctx: GraphicsContext, _ label: String, _ value: String, _ x: CGFloat, _ y: CGFloat) {
        let lines: [Substring] = label.split(separator: "\n")
        var k: Int = 0
        while k < lines.count {
            let l = Text(String(lines[k])).font(.system(size: 9)).foregroundColor(theme.dim)
            ctx.draw(l, at: CGPoint(x: x, y: y + CGFloat(k) * 11), anchor: .top)
            k += 1
        }
        let v = Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundColor(theme.text)
        ctx.draw(v, at: CGPoint(x: x, y: y + 23), anchor: .top)
    }

    private func yOf(_ v: Float, _ r: CGRect) -> CGFloat {
        let t: Float = LoudHistoryView.top, b: Float = LoudHistoryView.bottom
        let f: Float = max(0, min(1, (t - v) / (t - b)))
        return r.minY + CGFloat(f) * r.height
    }

    private func grid(_ ctx: GraphicsContext, _ r: CGRect) {
        var p = Path()
        for db in [-12, -18, -24, -30] {
            let y: CGFloat = yOf(Float(db), r)
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.stroke(p, with: .color(theme.grid), lineWidth: 1)
        for db in [-12, -24] {
            let t = Text("\(db)").font(.system(size: 9)).foregroundColor(theme.dim)
            ctx.draw(t, at: CGPoint(x: r.minX + 1, y: yOf(Float(db), r) - 1), anchor: .bottomLeading)
        }
    }

    private func intLine(_ ctx: GraphicsContext, _ r: CGRect, _ v: Float) {
        var p = Path()
        let y: CGFloat = yOf(v, r)
        p.move(to: CGPoint(x: r.minX, y: y))
        p.addLine(to: CGPoint(x: r.maxX, y: y))
        ctx.stroke(p, with: .color(theme.text.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    /// Short-term: справа — новое; тишина и пропуски — разрыв линии.
    private func curve(_ ctx: GraphicsContext, _ r: CGRect, _ h: LoudHistory) {
        let n: Int = LoudHistory.points
        let dx: CGFloat = r.width / CGFloat(n - 1)
        var p = Path()
        var pen: Bool = false
        var k: Int = 0
        while k < n {
            let v: Float = h.values[(h.head + k) % n]
            if v.isFinite && v > -70 {
                let pt = CGPoint(x: r.minX + CGFloat(k) * dx, y: yOf(v, r))
                if pen { p.addLine(to: pt) } else { p.move(to: pt) }
                pen = true
            } else {
                pen = false
            }
            k += 1
        }
        ctx.stroke(p, with: .color(theme.accent), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }
}
