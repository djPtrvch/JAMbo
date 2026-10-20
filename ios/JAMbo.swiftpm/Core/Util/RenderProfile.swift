import Foundation
import Synchronization

/// Замеры колбэка по разделам (S14a): метки на уровне блока (не на отсчёт) — время от прошлой метки идёт в раздел.
/// Метки ставят AudioCore, Sampler и MasterChain; выключенный замер (тесты) — одна проверка на метку.
/// Каждую секунду звука — средняя доля блока и наибольшая доля одного блока по разделам и всего, и наибольшая доля
/// с последнего сброса (RESET в DIAGNOSTICS) — seqlock, как PlayClock.
public final class RenderProfile: @unchecked Sendable {
    /// Разделы: секвенсор (снимки, команды, транспорт, начало MOD и FX), голоса сэмплера (и прослушивание), голоса синта,
    /// EQ дорожек и мастера, микшер, FX (посылы и Sidechain), мастер (SAT, COMP, CLIP, LIM, выход), метры, скоп,
    /// спектры и запись стемов.
    public static let seq = 0, voices = 1, synth = 2, eq = 3, mix = 4, fx = 5, master = 6, meters = 7
    public static let count = 8
    public static let names: [String] = ["Seq", "Samples", "Synth", "EQ", "Mix", "FX", "Master", "Meters"]

    /// Итог окна: доли длительности блока (1 — весь блок), по разделам и всего (индекс count).
    public struct Stats: Sendable {
        public var avg: [Float]
        public var peak: [Float]
        /// Наибольшая доля блока с последнего сброса.
        public var worst: [Float]
        /// Блоков в окне.
        public var blocks: Int
    }

    private let sampleRate: Double
    private let window: Int
    private let flag = Atomic<Int>(0)
    private var active = false
    private var last: UInt64 = 0
    /// Время текущего блока и сумма окна по разделам (нс), наибольшая доля блока за окно (индекс count — весь блок).
    private let block = UnsafeMutablePointer<Double>.allocate(capacity: RenderProfile.count + 1)
    private let sum = UnsafeMutablePointer<Double>.allocate(capacity: RenderProfile.count + 1)
    private let peakNow = UnsafeMutablePointer<Double>.allocate(capacity: RenderProfile.count + 1)
    private let worst = UnsafeMutablePointer<Double>.allocate(capacity: RenderProfile.count + 1)
    private let resetFlag = Atomic<Int>(0)
    private var frames = 0
    private var blocks = 0
    /// Опубликованное окно: avg, peak, worst (по count + 1); число блоков — в blocksOut.
    private let out = UnsafeMutablePointer<Float>.allocate(capacity: 3 * (RenderProfile.count + 1))
    private let version = Atomic<Int>(0)
    private let blocksOut = Atomic<Int>(0)

    public init(sampleRate: Double, windowSeconds: Double = 1) {
        self.sampleRate = sampleRate
        window = Int(sampleRate * windowSeconds)
        block.initialize(repeating: 0, count: RenderProfile.count + 1)
        sum.initialize(repeating: 0, count: RenderProfile.count + 1)
        peakNow.initialize(repeating: 0, count: RenderProfile.count + 1)
        worst.initialize(repeating: 0, count: RenderProfile.count + 1)
        out.initialize(repeating: 0, count: 3 * (RenderProfile.count + 1))
        // Первый вызов часов (ленивые данные перевода тиков в нс) — здесь, не в колбэке.
        _ = RenderProfile.now()
    }

    deinit {
        block.deallocate()
        sum.deallocate()
        peakNow.deallocate()
        worst.deallocate()
        out.deallocate()
    }

    /// Включить или выключить замер (интерфейс; колбэк подхватит со следующего блока, окно начнётся заново).
    public var enabled: Bool {
        get { return flag.load(ordering: .relaxed) != 0 }
        set { flag.store(newValue ? 1 : 0, ordering: .relaxed) }
    }

    /// Сбросить наибольшие значения (интерфейс; колбэк сбросит в начале следующего блока).
    public func resetWorst() {
        resetFlag.store(1, ordering: .relaxed)
    }

    /// Монотонное время, нс (без выделений: на Apple — mach_absolute_time).
    @inline(__always)
    static func now() -> UInt64 {
        return DispatchTime.now().uptimeNanoseconds
    }

    /// Колбэк: начало блока.
    @inline(__always)
    public func begin() {
        let on: Bool = flag.load(ordering: .relaxed) != 0
        if !on {
            if active {
                active = false
                reset()
            }
            return
        }
        active = true
        let clear: Bool = resetFlag.load(ordering: .relaxed) != 0
        if clear { resetFlag.store(0, ordering: .relaxed) }
        var k = 0
        while k <= RenderProfile.count {
            block[k] = 0
            if clear { worst[k] = 0 }
            k += 1
        }
        last = RenderProfile.now()
    }

    /// Колбэк: время от прошлой метки — в раздел section.
    @inline(__always)
    public func lap(_ section: Int) {
        if !active { return }
        let t: UInt64 = RenderProfile.now()
        block[section] += Double(t &- last)
        last = t
    }

    /// Колбэк: конец блока из n кадров.
    @inline(__always)
    public func end(frames n: Int) {
        if !active || n <= 0 { return }
        let c: Int = RenderProfile.count
        var total: Double = 0
        var k = 0
        while k < c {
            total += block[k]
            k += 1
        }
        block[c] = total
        k = 0
        while k <= c {
            sum[k] += block[k]
            k += 1
        }
        // Пик — доля своего блока: блоки разной длины сравниваются по доле.
        let blockNs: Double = Double(n) / sampleRate * 1e9
        k = 0
        while k <= c {
            let share: Double = block[k] / blockNs
            if share > peakNow[k] { peakNow[k] = share }
            if share > worst[k] { worst[k] = share }
            k += 1
        }
        frames += n
        blocks += 1
        if frames >= window { publish() }
    }

    /// Окно → опубликованные значения.
    private func publish() {
        let c: Int = RenderProfile.count
        let wallNs: Double = Double(frames) / sampleRate * 1e9
        let v: Int = version.load(ordering: .relaxed)
        version.store(v + 1, ordering: .relaxed)
        atomicMemoryFence(ordering: .releasing)
        var k = 0
        while k <= c {
            out[k] = Float(sum[k] / wallNs)
            out[c + 1 + k] = Float(peakNow[k])
            out[2 * (c + 1) + k] = Float(worst[k])
            k += 1
        }
        blocksOut.store(blocks, ordering: .relaxed)
        version.store(v + 2, ordering: .releasing)
        reset()
    }

    private func reset() {
        var k = 0
        while k <= RenderProfile.count {
            sum[k] = 0
            peakNow[k] = 0
            k += 1
        }
        frames = 0
        blocks = 0
    }

    /// Интерфейс: последнее окно (nil — ещё не было).
    public func read() -> Stats? {
        let c: Int = RenderProfile.count
        while true {
            let v0: Int = version.load(ordering: .acquiring)
            if v0 == 0 { return nil }
            if v0 & 1 == 1 { continue }
            var avg: [Float] = []
            var peak: [Float] = []
            var high: [Float] = []
            for k in 0...c {
                avg.append(out[k])
                peak.append(out[c + 1 + k])
                high.append(out[2 * (c + 1) + k])
            }
            let b: Int = blocksOut.load(ordering: .relaxed)
            atomicMemoryFence(ordering: .acquiring)
            if version.load(ordering: .relaxed) == v0 { return Stats(avg: avg, peak: peak, worst: high, blocks: b) }
        }
    }
}
