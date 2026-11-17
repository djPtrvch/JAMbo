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
    @State private var start: Double? = nil
    /// Ход пальца на всю шкалу регулятора, pt.
    static let travel: CGFloat = 240

    /// Измеритель спит — анимация на паузе.
    private var paused: Bool { return model.meterAsleep }

    // Нагрузка (17.11): 60 раз в секунду обновляются только полосы; подписи и метка клиппинга — 10 раз в секунду;
    // регулятор, жест и MIDI — вне анимации (только когда меняются).
    var body: some View {
        let ch: Int = model.meterChannel
        let still: Bool = paused
        return VStack(spacing: 4) {
            FrameTimeline(fps: 10, paused: still) { tl in
                top(ch, now: tl.date.timeIntervalSinceReferenceDate)
            }
            bars(ch, still: still)
            FrameTimeline(fps: 10, paused: still) { _ in
                label(bottomText(ch))
            }
            .onTapGesture { model.resetMeterPeak() }
        }
        .frame(width: Layout.meterWidth)
    }

    /// LUFS и метка клиппинга.
    private func top(_ ch: Int, now: Double) -> some View {
        let lufs: Float = model.audio.core.levels.loudness.integrated.load()
        let clip: Bool = model.meters.clip(ch, now: now)
        return VStack(spacing: 4) {
            label("LUFS\n" + MeterColumn.fmtLufs(lufs)).onTapGesture { model.resetLoudness() }
            RoundedRectangle(cornerRadius: 2).fill(clip ? theme.rec : theme.off).frame(width: 21, height: 4)
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

    private func bars(_ ch: Int, still: Bool) -> some View {
        let stereo: Bool = ch >= Levels.master || model.trackStereo(ch)
        let track: Bool = ch < Levels.master
        let vol: Double = faderValue(ch)
        // Заглушённая дорожка — серым, как в MIX (отличие от веба).
        let muted: Bool = track && ch < model.project.tracks.count && !model.project.audible(ch)
        let meters: MeterState = model.meters
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                FrameTimeline(fps: 60, paused: still) { _ in
                    MeterBarsView(bars: meters.bars(ch, stereo: stereo), muted: muted, height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
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
