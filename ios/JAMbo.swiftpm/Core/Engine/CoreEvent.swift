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
}
