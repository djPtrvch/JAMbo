import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

// Room (Headphone Monitor, фаза 2): свёртка 2×2 — outL = L∗h_LL + R∗h_RL, outR = L∗h_LR + R∗h_RR. Равномерное
// разбиение на партиции по 128 отсчётов (БПФ 256, overlap-save, частотная линия задержки), добавленная задержка —
// 128 отсчётов (2,7 мс при 48 кГц). Прямая часть (первые direct отсчётов) и хвост — в разных сумматорах: выход
// = прямая + Ambience · хвост (громкость хвоста — плавно, без пересчёта импульсов). БПФ — PvFFT (vDSP на iPad).
// Экземпляр (RoomConv) готовится вне колбэка; смена комнаты — кроссфейд 40 мс между экземплярами (RoomStage).

/// Одна свёртка (одна комната): спектры партиций импульсов и состояние.
public final class RoomConv: @unchecked Sendable {
    public static let part = 128
    static let size = 256
    static let bins = 129
    public let name: String
    let parts: Int
    /// Партиции прямой части (первые direct отсчётов).
    let directParts: Int
    let fft: PvFFT
    /// Спектры импульсов: [путь][партиция][бин] (путь — LL, LR, RL, RR).
    let hr: UnsafeMutablePointer<Float>
    let hi: UnsafeMutablePointer<Float>
    /// Линия задержки спектров входа: [канал][место][бин].
    let xr: UnsafeMutablePointer<Float>
    let xi: UnsafeMutablePointer<Float>
    var head = 0
    /// Сумматоры: прямая L, прямая R, хвост L, хвост R — по bins.
    let ar: UnsafeMutablePointer<Float>
    let ai: UnsafeMutablePointer<Float>
    /// Вход: прошлые 128 и новые 128 отсчётов каждого канала.
    let inL: UnsafeMutablePointer<Float>
    let inR: UnsafeMutablePointer<Float>
    let tmp: UnsafeMutablePointer<Float>
    /// Выход блока: прямая L, прямая R, хвост L, хвост R — по 128.
    let out: UnsafeMutablePointer<Float>

    public init(ir: RoomIR) {
        name = ir.name
        let p: Int = RoomConv.part
        let b: Int = RoomConv.bins
        parts = Swift.max(1, (ir.frames + p - 1) / p)
        directParts = Swift.max(1, Swift.min(parts, (ir.direct + p - 1) / p))
        fft = PvFFT(size: RoomConv.size)
        let hn: Int = 4 * parts * b
        hr = .allocate(capacity: hn)
        hi = .allocate(capacity: hn)
        hr.initialize(repeating: 0, count: hn)
        hi.initialize(repeating: 0, count: hn)
        xr = .allocate(capacity: 2 * parts * b)
        xi = .allocate(capacity: 2 * parts * b)
        xr.initialize(repeating: 0, count: 2 * parts * b)
        xi.initialize(repeating: 0, count: 2 * parts * b)
        ar = .allocate(capacity: 4 * b)
        ai = .allocate(capacity: 4 * b)
        ar.initialize(repeating: 0, count: 4 * b)
        ai.initialize(repeating: 0, count: 4 * b)
        inL = .allocate(capacity: RoomConv.size)
        inR = .allocate(capacity: RoomConv.size)
        tmp = .allocate(capacity: RoomConv.size)
        inL.initialize(repeating: 0, count: RoomConv.size)
        inR.initialize(repeating: 0, count: RoomConv.size)
        tmp.initialize(repeating: 0, count: RoomConv.size)
        out = .allocate(capacity: 4 * p)
        out.initialize(repeating: 0, count: 4 * p)
        // Спектры партиций (дополненных нулями до 256), с делением на масштаб круга БПФ.
        let scale: Float = 1 / fft.gain
        for path in 0..<4 {
            for k in 0..<parts {
                tmp.update(repeating: 0, count: RoomConv.size)
                let from: Int = k * p
                let m: Int = Swift.min(p, ir.frames - from)
                for i in 0..<m { tmp[i] = ir.h[path * ir.frames + from + i] * scale }
                let at: Int = (path * parts + k) * b
                fft.forward(tmp, hr + at, hi + at)
            }
        }
    }

    deinit {
        hr.deallocate(); hi.deallocate(); xr.deallocate(); xi.deallocate(); ar.deallocate(); ai.deallocate()
        inL.deallocate(); inR.deallocate(); tmp.deallocate(); out.deallocate()
    }

    /// Блок: новые 128 отсчётов — в inL[128…], inR[128…] (кладёт RoomStage); выход — out (4 × 128).
    @inline(__always)
    func step() {
        let b: Int = RoomConv.bins
        let p: Int = RoomConv.part
        let np: Int = parts
        let h: Int = head
        fft.forward(inL, xr + h * b, xi + h * b)
        fft.forward(inR, xr + (np + h) * b, xi + (np + h) * b)
        ar.update(repeating: 0, count: 4 * b)
        ai.update(repeating: 0, count: 4 * b)
        var k = 0
        while k < np {
            let slot: Int = (h - k + np) % np
            let acc: Int = k < directParts ? 0 : 2
            var path = 0
            while path < 4 {
                let ch: Int = path < 2 ? 0 : 1
                let ear: Int = path & 1
                let x: Int = (ch * np + slot) * b
                let f: Int = (path * np + k) * b
                let a: Int = (acc + ear) * b
                RoomConv.cmac(xr + x, xi + x, hr + f, hi + f, ar + a, ai + a, b)
                path += 1
            }
            k += 1
        }
        var j = 0
        while j < 4 {
            fft.inverse(ar + j * b, ai + j * b, tmp)
            (out + j * p).update(from: tmp + p, count: p)
            j += 1
        }
        inL.update(from: inL + p, count: p)
        inR.update(from: inR + p, count: p)
        head = (h + 1) % np
    }

    /// acc += x · h (комплексно, n бинов).
    @inline(__always)
    static func cmac(_ xr: UnsafeMutablePointer<Float>, _ xi: UnsafeMutablePointer<Float>,
                     _ hr: UnsafeMutablePointer<Float>, _ hi: UnsafeMutablePointer<Float>,
                     _ ar: UnsafeMutablePointer<Float>, _ ai: UnsafeMutablePointer<Float>, _ n: Int) {
        #if canImport(Accelerate)
        var x = DSPSplitComplex(realp: xr, imagp: xi)
        var f = DSPSplitComplex(realp: hr, imagp: hi)
        var a = DSPSplitComplex(realp: ar, imagp: ai)
        vDSP_zvma(&x, 1, &f, 1, &a, 1, &a, 1, vDSP_Length(n))
        #else
        var i = 0
        while i < n {
            let r: Float = xr[i], m: Float = xi[i], c: Float = hr[i], d: Float = hi[i]
            ar[i] += r * c - m * d
            ai[i] += r * d + m * c
            i += 1
        }
        #endif
    }
}

/// Room в колбэке: ФИФО на 128 отсчётов, текущая комната и переход к новой (40 мс), Ambience — плавно.
/// Off и нет перехода — блок не трогается (выход бит в бит равен входу).
public final class RoomStage: @unchecked Sendable {
    static let fadeFrames: Float = 1920
    /// Новые комнаты от интерфейса (nil — Off) и отработавшие — обратно (освобождает основной поток).
    let incoming = SPSCQueue<Unmanaged<RoomConv>?>(capacity: 16, filler: nil)
    public let retired = SPSCQueue<Unmanaged<RoomConv>?>(capacity: 64, filler: nil)
    /// Громкость хвоста (множитель; 0 — −∞).
    public let ambience = AtomicFloat(0.5)
    private var cur: Unmanaged<RoomConv>? = nil
    private var next: Unmanaged<RoomConv>? = nil
    private var pending: Unmanaged<RoomConv>? = nil
    private var hasPending = false
    private var fading = false
    private var fade: Float = 0
    private var amb: Float = 0.5
    private var fill = 0
    private let glide: Float

    public init(sampleRate: Double) {
        glide = Float(1 - exp(-1 / (0.02 * sampleRate)))
    }

    /// Основной поток: новая комната (nil — Off).
    public func set(_ conv: RoomConv?) {
        let u: Unmanaged<RoomConv>? = conv.map { Unmanaged.passRetained($0) }
        if !incoming.push(u) { u?.release() }
    }

    /// Основной поток: освободить отработавшие экземпляры.
    public func drain() {
        while let r = retired.pop() { r?.release() }
    }

    private func retire(_ u: Unmanaged<RoomConv>?) {
        guard let v = u else { return }
        _ = retired.push(v)
    }

    /// Колбэк: блок на месте (Double, как у MonitorChain).
    @inline(__always)
    func process(_ l: UnsafeMutablePointer<Double>, _ r: UnsafeMutablePointer<Double>, _ n: Int) {
        while let item = incoming.pop() {
            if hasPending { retire(pending) }
            pending = item
            hasPending = true
        }
        if !fading && hasPending {
            hasPending = false
            if pending == nil && cur == nil {
                pending = nil
            } else {
                // Из Off — Ambience сразу на месте (не плывёт вместе с переходом).
                if cur == nil { amb = ambience.load() }
                next = pending
                pending = nil
                fading = true
                fade = 0
            }
        }
        if cur == nil && !fading { return }
        let target: Float = ambience.load()
        let p: Int = RoomConv.part
        let step: Float = 1 / RoomStage.fadeFrames
        var i = 0
        while i < n {
            let m: Int = Swift.min(p - fill, n - i)
            let a: RoomConv? = cur?.takeUnretainedValue()
            let b: RoomConv? = fading ? next?.takeUnretainedValue() : nil
            var j = 0
            while j < m {
                let k: Int = fill + j
                let dl: Float = Float(l[i + j]), dr: Float = Float(r[i + j])
                amb += (target - amb) * glide
                var ol: Float = dl, or: Float = dr
                if let c = a {
                    c.inL[p + k] = dl
                    c.inR[p + k] = dr
                    ol = c.out[k] + amb * c.out[2 * p + k]
                    or = c.out[p + k] + amb * c.out[3 * p + k]
                }
                if fading {
                    var nl: Float = dl, nr: Float = dr
                    if let c = b {
                        c.inL[p + k] = dl
                        c.inR[p + k] = dr
                        nl = c.out[k] + amb * c.out[2 * p + k]
                        nr = c.out[p + k] + amb * c.out[3 * p + k]
                    }
                    fade = Swift.min(1, fade + step)
                    ol += (nl - ol) * fade
                    or += (nr - or) * fade
                }
                l[i + j] = Double(ol)
                r[i + j] = Double(or)
                j += 1
            }
            fill += m
            i += m
            if fill == p {
                fill = 0
                a?.step()
                b?.step()
            }
            if fading && fade >= 1 {
                fading = false
                retire(cur)
                cur = next
                next = nil
            }
        }
    }
}
