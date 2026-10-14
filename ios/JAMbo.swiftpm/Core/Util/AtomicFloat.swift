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
