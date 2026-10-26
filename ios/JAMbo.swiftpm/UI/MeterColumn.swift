import SwiftUI

/// Измеритель уровня справа (как ui/meter.ts веба): сверху интегральная громкость LUFS (тап — сброс), метка
/// клиппинга, полосы (стерео — две, моно — одна; шкала −60…0 dB, пик-холд, выше 0 dB — красная, заглушённая
/// дорожка — серая), снизу наибольший
/// пик в dB (тап — сброс). Поверх полос — регулятор громкости (белая планка по той же шкале): у дорожки — её громкость
/// в микшере (SETTINGS → LEVEL: ABSOLUTE — совпадает с MIX; RELATIVE — подстройка trim вниз от громкости MIX: регулятор
/// на шкале — на итоговой громкости, выше громкости MIX не поднимается; при ABSOLUTE подстройка не действует), при MIX
/// и MST — громкость выхода мастера (палец вверх-вниз; пока палец на нём — снизу VOL — итоговая громкость).
struct MeterColumn: View {
    let model: AppModel
    @Environment(\.theme) private var theme
    @State private var start: Double? = nil
    /// Ход пальца на всю шкалу регулятора, pt.
    static let travel: CGFloat = 240

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            let _ = RedrawMeter.hit(.meter)
            column(now: tl.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: Layout.meterWidth)
    }

    private func column(now: Double) -> some View {
        let ch: Int = model.meterChannel
        let m: MeterState = model.meters
        let lufs: Float = model.audio.core.levels.loudness.integrated.load()
        let clip: Bool = m.clip(ch, now: now)
        return VStack(spacing: 4) {
            label("LUFS\n" + MeterColumn.fmtLufs(lufs)).onTapGesture { model.resetLoudness() }
            RoundedRectangle(cornerRadius: 2).fill(clip ? theme.rec : theme.off).frame(width: 21, height: 4)
            bars(ch)
            label(bottomText(ch)).onTapGesture { model.resetMeterPeak() }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9)).monospacedDigit()
            .multilineTextAlignment(.center)
            .lineSpacing(0)
            .foregroundStyle(theme.dim)
            .frame(width: Layout.meterWidth)
            .contentShape(Rectangle())
    }

    private func bottomText(_ ch: Int) -> String {
        if model.meters.volDrag { return "VOL\n" + MeterColumn.fmtVol(volValue(ch)) }
        return MeterColumn.fmtDb(model.meters.maxPeak[ch]) + "\ndB"
    }

    /// Итоговая громкость (подпись VOL): у дорожки — громкость MIX и подстройка.
    private func volValue(_ ch: Int) -> Double {
        return model.meterVol(ch)
    }

    /// Положение регулятора на шкале: громкость выхода или итоговая громкость дорожки (при RELATIVE — громкость MIX
    /// и подстройка; выше громкости MIX не поднимается).
    private func faderValue(_ ch: Int) -> Double {
        return volValue(ch)
    }

    private func bars(_ ch: Int) -> some View {
        let stereo: Bool = ch >= Levels.master || model.trackStereo(ch)
        let data = model.meters.bars(ch, stereo: stereo)
        let track: Bool = ch < Levels.master
        let vol: Double = faderValue(ch)
        // Заглушённая дорожка — серым, как в MIX (отличие от веба).
        let muted: Bool = track && ch < model.project.tracks.count && !model.project.audible(ch)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas(rendersAsynchronously: true) { ctx, size in
                    let w: CGFloat = MeterBars.span(data.count)
                    MeterBars.draw(ctx, CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height), data, theme: theme,
                                   muted: muted)
                }
                thumb(vol, geo.size)
            }
            .contentShape(Rectangle())
            .gesture(drag(ch))
        }
        .midiTarget(model, MidiButtons.level)
    }

    private func thumb(_ vol: Double, _ size: CGSize) -> some View {
        let f: CGFloat = CGFloat((vol - Params.volMin) / -Params.volMin)
        return RoundedRectangle(cornerRadius: 3)
            .fill(theme.text)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.bg, lineWidth: 1.5))
            .frame(width: 30, height: 8)
            .shadow(color: Color.black.opacity(0.4), radius: 2, y: 1)
            .position(x: size.width / 2, y: size.height * (1 - f))
            .allowsHitTesting(false)
    }

    private func drag(_ ch: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil {
                    start = faderValue(ch)
                    model.meters.volDrag = true
                    model.beginGesture()
                }
                let dy: Double = Double(-g.translation.height / MeterColumn.travel)
                let v: Double = (start ?? 0) + dy * -Params.volMin
                model.setMeterVol(ch, v)
            }
            .onEnded { _ in
                guard start != nil else { return }
                start = nil
                model.meters.volDrag = false
                model.endGesture()
            }
    }

    static func fmtDb(_ peak: Float) -> String {
        return peak > 0.001 ? String(format: "%.1f", 20 * log10(peak)) : "−∞"
    }

    static func fmtLufs(_ l: Float) -> String {
        return l.isFinite ? String(format: "%.1f", l) : "−∞"
    }

    static func fmtVol(_ v: Double) -> String {
        return v <= Params.volMin + 0.05 ? "−∞" : String(format: "%.1f", v)
    }
}
