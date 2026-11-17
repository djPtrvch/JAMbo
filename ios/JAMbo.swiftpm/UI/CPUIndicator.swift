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
        .frame(width: 48, height: 48)
        // По центру между низом значка наушников (~12 pt от верха панели) и надписью LUFS (верх панели + её высота
        // 44 + зазор 6 = 50 pt): центр подписей — на 31 pt (блок 48 от верха панели, его середина 24, + 7).
        .offset(y: 7)
    }
}

/// Цепочка прослушивания меняет звук (коррекция наушников, CORRECT CURVE, SPACE, MONO, SUB — monitorAudible; 8.11,
/// решение пользователя): над CPU — жёлтый значок наушников, без кнопки и контура; BYPASS или всё нейтрально —
/// значка нет. Тап — окно коррекции (как тап по имени MASTER EQ).
struct PhonesBadge: View {
    let model: AppModel

    var body: some View {
        if model.monitorAudible {
            Image(systemName: "headphones")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 28, height: 13, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { model.openPhones() }
        }
    }
}
