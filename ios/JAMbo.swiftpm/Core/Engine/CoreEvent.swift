/// Сообщение от интерфейса в аудиоколбэк (через SPSCQueue). Только простые значения — без ссылок.
public enum CoreEvent: Sendable {
    case none
    /// Тест-тон S0: включить или выключить.
    case tone(on: Bool)
    /// Тест-тон S0: частота в Гц.
    case toneFrequency(Float)
}
