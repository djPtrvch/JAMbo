import SwiftUI
import Darwin

/// Индикатор нагрузки, обновление 4 раза в секунду (17.11 — замер графики, на пробу):
/// CPU — средняя нагрузка аудиоколбэка (доля одного ядра);
/// UI — главный поток (SwiftUI: виды, раскладка, Canvas, жесты), доля одного ядра;
/// APP — всё приложение (все потоки, может быть больше 100 %).
/// Отрисовку слоёв на GPU (отдельный системный процесс) ни одна цифра не видит.
struct CPUIndicator: View {
    let meter: CPUMeter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
            let ui: UILoad.Sample = UILoad.shared.sample(now: tl.date.timeIntervalSinceReferenceDate)
            label(cpu: Int((meter.load * 100).rounded()), ui: ui.main, app: ui.app)
        }
    }

    private func label(cpu: Int, ui: Int, app: Int) -> some View {
        let high: Bool = cpu >= 70
        // Как в вебе: мелким обычным шрифтом, цвет --dim (CPU ≥ 70 % — красный).
        return VStack(spacing: 1) {
            Text("CPU \(cpu)%").foregroundStyle(high ? theme.rec : theme.dim)
            Text("UI \(ui)%").foregroundStyle(theme.dim)
            Text("APP \(app)%").foregroundStyle(theme.dim)
        }
        .font(.system(size: 9)).monospacedDigit()
        .frame(width: 48, height: 48)
        // По центру между низом значка наушников (~12 pt от верха панели) и надписью LUFS (верх панели + её высота
        // 44 + зазор 6 = 50 pt): центр подписей — на 31 pt (блок 48 от верха панели, его середина 24, + 7).
        .offset(y: 7)
    }
}

/// Нагрузка процессора по времени потоков: главный поток (UI) и весь процесс (APP), проценты одного ядра
/// за время между замерами (не чаще 5 раз в секунду, иначе разница слишком мала).
final class UILoad {
    struct Sample { var main: Int = 0; var app: Int = 0 }
    static let shared = UILoad()
    /// Порт главного потока (shared создаётся из body — на главном потоке).
    private let port: thread_act_t = mach_thread_self()
    private var lastMain: Double = -1
    private var lastApp: Double = 0
    private var lastWall: Double = 0
    private var value = Sample()

    func sample(now: Double) -> Sample {
        if lastWall > 0, now - lastWall < 0.2 { return value }
        let main: Double = mainSeconds()
        let app: Double = appSeconds()
        if lastMain >= 0, now > lastWall {
            let wall: Double = now - lastWall
            value.main = Int(((main - lastMain) / wall * 100).rounded())
            value.app = Int(((app - lastApp) / wall * 100).rounded())
        }
        lastMain = main
        lastApp = app
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

    private func appSeconds() -> Double {
        var u = rusage()
        if getrusage(RUSAGE_SELF, &u) != 0 { return lastApp }
        return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6
            + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
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
