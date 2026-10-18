import Foundation

// Таблицы движка WTABLE (как src/audio/wavetable.ts веба): встроенные генерируются по спектру кадров (гармоники
// 1…1023 при кадре 2048); мипмапы по октавам — обратным FFT с обрезкой гармоник (уровень L — гармоники до 1024 >> L),
// вне аудиопотока. Ключ таблицы дорожки (Track.table): "" — BASIC, "builtin:NAME" — встроенная.
// Свои таблицы (WAV из библиотеки) — S11.

public enum WavetableKey {
    public static let builtins = ["BASIC", "PWM", "ORGAN", "FORMANT", "DIGITAL", "METAL"]

    /// Ключ встроенной таблицы.
    public static func builtin(_ name: String) -> String { name == "BASIC" ? "" : "builtin:" + name }

    /// Имя таблицы для показа.
    public static func name(_ key: String) -> String {
        if key.isEmpty { return "BASIC" }
        if key.hasPrefix("builtin:") { return String(key.dropFirst(8)) }
        return "TABLE"
    }
}

/// Таблица: кадров frames, 11 уровней мипмапа (размер и данные frames × size). Живёт, пока на неё ссылаются
/// (кэш WavetableStore и снимки звука); колбэк читает только указатели.
public final class WtTable: @unchecked Sendable {
    public static let tableSize = 2048
    public static let builtinFrames = 64
    public static let levelCount = 11
    static let harmonics = tableSize / 2 - 1

    public let frames: Int
    public let sizes: UnsafeMutablePointer<Int>
    public let data: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    init(frames: Int) {
        self.frames = frames
        sizes = .allocate(capacity: WtTable.levelCount)
        data = .allocate(capacity: WtTable.levelCount)
        for l in 0..<WtTable.levelCount {
            let h = 1024 >> l
            let size = Swift.min(WtTable.tableSize, Swift.max(256, 4 * h))
            sizes[l] = size
            data[l] = .allocate(capacity: frames * size)
            data[l].initialize(repeating: 0, count: frames * size)
        }
    }

    deinit {
        for l in 0..<WtTable.levelCount { data[l].deallocate() }
        sizes.deallocate()
        data.deallocate()
    }

    // MARK: — построение

    /// Встроенная таблица по имени (BASIC — и для неизвестного).
    public static func builtin(_ name: String) -> WtTable {
        let sp = builtinSpectra(name)
        return buildMips(sp, perFrame: true)
    }

    /// Спектр кадров: re/im гармоник 1…harmonics.
    struct Spectra {
        let frames: Int
        var re: [[Double]]
        var im: [[Double]]
    }

    static func fft(_ re: inout [Double], _ im: inout [Double], inverse: Bool) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        let sign: Double = inverse ? 1 : -1
        var len = 2
        while len <= n {
            let a = sign * 2 * Double.pi / Double(len)
            let wr0 = cos(a), wi0 = sin(a)
            var i = 0
            while i < n {
                var wr = 1.0, wi = 0.0
                for k in 0..<(len / 2) {
                    let p = i + k, q = p + len / 2
                    let xr = re[q] * wr - im[q] * wi, xi = re[q] * wi + im[q] * wr
                    re[q] = re[p] - xr
                    im[q] = im[p] - xi
                    re[p] += xr
                    im[p] += xi
                    let t = wr * wr0 - wi * wi0
                    wi = wr * wi0 + wi * wr0
                    wr = t
                }
                i += len
            }
            len <<= 1
        }
    }

    /// Мипмапы из спектров; perFrame — каждый кадр к пику 1.0 (встроенные), иначе вся таблица к пику 1.0.
    static func buildMips(_ sp: Spectra, perFrame: Bool) -> WtTable {
        let table = WtTable(frames: sp.frames)
        var peaks = [Double](repeating: 0, count: sp.frames)
        for l in 0..<levelCount {
            let h = 1024 >> l
            let size = table.sizes[l]
            let lim = Swift.min(h, size / 2 - 1, harmonics)
            let out = table.data[l]
            var re = [Double](repeating: 0, count: size)
            var im = [Double](repeating: 0, count: size)
            for f in 0..<sp.frames {
                for k in 0..<size {
                    re[k] = 0
                    im[k] = 0
                }
                if lim >= 1 {
                    for n in 1...lim {
                        re[n] = sp.re[f][n]
                        im[n] = sp.im[f][n]
                        re[size - n] = sp.re[f][n]
                        im[size - n] = -sp.im[f][n]
                    }
                }
                fft(&re, &im, inverse: true)
                for k in 0..<size {
                    out[f * size + k] = Float(re[k])
                    if l == 0 { peaks[f] = Swift.max(peaks[f], abs(re[k])) }
                }
            }
        }
        let all = peaks.max() ?? 0
        for l in 0..<levelCount {
            let size = table.sizes[l]
            let out = table.data[l]
            for f in 0..<sp.frames {
                let pk = perFrame ? peaks[f] : all
                let g = pk > 0 ? 1 / pk : 1
                for k in (f * size)..<((f + 1) * size) { out[k] = Float(Double(out[k]) * g) }
            }
        }
        return table
    }

    /// Спектры из амплитуд (синусная фаза или своя): a·sin(nx + φ) → коэффициент (a/2)·e^{i(φ − π/2)}.
    static func spectraFrom(_ frames: Int, _ amp: (Double, Int) -> Double,
                            _ phase: (Double, Int) -> Double = { _, _ in 0 }) -> Spectra {
        var re: [[Double]] = [], im: [[Double]] = []
        for f in 0..<frames {
            let t = frames > 1 ? Double(f) / Double(frames - 1) : 0
            var r = [Double](repeating: 0, count: harmonics + 1)
            var i = [Double](repeating: 0, count: harmonics + 1)
            for n in 1...harmonics {
                let a = amp(t, n)
                if a == 0 { continue }
                let ph = phase(t, n) - Double.pi / 2
                r[n] = a / 2 * cos(ph)
                i[n] = a / 2 * sin(ph)
            }
            re.append(r)
            im.append(i)
        }
        return Spectra(frames: frames, re: re, im: im)
    }

    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

    /// Встроенные таблицы: 64 кадра × 2048.
    static func builtinSpectra(_ name: String) -> Spectra {
        let fr = builtinFrames
        switch name {
        case "PWM":
            // Импульс: ширина 50 % → 5 %.
            return spectraFrom(fr, { t, n in
                (2 / (Double(n) * Double.pi)) * sin(Double(n) * Double.pi * lerp(0.5, 0.05, t))
            }, { _, _ in Double.pi / 2 })
        case "ORGAN":
            // Дроубары (гармоники 1, 2, 3, 4, 5, 6, 8, 10, 12, 16): регистровки сменяют друг друга.
            let bars = [1, 2, 3, 4, 5, 6, 8, 10, 12, 16]
            let regs: [[Double]] = [
                [8, 8, 0, 0, 0, 0, 0, 0, 0, 0], [8, 8, 8, 0, 0, 0, 0, 0, 0, 0], [8, 6, 8, 4, 0, 3, 0, 0, 0, 0],
                [8, 8, 8, 8, 0, 0, 0, 0, 0, 8], [6, 8, 8, 6, 4, 4, 3, 2, 2, 4], [8, 8, 8, 8, 8, 8, 8, 8, 8, 8],
            ]
            return spectraFrom(fr) { t, n in
                guard let k = bars.firstIndex(of: n) else { return 0 }
                let x = t * Double(regs.count - 1)
                let i = Swift.min(regs.count - 2, Int(x.rounded(.down)))
                return lerp(regs[i][k], regs[i + 1][k], x - Double(i)) / 8 / Double(n).squareRoot()
            }
        case "FORMANT":
            // Гласные A, E, I, O, U аддитивно: огибающая трёх формант (тон таблицы ~110 Гц).
            let v: [[Double]] = [[800, 1150, 2900], [400, 1600, 2700], [350, 2300, 3000], [450, 800, 2830], [325, 700, 2530]]
            let w: [Double] = [1, 0.6, 0.3]
            return spectraFrom(fr) { t, n in
                let x = t * Double(v.count - 1)
                let i = Swift.min(v.count - 2, Int(x.rounded(.down)))
                let u = x - Double(i)
                let hz = Double(n) * 110
                if hz > 6000 { return 0 }
                var a = 0.0
                for k in 0..<3 {
                    let fc = lerp(v[i][k], v[i + 1][k], u), bw = 60 + fc * 0.08
                    a += w[k] * exp(-0.5 * pow((hz - fc) / bw, 2))
                }
                return a
            }
        case "DIGITAL":
            // Наборы гармоник: число гармоник растёт с кадром, фазы случайные — «цифровой» тембр.
            var s: UInt64 = 7
            var ph = [Double](repeating: 0, count: harmonics + 1)
            for k in 0...harmonics {
                s = (s &* 1664525 &+ 1013904223) & 0xFFFF_FFFF
                ph[k] = Double(s) / 4294967296 * Double.pi * 2
            }
            return spectraFrom(fr, { t, n in
                let top = 1 + Int((t * 63).rounded(.down))
                if n > top * 4 { return 0 }
                return (n & (1 + Int((t * 7).rounded(.down)))) != 0 || n == 1 ? 1 / Double(n).squareRoot() : 0
            }, { _, n in ph[n] })
        case "METAL":
            // Инхармонические партиалы (моды стержня), растянутые вверх с кадром — металлический тон.
            let modes: [Double] = [1, 2.756, 5.404, 8.933, 13.344, 18.64]
            return spectraFrom(fr) { t, n in
                let base = lerp(2, 14, t)
                var a = 0.0
                for (k, m) in modes.enumerated() where jsRound(m * base) == n { a += 1 / Double(k + 1) }
                return a + (n == 1 ? 0.3 : 0)
            }
        default:
            // BASIC: синус → пила (первая половина кадров) → квадрат (вторая).
            return spectraFrom(fr) { t, n in
                let saw = 1 / Double(n), sq = n % 2 == 1 ? 1 / Double(n) : 0
                if t < 0.5 {
                    let u = t * 2
                    return (n == 1 ? 1 - u : 0) + u * saw
                }
                let u = (t - 0.5) * 2
                return (1 - u) * saw + u * sq
            }
        }
    }

    /// Math.round: половина — вверх.
    static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
}

/// Кэш таблиц (основной поток): встроенные строятся вне основного потока и остаются в памяти.
public final class WavetableStore {
    public private(set) var ready: [String: WtTable] = [:]
    private var building: Set<String> = []

    public init() {}

    /// Таблица по ключу, если готова; иначе — построение в фоне, done — в основном потоке, когда готова.
    public func table(_ key: String, done: @escaping () -> Void) -> WtTable? {
        if let t = ready[key] { return t }
        if building.contains(key) { return nil }
        building.insert(key)
        let name = WavetableKey.name(key)
        DispatchQueue.global(qos: .userInitiated).async {
            let t = WtTable.builtin(name)
            DispatchQueue.main.async {
                self.ready[key] = t
                self.building.remove(key)
                done()
            }
        }
        return nil
    }
}
