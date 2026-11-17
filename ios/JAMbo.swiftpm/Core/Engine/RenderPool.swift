import Foundation
import Synchronization

/// Задания колбэка, которые можно считать на нескольких потоках (MULTICORE) (номер задания — 0…count−1; задания независимы).
public protocol RenderJobs: AnyObject {
    func runJob(_ j: Int)
}

/// Многоядерный режим (17.11, MULTICORE; проверка — SWIFT_MILESTONE_S14.md «Проверка многоядерного режима»): помощники —
/// потоки, которые ждут на семафоре; колбэк будит их, и задания блока разбирают все по очереди атомарным счётчиком.
/// Помощник не проснулся — всё досчитает колбэк (звук тот же, только дольше); колбэк ждёт конца взятых заданий.
/// Потоки реального времени и аудио-группа — снаружи (setup: AudioHost), в тестах — обычные потоки.
/// Счётчик заданий: старшие 32 бита — число заданий блока, младшие — следующее задание (одно атомарное значение:
/// поздний помощник прошлого блока не возьмёт задание нового с прежним числом).
public final class RenderPool: @unchecked Sendable {
    public static let maxHelpers: Int = 3
    private let ticket = Atomic<Int>(0)
    private let done = Atomic<Int>(0)
    private let generation = Atomic<Int>(0)
    private let helpers = Atomic<Int>(0)
    private let helperJobs = Atomic<Int>(0)
    private let allJobs = Atomic<Int>(0)
    private let alive = Atomic<Int>(0)
    /// Семафоры помощников: два набора (поколение чётное / нечётное) — старые потоки не крадут пробуждения новых.
    private let sems: UnsafeMutablePointer<DispatchSemaphore>
    /// Что считать в этом блоке (колбэк ставит до выдачи заданий; помощники читают после взятия задания).
    /// Без счёта ссылок: цели живут всё время ядра (голоса синта, эффекты дорожек).
    private unowned(unsafe) var active: RenderJobs? = nil

    public init() {
        let c: Int = 2 * RenderPool.maxHelpers
        sems = UnsafeMutablePointer<DispatchSemaphore>.allocate(capacity: c)
        for k in 0..<c { (sems + k).initialize(to: DispatchSemaphore(value: 0)) }
    }

    /// Помощников в работе (колбэк будит не больше).
    public var helperCount: Int { return helpers.load(ordering: .relaxed) }
    /// Живых потоков помощников (вышли из прошлого поколения — уходят).
    public var aliveCount: Int { return alive.load(ordering: .relaxed) }

    /// Заданий, взятых помощниками, с прошлого чтения (интерфейс: доля помощников).
    public func takeHelperJobs() -> Int {
        return helperJobs.exchange(0, ordering: .relaxed)
    }

    /// Всех заданий с прошлого чтения.
    public func takeAllJobs() -> Int {
        return allJobs.exchange(0, ordering: .relaxed)
    }

    /// Запустить k помощников (основной поток; прежние уходят). setup — на потоке помощника перед работой, возвращает
    /// завершение (выход из аудио-группы).
    public func start(_ k: Int, setup: @escaping @Sendable () -> (() -> Void)) {
        stop()
        let g: Int = generation.load(ordering: .acquiring)
        let n: Int = Swift.max(0, Swift.min(k, RenderPool.maxHelpers))
        if n == 0 { return }
        let set: Int = (g & 1) * RenderPool.maxHelpers
        for i in 0..<n {
            let sem: DispatchSemaphore = sems[set + i]
            let th = Thread { [self] in
                self.alive.wrappingAdd(1, ordering: .relaxed)
                let finish: () -> Void = setup()
                self.helperLoop(sem, g)
                finish()
                self.alive.wrappingAdd(-1, ordering: .relaxed)
            }
            th.name = "JAMbo render \(i + 1)"
            th.qualityOfService = .userInteractive
            th.stackSize = 1 << 19
            th.start()
        }
        helpers.store(n, ordering: .releasing)
    }

    /// Остановить помощников (основной поток): колбэк больше их не будит, потоки выходят.
    public func stop() {
        helpers.store(0, ordering: .releasing)
        let g: Int = generation.wrappingAdd(1, ordering: .acquiringAndReleasing).oldValue
        let set: Int = (g & 1) * RenderPool.maxHelpers
        for i in 0..<RenderPool.maxHelpers { sems[set + i].signal() }
    }

    private func helperLoop(_ sem: DispatchSemaphore, _ g: Int) {
        while generation.load(ordering: .acquiring) == g {
            sem.wait()
            if generation.load(ordering: .acquiring) != g { break }
            let mine: Int = work()
            if mine > 0 { helperJobs.wrappingAdd(mine, ordering: .relaxed) }
        }
    }

    /// Разобрать задания блока (любой поток); вернуть, сколько сделано.
    @inline(__always)
    private func work() -> Int {
        var mine: Int = 0
        while true {
            let v: Int = ticket.wrappingAdd(1, ordering: .acquiringAndReleasing).oldValue
            let idx: Int = v & 0xFFFF_FFFF
            let count: Int = v >> 32
            if idx >= count { break }
            active?.runJob(idx)
            mine += 1
            done.wrappingAdd(1, ordering: .releasing)
        }
        return mine
    }

    /// Колбэк: задания 0…count−1 на колбэке и помощниках; возврат — когда все сделаны.
    public func run(_ count: Int, _ t: RenderJobs) {
        if count <= 0 { return }
        allJobs.wrappingAdd(count, ordering: .relaxed)
        let h: Int = Swift.min(helpers.load(ordering: .acquiring), count - 1)
        if h <= 0 {
            var j: Int = 0
            while j < count {
                t.runJob(j)
                j += 1
            }
            return
        }
        active = t
        done.store(0, ordering: .relaxed)
        ticket.store(count << 32, ordering: .releasing)
        let set: Int = (generation.load(ordering: .relaxed) & 1) * RenderPool.maxHelpers
        var i: Int = 0
        while i < h {
            sems[set + i].signal()
            i += 1
        }
        _ = work()
        while done.load(ordering: .acquiring) < count {}
    }
}
