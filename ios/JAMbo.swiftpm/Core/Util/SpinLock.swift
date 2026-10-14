#if canImport(os)
import os
#else
import Foundation
#endif

/// Замок для обмена UI ↔ аудио без модуля Synchronization (ТЗ 0.2: запасной вариант).
/// Аудиопоток только пробует взять замок (tryLock) и при занятом пропускает — колбэк не ждёт.
/// На iPad — os_unfair_lock, на Linux (тесты) — NSLock.
public final class SpinLock: @unchecked Sendable {
    #if canImport(os)
    private let pointer: UnsafeMutablePointer<os_unfair_lock>

    public init() {
        pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    @inline(__always) public func lock() { os_unfair_lock_lock(pointer) }
    @inline(__always) public func unlock() { os_unfair_lock_unlock(pointer) }
    @inline(__always) public func tryLock() -> Bool { return os_unfair_lock_trylock(pointer) }
    #else
    private let inner = NSLock()

    public init() {}

    @inline(__always) public func lock() { inner.lock() }
    @inline(__always) public func unlock() { inner.unlock() }
    @inline(__always) public func tryLock() -> Bool { return inner.try() }
    #endif
}
