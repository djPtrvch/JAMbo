import SwiftUI
import Darwin

/// Индикатор нагрузки, обновление 4 раза в секунду (17.11 — замер графики, на пробу), доли одного ядра:
/// CPU — аудиоколбэк; PUMP — насос drain() (60 раз в секунду переносит сообщения звука в состояние интерфейса);
/// VIEW — остальное время главного потока (SwiftUI: виды, раскладка, Canvas, жесты).
/// Отрисовку слоёв на GPU (отдельный системный процесс) ни одна цифра не видит.
struct CPUIndicator: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
            let ui: UILoad.Sample = UILoad.shared.sample(now: tl.date.timeIntervalSinceReferenceDate, pumpNs: model.pumpNs)
            label(cpu: Int((model.audio.core.cpu.load * 100).rounded()), pump: ui.pump, view: max(0, ui.main - ui.pump))
        }
    }

    private func label(cpu: Int, pump: Int, view: Int) -> some View {
        let high: Bool = cpu >= 70
        // Как в вебе: мелким обычным шрифтом, цвет --dim (CPU ≥ 70 % — красный).
        return VStack(spacing: 1) {
            Text("CPU \(cpu)%").foregroundStyle(high ? theme.rec : theme.dim)
            Text("PUMP \(pump)%").foregroundStyle(theme.dim)
            Text("VIEW \(view)%").foregroundStyle(theme.dim)
        }
        .font(.system(size: 9)).monospacedDigit()
        .frame(width: 48, height: 48)
        // По центру между низом значка наушников (~12 pt от верха панели) и надписью LUFS (верх панели + её высота
        // 44 + зазор 6 = 50 pt): центр подписей — на 31 pt (блок 48 от верха панели, его середина 24, + 7).
        .offset(y: 7)
    }
}

/// Нагрузка главного потока по времени потока (main) и доля насоса (pump), проценты одного ядра
/// за время между замерами (не чаще 5 раз в секунду, иначе разница слишком мала).
final class UILoad {
    struct Sample { var main: Int = 0; var pump: Int = 0 }
    static let shared = UILoad()
    /// Порт главного потока (shared создаётся из body — на главном потоке).
    private let port: thread_act_t = mach_thread_self()
    private var lastMain: Double = -1
    private var lastPump: UInt64 = 0
    private var lastWall: Double = 0
    private var value = Sample()

    func sample(now: Double, pumpNs: UInt64) -> Sample {
        if lastWall > 0, now - lastWall < 0.2 { return value }
        let main: Double = mainSeconds()
        if lastMain >= 0, now > lastWall {
            let wall: Double = now - lastWall
            value.main = Int(((main - lastMain) / wall * 100).rounded())
            value.pump = Int((Double(pumpNs &- lastPump) / 1e9 / wall * 100).rounded())
        }
        lastMain = main
        lastPump = pumpNs
        lastWall = now
        return value
    }

    private func mainSeconds() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr: kern_return_t = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        if kr != KERN_SUCCESS { return lastMain }
        return Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6
            + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
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
