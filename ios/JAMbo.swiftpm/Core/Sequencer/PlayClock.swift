import Synchronization

/// Ход транспорта из колбэка для интерфейса (запись нот с REC): следующий шаг, его кадр, длина шага в кадрах,
/// кадр начала блока и время хоста, когда этот блок звучит. Одна запись — seqlock: читатель повторяет, пока
/// писатель не закончил (колбэк не ждёт никогда).
public final class PlayClock: @unchecked Sendable {
    public struct State: Equatable, Sendable {
        public var playing: Bool = false
        public var nextTick: Int = 0
        public var nextFrame: Double = 0
        public var stepFrames: Double = 6000
        public var blockFrame: Double = 0
        public var blockHost: Double = 0
    }

    private let version = Atomic<Int>(0)
    private let playing = Atomic<Int>(0)
    private let nextTick = Atomic<Int>(0)
    private let nextFrame = Atomic<UInt64>(0)
    private let stepFrames = Atomic<UInt64>(0)
    private let blockFrame = Atomic<UInt64>(0)
    private let blockHost = Atomic<UInt64>(0)

    public init() {}

    /// Колбэк: записать состояние.
    @inline(__always)
    public func write(_ s: State) {
        let v = version.load(ordering: .relaxed)
        version.store(v + 1, ordering: .relaxed)
        // Барьер: записи полей не уходят раньше нечётной версии (seqlock по Boehm; на ARM иначе читатель мог
        // увидеть новые поля при старой чётной версии).
        atomicMemoryFence(ordering: .releasing)
        playing.store(s.playing ? 1 : 0, ordering: .relaxed)
        nextTick.store(s.nextTick, ordering: .relaxed)
        nextFrame.store(s.nextFrame.bitPattern, ordering: .relaxed)
        stepFrames.store(s.stepFrames.bitPattern, ordering: .relaxed)
        blockFrame.store(s.blockFrame.bitPattern, ordering: .relaxed)
        blockHost.store(s.blockHost.bitPattern, ordering: .relaxed)
        version.store(v + 2, ordering: .releasing)
    }

    /// Интерфейс: прочитать целую запись.
    public func read() -> State {
        while true {
            let v0 = version.load(ordering: .acquiring)
            if v0 & 1 == 1 { continue }
            var s = State()
            s.playing = playing.load(ordering: .relaxed) != 0
            s.nextTick = nextTick.load(ordering: .relaxed)
            s.nextFrame = Double(bitPattern: nextFrame.load(ordering: .relaxed))
            s.stepFrames = Double(bitPattern: stepFrames.load(ordering: .relaxed))
            s.blockFrame = Double(bitPattern: blockFrame.load(ordering: .relaxed))
            s.blockHost = Double(bitPattern: blockHost.load(ordering: .relaxed))
            // Барьер: чтения полей не уходят позже повторной проверки версии.
            atomicMemoryFence(ordering: .acquiring)
            if version.load(ordering: .relaxed) == v0 { return s }
        }
    }
}
