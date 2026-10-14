import Synchronization

/// Float, который пишет один поток и читает другой (UI ↔ аудио), без блокировок: биты Float в Atomic<UInt32>.
public final class AtomicFloat: @unchecked Sendable {
    private let bits: Atomic<UInt32>

    public init(_ value: Float) {
        bits = Atomic<UInt32>(value.bitPattern)
    }

    @inline(__always)
    public func load() -> Float {
        return Float(bitPattern: bits.load(ordering: .relaxed))
    }

    @inline(__always)
    public func store(_ value: Float) {
        bits.store(value.bitPattern, ordering: .relaxed)
    }
}

/// Счётчик (Int), который пишет один поток и читает другой.
public final class AtomicCounter: @unchecked Sendable {
    private let value = Atomic<Int>(0)

    public init() {}

    @inline(__always)
    public func load() -> Int {
        return value.load(ordering: .relaxed)
    }

    @inline(__always)
    public func store(_ newValue: Int) {
        value.store(newValue, ordering: .relaxed)
    }
}
