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
    /// Живая нота с пианоролла (id — касание; velocity 1 — без p-lock Level) и её отпускание.
    case noteOn(track: Int, note: Int, id: Int, velocity: Float)
    case noteOff(track: Int, id: Int)
    /// ▶ редактора сэмпла: отрезок a…b (доли) сэмпла hash; стоп.
    case preview(hash: UInt64, a: Double, b: Double)
    case previewStop
}
