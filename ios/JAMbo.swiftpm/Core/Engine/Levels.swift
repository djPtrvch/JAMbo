import Foundation

// Уровни для измерителя справа и метров MIX (как Meter веба): колбэк пишет пики каждого блока — дорожки (после
// громкости микшера и Sidechain, до mute/solo, как узел vol веба) и выход мастера, — и снижение громкости от
// Sidechain; интерфейс читает новые блоки по таймеру (баллистика, пик-холд — вне колбэка). LUFS — Loudness.

/// Пики блоков по каналам: дорожки 0…maxTracks−1, выход мастера — Levels.master, референс (S15g) — Levels.ref.
/// Кольцо из ring блоков.
public final class Levels: @unchecked Sendable {
    public static let master = SoundData.maxTracks
    public static let ref = SoundData.maxTracks + 1
    public static let channels = SoundData.maxTracks + 2
    /// Значений на канал в блоке: пик L, пик R, наибольшее приглушение Sidechain (amount·e, 0…1).
    static let stride = 3
    static let ring = 64
    let data: UnsafeMutablePointer<Float>
    /// Всего записано блоков (пишет колбэк после блока).
    public let blocks = AtomicCounter()
    /// Громкость (LUFS) показанного канала.
    public let loudness = Loudness(sampleRate: AudioCore.sampleRate)

    public init() {
        let n = Levels.ring * Levels.channels * Levels.stride
        data = .allocate(capacity: n)
        data.initialize(repeating: 0, count: n)
    }

    deinit { data.deallocate() }

    /// Колбэк: значения текущего блока (до commit) — с нуля.
    @inline(__always)
    func begin() -> UnsafeMutablePointer<Float> {
        let slot = blocks.load() % Levels.ring
        let p = data + slot * Levels.channels * Levels.stride
        p.update(repeating: 0, count: Levels.channels * Levels.stride)
        return p
    }

    /// Колбэк: значения канала ch в текущем блоке.
    @inline(__always)
    func current(_ ch: Int) -> UnsafeMutablePointer<Float> {
        let slot = blocks.load() % Levels.ring
        return data + (slot * Levels.channels + ch) * Levels.stride
    }

    /// Колбэк: блок записан.
    @inline(__always)
    func commit(frames: Int) {
        loudness.end(frames)
        blocks.store(blocks.load() + 1)
    }

    /// Интерфейс: блоки после since (не больше ring) — для каждого вызов f(указатель на значения блока по каналам).
    /// Возвращает новый счётчик.
    public func read(since: Int, _ f: (UnsafePointer<Float>) -> Void) -> Int {
        let w = blocks.load()
        var k = Swift.max(since, w - Levels.ring + 1)
        while k < w {
            f(UnsafePointer(data + (k % Levels.ring) * Levels.channels * Levels.stride))
            k += 1
        }
        return w
    }

    /// Значение канала ch в блоке: 0 — пик L, 1 — пик R, 2 — приглушение Sidechain.
    @inline(__always)
    public static func value(_ block: UnsafePointer<Float>, _ ch: Int, _ k: Int) -> Float {
        return block[ch * stride + k]
    }
}

/// Громкость показанного канала, как в вебе: K-взвешивание (биквады Web Audio — highshelf 1682 Гц +4 dB и highpass
/// 38 Гц, Q 0,5 dB) по каналам; моментальная — средний квадрат последних 16384 отсчётов (сумма каналов), раз в 100 мс;
/// интегральная — по BS.1770 из этих блоков (пороги −70 LUFS и −10 LU, корзины по 0,1 LU — память не растёт).
public final class Loudness: @unchecked Sendable {
    static let window = 16384
    static let hop = 4800
    static let bins = 800
    static let absGate = -70.0
    static let ringBlocks = 512
    /// Что слушать: дорожка, Levels.master; −1 — ничего (ставит интерфейс).
    public let source = AtomicCounter()
    /// Сброс интегральной (интерфейс увеличивает счётчик).
    public let resetRequests = AtomicCounter()
    /// Моментальная и интегральная громкость, LUFS (−∞ — тишина или ещё нет блоков).
    public let momentary = AtomicFloat(-Float.infinity)
    public let integrated = AtomicFloat(-Float.infinity)

    let c: UnsafeMutablePointer<Double>
    /// Состояние биквадов (DF1, как Biquad.cpp): [канал][фильтр][x1, x2, y1, y2].
    let z: UnsafeMutablePointer<Double>
    /// Энергия блоков (сумма квадратов по каналам) и их длина.
    let energy: UnsafeMutablePointer<Double>
    let frames: UnsafeMutablePointer<Int>
    let binN: UnsafeMutablePointer<Double>
    let binE: UnsafeMutablePointer<Double>
    let zeros: UnsafeMutablePointer<Float>
    private var written = 0
    private var sinceHop = 0
    private var fed = false
    private var lastSource = -1
    private var lastReset = 0

    public init(sampleRate: Double) {
        c = .allocate(capacity: 10)
        EqCoeffs.coeffs(EqSpec.highShelf, 1682, 4, 0, sampleRate, c)
        EqCoeffs.coeffs(EqSpec.lowCut, 38, 0, 0.5, sampleRate, c + 5)
        z = .allocate(capacity: 16)
        z.initialize(repeating: 0, count: 16)
        energy = .allocate(capacity: Loudness.ringBlocks)
        energy.initialize(repeating: 0, count: Loudness.ringBlocks)
        frames = .allocate(capacity: Loudness.ringBlocks)
        frames.initialize(repeating: 0, count: Loudness.ringBlocks)
        binN = .allocate(capacity: Loudness.bins)
        binN.initialize(repeating: 0, count: Loudness.bins)
        binE = .allocate(capacity: Loudness.bins)
        binE.initialize(repeating: 0, count: Loudness.bins)
        zeros = .allocate(capacity: AudioCore.maxFrames)
        zeros.initialize(repeating: 0, count: AudioCore.maxFrames)
        source.store(-1)
    }

    deinit {
        c.deallocate(); z.deallocate(); energy.deallocate(); frames.deallocate(); binN.deallocate(); binE.deallocate()
        zeros.deallocate()
    }

    /// Колбэк: слушает ли громкость канал ch (заодно — смена канала и сброс).
    @inline(__always)
    func listens(_ ch: Int) -> Bool {
        let s = source.load()
        if s != lastSource {
            lastSource = s
            restart()
        }
        let r = resetRequests.load()
        if r != lastReset {
            lastReset = r
            clearIntegrated()
        }
        return s == ch && s >= 0
    }

    /// Новый канал: фильтры, окно и интегральная — с нуля.
    private func restart() {
        z.update(repeating: 0, count: 16)
        energy.update(repeating: 0, count: Loudness.ringBlocks)
        frames.update(repeating: 0, count: Loudness.ringBlocks)
        sinceHop = 0
        momentary.store(-Float.infinity)
        clearIntegrated()
    }

    private func clearIntegrated() {
        binN.update(repeating: 0, count: Loudness.bins)
        binE.update(repeating: 0, count: Loudness.bins)
        integrated.store(-Float.infinity)
    }

    /// Колбэк: n отсчётов показанного канала.
    func process(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ n: Int) {
        fed = true
        let e: Double = filter(l, z, n) + filter(r, z + 8, n)
        push(e, n)
    }

    /// Колбэк: конец блока; если показанный канал молчал (его не кормили) — тишина.
    func end(_ n: Int) {
        if !fed && listens(source.load()) {
            let zero: Double = filterSilence(z, n) + filterSilence(z + 8, n)
            push(zero, n)
        }
        fed = false
    }

    /// Сумма квадратов K-взвешенного сигнала канала (два биквада подряд).
    @inline(__always)
    private func filter(_ x: UnsafePointer<Float>, _ s: UnsafeMutablePointer<Double>, _ n: Int) -> Double {
        let a0: Double = c[0], a1: Double = c[1], a2: Double = c[2], a3: Double = c[3], a4: Double = c[4]
        let b0: Double = c[5], b1: Double = c[6], b2: Double = c[7], b3: Double = c[8], b4: Double = c[9]
        var x1: Double = s[0], x2: Double = s[1], y1: Double = s[2], y2: Double = s[3]
        var u1: Double = s[4], u2: Double = s[5], v1: Double = s[6], v2: Double = s[7]
        var sum: Double = 0
        var i = 0
        while i < n {
            let xi: Double = Double(x[i])
            let y: Double = a0 * xi + a1 * x1 + a2 * x2 - a3 * y1 - a4 * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = y
            let v: Double = b0 * y + b1 * u1 + b2 * u2 - b3 * v1 - b4 * v2
            u2 = u1; u1 = y; v2 = v1; v1 = v
            sum += v * v
            i += 1
        }
        // Денормалы после долгой тишины.
        if abs(y1) < 1e-30 && abs(v1) < 1e-30 { y1 = 0; y2 = 0; v1 = 0; v2 = 0 }
        s[0] = x1; s[1] = x2; s[2] = y1; s[3] = y2
        s[4] = u1; s[5] = u2; s[6] = v1; s[7] = v2
        return sum
    }

    /// Хвост фильтров на тишине.
    @inline(__always)
    private func filterSilence(_ s: UnsafeMutablePointer<Double>, _ n: Int) -> Double {
        if s[0] == 0 && s[1] == 0 && s[2] == 0 && s[3] == 0 && s[6] == 0 && s[7] == 0 { return 0 }
        return filter(UnsafePointer(zeros), s, Swift.min(n, AudioCore.maxFrames))
    }

    @inline(__always)
    private func push(_ e: Double, _ n: Int) {
        let k = written % Loudness.ringBlocks
        energy[k] = e
        frames[k] = n
        written += 1
        sinceHop += n
        if sinceHop < Loudness.hop { return }
        sinceHop = 0
        // Окно — последние 16384 отсчёта (целыми блоками), делится на длину окна, как буфер AnalyserNode веба.
        var sum: Double = 0
        var got = 0
        var j = written - 1
        while j >= 0 && j > written - 1 - Loudness.ringBlocks && got < Loudness.window {
            let q = j % Loudness.ringBlocks
            sum += energy[q]
            got += frames[q]
            j -= 1
        }
        let ms: Double = sum / Double(Loudness.window)
        momentary.store(ms > 1e-10 ? Float(-0.691 + 10 * log10(ms)) : -Float.infinity)
        integrate(ms)
    }

    /// Блок в интегральную: корзина по громкости, затем относительный порог (средняя минус 10 LU).
    private func integrate(_ e: Double) {
        let l: Double = e > 1e-10 ? -0.691 + 10 * log10(e) : -Double.infinity
        if l <= Loudness.absGate { return }
        let b: Int = Swift.min(Loudness.bins - 1, Int(((l - Loudness.absGate) * 10).rounded(.down)))
        binN[b] += 1
        binE[b] += e
        var n: Double = 0
        var s: Double = 0
        var i = 0
        while i < Loudness.bins {
            n += binN[i]
            s += binE[i]
            i += 1
        }
        let rel: Double = -0.691 + 10 * log10(s / n) - 10
        i = Swift.max(0, Int(((rel - Loudness.absGate) * 10).rounded(.up)))
        n = 0
        s = 0
        while i < Loudness.bins {
            n += binN[i]
            s += binE[i]
            i += 1
        }
        integrated.store(n > 0 ? Float(-0.691 + 10 * log10(s / n)) : -Float.infinity)
    }
}
