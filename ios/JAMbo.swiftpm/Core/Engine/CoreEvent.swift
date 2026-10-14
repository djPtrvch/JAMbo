/// Сообщение от интерфейса в аудиоколбэк (через SPSCQueue). Только простые значения — без ссылок.
public enum CoreEvent: Sendable {
    case none
    /// Тест-тон (DIAGNOSTICS): включить или выключить.
    case tone(on: Bool)
    /// Тест-тон: частота в Гц.
    case toneFrequency(Float)
    /// PLAY: старт с начала следующего блока или стоп.
    case play(Bool)
    /// Темп, BPM.
    case tempo(Double)
    /// Метроном.
    case metronome(Bool)
    /// Тап по ячейке сетки во время игры: ячейка или Launcher.stop.
    case launch(track: Int, slot: Int)
    /// Тап по строке во время игры; atPass — в конце прохода строки (стрелки SWITCH).
    case scene(row: Int, atPass: Bool)
    /// Строки сетки переставили во время игры: активные ячейки и остановки — снова из снимка проекта.
    case adoptPlay
}
