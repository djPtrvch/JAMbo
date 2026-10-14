import SwiftUI

/// Индикатор CPU: средняя нагрузка аудиоколбэка (доля одного ядра), обновление 4 раза в секунду.
struct CPUIndicator: View {
    let meter: CPUMeter
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            label(percent: Int((meter.load * 100).rounded()))
        }
    }

    private func label(percent: Int) -> some View {
        let high: Bool = percent >= 70
        return VStack(spacing: 0) {
            Text("CPU").font(.system(size: 9, weight: .bold))
            Text("\(percent)%").font(.system(size: 13, weight: .bold)).monospacedDigit()
        }
        .foregroundStyle(high ? theme.rec : theme.dim)
        .frame(width: 48, height: 48)
    }
}
