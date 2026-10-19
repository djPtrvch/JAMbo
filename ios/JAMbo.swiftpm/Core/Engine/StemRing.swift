import Synchronization

// Запись стемов (S11d): колбэк кладёт звук пишущихся каналов (дорожки и мастер) в одно кольцо без потерь,
// сообщения о блоках, начале и конце записи — в очередь в том же порядке; основной поток (StemCollector)
// забирает их по таймеру и собирает стемы. Кольцо выделяется при первом нажатии ● (prepare), не при запуске.

/// Сообщение колбэка о записи стема.
public struct StemMsg: Sendable {
    public enum Kind: Sendable { case none, started, data, ended, endAt }
    public var kind: Kind = .none
    public var channel: Int = 0
    /// data — кадров в блоке; ended — кадров в стеме; endAt — кадр конца записи (−1 — конец пока не виден).
    public var value: Int64 = 0
    /// data — начало блока в кольце (отсчётов от начала записи); ended — пропущено кадров (кольцо было полно).
    public var pos: Int = 0
}

public final class StemRing: @unchecked Sendable {
    /// Каналы: дорожки 0…maxTracks−1 и мастер.
    public static let channels = SeqData.maxTracks + 1
    public static let master = SeqData.maxTracks
    /// Отсчётов в кольце (стерео подряд): 2^22 — около 43 с стерео на всех; хватает и 17 каналам на секунду с лишним.
    static let capacity = 1 << 22

    public let msgs = SPSCQueue<StemMsg>(capacity: 16384, filler: StemMsg())
    private var buf: UnsafeMutablePointer<Float>?
    private let ready = Atomic<Bool>(false)
    /// Записано и прочитано отсчётов (растут без конца; индекс — по маске).
    private let written = Atomic<Int>(0)
    private let readTotal = Atomic<Int>(0)

    // Состояние колбэка.
    private let active = UnsafeMutablePointer<Bool>.allocate(capacity: StemRing.channels)
    private let startF = UnsafeMutablePointer<Int64>.allocate(capacity: StemRing.channels)
    private let endF = UnsafeMutablePointer<Int64>.allocate(capacity: StemRing.channels)
    private let count = UnsafeMutablePointer<Int64>.allocate(capacity: StemRing.channels)
    private let dropped = UnsafeMutablePointer<Int>.allocate(capacity: StemRing.channels)
    /// Гейт mute/solo дорожек по отсчётам блока (дорожка·maxFrames): пишет микшер, пока идёт запись.
    public let gate = UnsafeMutablePointer<Float>.allocate(capacity: SeqData.maxTracks * Sampler.maxFrames)
    /// Пишется ли хоть один канал (микшер заполняет gate).
    public private(set) var capturing = false

    public init() {
        active.initialize(repeating: false, count: StemRing.channels)
        startF.initialize(repeating: 0, count: StemRing.channels)
        endF.initialize(repeating: Int64.max, count: StemRing.channels)
        count.initialize(repeating: 0, count: StemRing.channels)
        dropped.initialize(repeating: 0, count: StemRing.channels)
        gate.initialize(repeating: 1, count: SeqData.maxTracks * Sampler.maxFrames)
    }

    deinit {
        buf?.deallocate()
        active.deallocate()
        startF.deallocate()
        endF.deallocate()
        count.deallocate()
        dropped.deallocate()
        gate.deallocate()
    }

    /// Основной поток, при нажатии ●: выделить кольцо (один раз).
    public func prepare() {
        if ready.load(ordering: .acquiring) { return }
        let b = UnsafeMutablePointer<Float>.allocate(capacity: StemRing.capacity)
        b.initialize(repeating: 0, count: StemRing.capacity)
        buf = b
        ready.store(true, ordering: .releasing)
    }

    public var isReady: Bool { return ready.load(ordering: .acquiring) }

    // MARK: — колбэк

    /// Начать запись канала с кадра at.
    func begin(_ ch: Int, at: Int64) {
        if !isReady || active[ch] { return }
        active[ch] = true
        startF[ch] = at
        endF[ch] = Int64.max
        count[ch] = 0
        dropped[ch] = 0
        capturing = true
        msgs.push(StemMsg(kind: .started, channel: ch, value: 0, pos: 0))
    }

    /// Конец записи канала в кадре at (последний кадр стема — at − 1).
    func end(_ ch: Int, at: Int64) {
        if !active[ch] { return }
        endF[ch] = Swift.max(at, startF[ch])
    }

    /// Ожидаемый конец записи (для частого мигания за 5 с до конца); −1 — не виден.
    func endAt(_ ch: Int, frame: Int64) {
        msgs.push(StemMsg(kind: .endAt, channel: ch, value: frame, pos: 0))
    }

    /// Блок канала [blockStart, blockStart + n): l · g (g — гейт по отсчётам или nil), r · g — часть внутри окна записи.
    func capture(_ ch: Int, _ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ g: UnsafePointer<Float>?,
                 blockStart: Int64, frames n: Int) {
        if !active[ch] { return }
        let a: Int64 = Swift.max(startF[ch], blockStart)
        let e: Int64 = Swift.min(endF[ch], blockStart + Int64(n))
        if e > a, let b = buf {
            let from = Int(a - blockStart)
            let k = Int(e - a)
            let w = written.load(ordering: .relaxed)
            let rd = readTotal.load(ordering: .acquiring)
            if w + 2 * k - rd > StemRing.capacity {
                dropped[ch] += k
            } else {
                let mask = StemRing.capacity - 1
                var i = 0
                var p = w
                if let gg = g {
                    while i < k {
                        b[p & mask] = l[from + i] * gg[from + i]
                        b[(p + 1) & mask] = r[from + i] * gg[from + i]
                        p += 2
                        i += 1
                    }
                } else {
                    while i < k {
                        b[p & mask] = l[from + i]
                        b[(p + 1) & mask] = r[from + i]
                        p += 2
                        i += 1
                    }
                }
                // Очередь полна — блок не считается записанным (место в кольце займёт следующий).
                if msgs.push(StemMsg(kind: .data, channel: ch, value: Int64(k), pos: w)) {
                    written.store(p, ordering: .releasing)
                    count[ch] += Int64(k)
                } else {
                    dropped[ch] += k
                }
            }
        }
        if blockStart + Int64(n) >= endF[ch] {
            active[ch] = false
            msgs.push(StemMsg(kind: .ended, channel: ch, value: count[ch], pos: dropped[ch]))
            var any = false
            var c = 0
            while c < StemRing.channels {
                if active[c] { any = true }
                c += 1
            }
            capturing = any
        }
    }

    // MARK: — основной поток

    /// Скопировать k кадров блока с позиции pos в l и r и освободить место в кольце.
    func read(pos: Int, frames k: Int, into l: inout [Float], _ r: inout [Float]) {
        guard let b = buf else { return }
        let mask = StemRing.capacity - 1
        var p = pos
        var i = 0
        while i < k {
            l.append(b[p & mask])
            r.append(b[(p + 1) & mask])
            p += 2
            i += 1
        }
        readTotal.store(p, ordering: .releasing)
    }
}

/// Основной поток: собирает стемы из сообщений кольца (вызывать по таймеру).
public final class StemCollector {
    private var left: [[Float]] = Array(repeating: [], count: StemRing.channels)
    private var right: [[Float]] = Array(repeating: [], count: StemRing.channels)
    /// Каналы, которые сейчас пишутся.
    public private(set) var recording: Set<Int> = []
    /// Ожидаемый кадр конца записи канала (если виден).
    public private(set) var endAt: [Int: Int64] = [:]

    public init() {}

    /// Готовые стемы: канал, звук и пропущено ли что-то (кольцо было полно).
    public func poll(_ ring: StemRing) -> [(channel: Int, data: SampleData, dropped: Int)] {
        var done: [(channel: Int, data: SampleData, dropped: Int)] = []
        while let m = ring.msgs.pop() {
            let c = m.channel
            switch m.kind {
            case .none:
                break
            case .started:
                left[c] = []
                right[c] = []
                recording.insert(c)
                endAt[c] = nil
            case .data:
                ring.read(pos: m.pos, frames: Int(m.value), into: &left[c], &right[c])
            case .endAt:
                endAt[c] = m.value >= 0 ? m.value : nil
            case .ended:
                recording.remove(c)
                endAt[c] = nil
                if !left[c].isEmpty {
                    done.append((c, SampleData(left: left[c], right: right[c]), m.pos))
                }
                left[c] = []
                right[c] = []
            }
        }
        return done
    }
}
