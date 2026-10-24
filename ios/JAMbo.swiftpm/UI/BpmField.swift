import SwiftUI

/// Темп: палец вверх-вниз — 4 px на 1 BPM; двойной тап — ввод числом (решение пользователя; прежде — удержание).
/// Внизу — полоса фазы: 4 отрезка на такт × SYNC QUANTUM, при игре загораются до текущей доли фразы.
struct BpmField: View {
    let model: AppModel
    @State private var start: Double? = nil
    @State private var moved: Bool = false
    @State private var lastTap: Date = .distantPast
    @State private var input: Bool = false
    @State private var text: String = ""
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack {
                Text("BPM").font(.system(size: 11)).tracking(0.9).foregroundStyle(theme.dim)
                Spacer(minLength: 4)
                Text(bpmText).font(.system(size: 19)).monospacedDigit().foregroundStyle(theme.text)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            PhaseBar(beat: model.live.beat, sync: model.settings.sync).padding(.horizontal, 12).padding(.bottom, 7)
        }
        .background(start != nil ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .gesture(drag)
        .alert("BPM", isPresented: $input) {
            TextField("BPM", text: $text).keyboardType(.decimalPad)
            Button("OK") { enter() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var bpmText: String {
        let v: Double = model.project.bpm
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil { begin() }
                let dy: CGFloat = g.translation.height
                if abs(dy) > 10 { moved = true }
                if moved, let s = start {
                    model.setBpm((s - Double(dy) / 4).rounded())
                }
            }
            .onEnded { _ in
                start = nil
                model.endGesture()
                if !moved { tapped() }
            }
    }

    private func begin() {
        model.ensureAudio()
        model.beginGesture()
        start = model.project.bpm
        moved = false
    }

    /// Второй тап подряд — окно ввода.
    private func tapped() {
        let now = Date()
        if now.timeIntervalSince(lastTap) < EqPlot.doubleTap {
            lastTap = .distantPast
            text = bpmText
            input = true
        } else {
            lastTap = now
        }
    }

    private func enter() {
        let v: Double? = Double(text.replacingOccurrences(of: ",", with: "."))
        if let v = v { model.setBpm(v) }
    }
}

/// Полоса фазы: 4 отрезка на такт; горят отрезки до текущей доли (−1 — стоп, все серые).
struct PhaseBar: View {
    let beat: Int
    /// Отрезков — 4 на такт × SYNC QUANTUM (S13e).
    let sync: SyncSettings
    @Environment(\.theme) private var theme

    var body: some View {
        let lit: Int = sync.phaseLit(beat: beat)
        let n: Int = sync.phaseSegments
        return HStack(spacing: 2) {
            ForEach(0..<n, id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? theme.accent : theme.meterTrack)
                    .frame(height: 1)
            }
        }
    }
}
