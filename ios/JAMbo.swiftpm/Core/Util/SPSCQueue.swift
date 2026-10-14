import Synchronization

/// Кольцевая очередь «один писатель — один читатель» без блокировок и выделений после создания.
/// T — простой тип без ссылок (enum или struct из чисел, Unmanaged): элемент копируется в заранее выделенный буфер.
public final class SPSCQueue<T>: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<T>
    private let capacity: Int
    private let mask: Int
    /// Сколько всего записано (меняет только писатель).
    private let head = Atomic<Int>(0)
    /// Сколько всего прочитано (меняет только читатель).
    private let tail = Atomic<Int>(0)

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

    /// Положить элемент; false — очередь полна (элемент не записан). Не ждёт — годится и для аудиопотока.
    @inline(__always) @discardableResult
    public func push(_ value: T) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        if h - t >= capacity { return false }
        buffer[h & mask] = value
        head.store(h + 1, ordering: .releasing)
        return true
    }

    /// Взять элемент; nil — пусто.
    @inline(__always)
    public func pop() -> T? {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        if t == h { return nil }
        let value = buffer[t & mask]
        tail.store(t + 1, ordering: .releasing)
        return value
    }

    /// Сколько элементов ждёт (приблизительно, если другой поток работает).
    public var count: Int {
        return head.load(ordering: .acquiring) - tail.load(ordering: .acquiring)
    }
}
