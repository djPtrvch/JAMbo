/// Кольцевая очередь «один писатель — один читатель» без выделений после создания.
/// T — простой тип без ссылок (enum или struct из чисел): элемент копируется в заранее выделенный буфер.
/// Аудиопоток не ждёт: pop и tryPush при занятом замке сразу возвращаются (элемент заберётся в следующем блоке).
public final class SPSCQueue<T>: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<T>
    private let capacity: Int
    private let mask: Int
    private let lock = SpinLock()
    private var head: Int = 0
    private var tail: Int = 0

    /// capacity округляется вверх до степени двойки; filler — начальное значение ячеек.
    public init(capacity: Int, filler: T) {
        var size = 1
        while size < max(2, capacity) { size <<= 1 }
        self.capacity = size
        mask = size - 1
        buffer = UnsafeMutablePointer<T>.allocate(capacity: size)
        buffer.initialize(repeating: filler, count: size)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    /// Положить элемент (ждёт замок — для UI); false — очередь полна.
    @discardableResult
    public func push(_ value: T) -> Bool {
        lock.lock()
        let ok = put(value)
        lock.unlock()
        return ok
    }

    /// Положить без ожидания (для аудиопотока); false — замок занят или очередь полна.
    @inline(__always) @discardableResult
    public func tryPush(_ value: T) -> Bool {
        guard lock.tryLock() else { return false }
        let ok = put(value)
        lock.unlock()
        return ok
    }

    /// Взять элемент без ожидания; nil — пусто или замок занят.
    @inline(__always)
    public func pop() -> T? {
        guard lock.tryLock() else { return nil }
        var result: T? = nil
        if tail != head {
            result = buffer[tail & mask]
            tail += 1
        }
        lock.unlock()
        return result
    }

    /// Сколько элементов ждёт.
    public var count: Int {
        lock.lock()
        let n = head - tail
        lock.unlock()
        return n
    }

    @inline(__always)
    private func put(_ value: T) -> Bool {
        if head - tail >= capacity { return false }
        buffer[head & mask] = value
        head += 1
        return true
    }
}
