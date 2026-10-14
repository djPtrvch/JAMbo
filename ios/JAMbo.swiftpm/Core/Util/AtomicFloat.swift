/// Float, который пишет один поток и читает другой (UI ↔ аудио).
/// Запись ждёт замок; чтение только пробует его взять — при занятом возвращает прошлое прочитанное значение.
public final class AtomicFloat: @unchecked Sendable {
    private let lock = SpinLock()
    private var value: Float
    private var lastRead: Float

    public init(_ value: Float) {
        self.value = value
        lastRead = value
    }

    @inline(__always)
    public func load() -> Float {
        if lock.tryLock() {
            lastRead = value
            lock.unlock()
        }
        return lastRead
    }

    @inline(__always)
    public func store(_ newValue: Float) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

/// То же для счётчиков (Int).
public final class AtomicCounter: @unchecked Sendable {
    private let lock = SpinLock()
    private var value: Int = 0
    private var lastRead: Int = 0

    public init() {}

    @inline(__always)
    public func load() -> Int {
        if lock.tryLock() {
            lastRead = value
            lock.unlock()
        }
        return lastRead
    }

    /// Запись без ожидания (для аудиопотока): замок занят — значение запишется в следующий раз.
    @inline(__always)
    public func tryStore(_ newValue: Int) {
        if lock.tryLock() {
            value = newValue
            lock.unlock()
        }
    }
}
