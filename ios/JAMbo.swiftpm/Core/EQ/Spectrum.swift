import Foundation

// Спектры EQ (как AnalyserNode веба: моно (L + R)/2, окно Блэкмана, FFT 4096, |X|/N, сглаживание 0,6 между
// чтениями, dB). Колбэк пишет сигнал в кольцевые буферы точек съёма (SpectrumTap), интерфейс читает последние
// 4096 отсчётов и считает спектр (SpectrumAnalyzer) — вне колбэка. Точки съёма (Spectra): до и после EQ показанного
// канала, после EQ сравниваемой дорожки, конечный выход мастера; канал — атомарное значение (−1 — съём выключен).

/// Кольцевой буфер точки съёма: пишет колбэк, читает интерфейс (без блокировок; разрыв на стыке — только в картинке).
public final class SpectrumTap: @unchecked Sendable {
    static let capacity = 8192
    static let mask = capacity - 1
    let buf: UnsafeMutablePointer<Float>
    /// Всего записано отсчётов.
    let written = AtomicCounter()

    public init() {
        buf = .allocate(capacity: SpectrumTap.capacity)
        buf.initialize(repeating: 0, count: SpectrumTap.capacity)
    }

    deinit { buf.deallocate() }

    /// Колбэк: n отсчётов стерео → моно (L + R)/2.
    @inline(__always)
    public func push(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ n: Int) {
        let b = buf
        let m = SpectrumTap.mask
        let w = written.load()
        var i = 0
        while i < n {
            b[(w + i) & m] = 0.5 * (l[i] + r[i])
            i += 1
        }
        written.store(w + n)
    }

    /// Колбэк: n отсчётов тишины (канал молчит).
    @inline(__always)
    public func pushSilence(_ n: Int) {
        let b = buf
        let m = SpectrumTap.mask
        let w = written.load()
        var i = 0
        while i < n {
            b[(w + i) & m] = 0
            i += 1
        }
        written.store(w + n)
    }

    /// Интерфейс: последние count отсчётов (count ≤ 4096).
    public func read(into out: UnsafeMutablePointer<Float>, count: Int) {
        let w = written.load()
        var i = 0
        while i < count {
            out[i] = buf[(w - count + i) & SpectrumTap.mask]
            i += 1
        }
    }
}

/// Точки съёма спектров EQ и что они слушают (ставит интерфейс, читает колбэк).
public final class Spectra: @unchecked Sendable {
    public let pre = SpectrumTap()
    public let post = SpectrumTap()
    public let compare = SpectrumTap()
    public let out = SpectrumTap()
    /// Канал EQ на экране (дорожка, EqSpec.masterChannel; −1 — EQ закрыт): до и после его EQ.
    public let channel = AtomicCounter()
    /// Дорожка для сравнения (после её EQ; −1 — нет).
    public let compareTrack = AtomicCounter()
    /// Спектр конечного выхода мастера включён (1).
    public let outOn = AtomicCounter()

    public init() {
        channel.store(-1)
        compareTrack.store(-1)
    }
}

/// Спектр как getFloatFrequencyData у AnalyserNode (fftSize 4096, smoothingTimeConstant 0,6): 2048 бинов, dB.
public final class SpectrumAnalyzer {
    public static let size = 4096
    public static let bins = size / 2
    static let smoothing: Float = 0.6
    let window: UnsafeMutablePointer<Float>
    let input: UnsafeMutablePointer<Float>
    /// Сглаженная амплитуда по бинам (между чтениями).
    let mag: UnsafeMutablePointer<Float>
    let fft: RealFFT
    let re: UnsafeMutablePointer<Float>
    let im: UnsafeMutablePointer<Float>
    /// Спектр в dB (bins значений) после analyze.
    public let db: UnsafeMutablePointer<Float>

    public init() {
        let n = SpectrumAnalyzer.size
        window = .allocate(capacity: n)
        // Окно Блэкмана (alpha 0,16), как в спецификации AnalyserNode.
        for i in 0..<n {
            let x: Double = 2 * Double.pi * Double(i) / Double(n)
            window[i] = Float(0.42 - 0.5 * cos(x) + 0.08 * cos(2 * x))
        }
        input = .allocate(capacity: n)
        input.initialize(repeating: 0, count: n)
        mag = .allocate(capacity: SpectrumAnalyzer.bins)
        mag.initialize(repeating: 0, count: SpectrumAnalyzer.bins)
        re = .allocate(capacity: SpectrumAnalyzer.bins)
        im = .allocate(capacity: SpectrumAnalyzer.bins)
        re.initialize(repeating: 0, count: SpectrumAnalyzer.bins)
        im.initialize(repeating: 0, count: SpectrumAnalyzer.bins)
        db = .allocate(capacity: SpectrumAnalyzer.bins)
        db.initialize(repeating: -240, count: SpectrumAnalyzer.bins)
        fft = RealFFT(size: n)
    }

    deinit {
        for p in [window, input, mag, re, im, db] { p.deallocate() }
    }

    /// Спектр последних 4096 отсчётов точки съёма → db.
    public func analyze(_ tap: SpectrumTap) {
        tap.read(into: input, count: SpectrumAnalyzer.size)
        analyzeInput()
    }

    /// Спектр сигнала x (4096 отсчётов) → db (тесты).
    public func analyze(_ x: [Float]) {
        for i in 0..<SpectrumAnalyzer.size { input[i] = i < x.count ? x[i] : 0 }
        analyzeInput()
    }

    private func analyzeInput() {
        let n = SpectrumAnalyzer.size
        var i = 0
        while i < n {
            input[i] *= window[i]
            i += 1
        }
        fft.forward(input, re, im)
        let scale: Float = 1 / Float(n)
        let k = SpectrumAnalyzer.smoothing
        i = 0
        while i < SpectrumAnalyzer.bins {
            let a: Float = (re[i] * re[i] + im[i] * im[i]).squareRoot() * scale
            var m: Float = k * mag[i] + (1 - k) * a
            if !m.isFinite { m = 0 }
            mag[i] = m
            db[i] = m > 0 ? 20 * log10(m) : -240
            i += 1
        }
    }
}

/// БПФ вещественного сигнала длины size (степень двойки): комплексное БПФ size/2 точек (чётные — Re, нечётные — Im) и
/// разделение спектра. Выход — бины 0…size/2−1 (Re, Im). Вне колбэка.
public final class RealFFT {
    let n: Int
    let half: Int
    let bits: Int
    let cr: UnsafeMutablePointer<Float>
    let ci: UnsafeMutablePointer<Float>
    /// Множители комплексного БПФ (half/2) и разделения (half): cos и −sin.
    let wc: UnsafeMutablePointer<Float>
    let ws: UnsafeMutablePointer<Float>
    let sc: UnsafeMutablePointer<Float>
    let ss: UnsafeMutablePointer<Float>
    let rev: UnsafeMutablePointer<Int>

    public init(size: Int) {
        n = size
        half = size / 2
        var b = 0
        while (1 << b) < half { b += 1 }
        bits = b
        cr = .allocate(capacity: half)
        ci = .allocate(capacity: half)
        wc = .allocate(capacity: half / 2)
        ws = .allocate(capacity: half / 2)
        for k in 0..<half / 2 {
            let a: Double = -2 * Double.pi * Double(k) / Double(half)
            wc[k] = Float(cos(a))
            ws[k] = Float(sin(a))
        }
        sc = .allocate(capacity: half)
        ss = .allocate(capacity: half)
        for k in 0..<half {
            let a: Double = -2 * Double.pi * Double(k) / Double(size)
            sc[k] = Float(cos(a))
            ss[k] = Float(sin(a))
        }
        rev = .allocate(capacity: half)
        for i in 0..<half {
            var r = 0
            var x = i
            for _ in 0..<b {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            rev[i] = r
        }
    }

    deinit {
        for p in [cr, ci, wc, ws, sc, ss] { p.deallocate() }
        rev.deallocate()
    }

    /// x (n отсчётов) → re, im (n/2 бинов).
    public func forward(_ x: UnsafePointer<Float>, _ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>) {
        let h = half
        let cr = self.cr, ci = self.ci, wc = self.wc, ws = self.ws, rev = self.rev
        var i = 0
        while i < h {
            let j = rev[i]
            cr[j] = x[2 * i]
            ci[j] = x[2 * i + 1]
            i += 1
        }
        // Комплексное БПФ (по основанию 2, на месте).
        var len = 2
        while len <= h {
            let hl = len / 2
            let step = h / len
            var s = 0
            while s < h {
                var k = 0
                while k < hl {
                    let c = wc[k * step], sn = ws[k * step]
                    let a = s + k, b = a + hl
                    let tr: Float = cr[b] * c - ci[b] * sn
                    let ti: Float = cr[b] * sn + ci[b] * c
                    cr[b] = cr[a] - tr
                    ci[b] = ci[a] - ti
                    cr[a] += tr
                    ci[a] += ti
                    k += 1
                }
                s += len
            }
            len <<= 1
        }
        // Разделение: X[k] = (Z[k] + Z*[h−k])/2 + e^(−2πik/n)·(Z[k] − Z*[h−k])/(2i).
        let sc = self.sc, ss = self.ss
        var k = 0
        while k < h {
            let m = k == 0 ? 0 : h - k
            let zr = cr[k], zi = ci[k], yr = cr[m], yi = -ci[m]
            let er: Float = 0.5 * (zr + yr), ei: Float = 0.5 * (zi + yi)
            // (Z − conj)/(2i): (a + ib)/(2i) = (b − ia)/2.
            let dr: Float = zr - yr, di: Float = zi - yi
            let or: Float = 0.5 * di, oi: Float = -0.5 * dr
            re[k] = er + sc[k] * or - ss[k] * oi
            im[k] = ei + sc[k] * oi + ss[k] * or
            k += 1
        }
    }
}
