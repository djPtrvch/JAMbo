import SwiftUI

/// Индикатор CPU: средняя нагрузка аудиоколбэка (доля одного ядра), обновление 4 раза в секунду.
struct CPUIndicator: View {
    let meter: CPUMeter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            label(percent: Int((meter.load * 100).rounded()))
        }
    }

    private func label(percent: Int) -> some View {
        let high: Bool = percent >= 70
        // Как в вебе: две строки мелким обычным шрифтом, цвет --dim (≥ 70 % — красный).
        return VStack(spacing: 1) {
            Text("CPU").font(.system(size: 9))
            Text("\(percent)%").font(.system(size: 9)).monospacedDigit()
        }
        .foregroundStyle(high ? theme.rec : theme.dim)
        // Высотой с кнопки верхней панели; подписи — к низу (8.11: над ними — значок наушников вровень с верхом
        // кнопок).
        .frame(width: 48, height: Layout.topHeight - 1, alignment: .bottom)
        .frame(height: Layout.topHeight, alignment: .top)
    }
}

/// Коррекция наушников включена (8.11, решение пользователя): над CPU — жёлтый значок наушников, без кнопки и
/// контура; выключена — значка нет. Тап — окно коррекции (как тап по имени MASTER EQ).
struct PhonesBadge: View {
    let model: AppModel

    var body: some View {
        if model.phonesEq.on {
            Image(systemName: "headphones")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 28, height: 13, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { model.openPhones() }
        }
    }
}
