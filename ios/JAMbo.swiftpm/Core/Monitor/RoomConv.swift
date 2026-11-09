import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

// Room (Headphone Monitor, фаза 2): свёртка 2×2 — outL = L∗h_LL + R∗h_RL, outR = L∗h_LR + R∗h_RR. Равномерное
// разбиение на партиции по 128 отсчётов (БПФ 256, overlap-save, частотная линия задержки), добавленная задержка —
// 128 отсчётов (2,7 мс при 48 кГц). Прямая часть (первые direct отсчётов) и хвост — в разных сумматорах: выход
// = прямая + Ambience · хвост (громкость хвоста — плавно, без пересчёта импульсов). БПФ — PvFFT (vDSP на iPad).
// Экземпляр (RoomConv) готовится вне колбэка; смена комнаты — кроссфейд 40 мс между экземплярами (RoomStage).
// HEAD (8.11): спектры первой партиции (прямая часть) — из набора по углу поворота головы (линейно между соседними
// углами через 2°); смена спектров — переход внутри блока: прямая часть считается и с прошлыми спектрами, выход —
// линейно от прошлых к новым за 128 отсчётов. Остальные партиции (отражения, хвост) не меняются.
// Колонки (9.11): срез низа колонок комнаты — фильтр на входе свёртки (rooms.json speaker), направленность — в импульсах.

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
    /// HEAD: спектры прямой части по углам [набор][путь][бин]; headCount 0 — набора нет.
    let headCount: Int
    let headFrom: Float
    let headStep: Float
    let headR: UnsafeMutablePointer<Float>
    let headI: UnsafeMutablePointer<Float>
    /// Спектры прямой части: прошлого блока (hp) и нового (hn), [путь][бин]; сумматоры прямой части по прошлым.
    let hpR: UnsafeMutablePointer<Float>
    let hpI: UnsafeMutablePointer<Float>
    let hnR: UnsafeMutablePointer<Float>
    let hnI: UnsafeMutablePointer<Float>
    let aoR: UnsafeMutablePointer<Float>
    let aoI: UnsafeMutablePointer<Float>
    /// Прошлый блок шёл со спектрами HEAD (hp — их).
    var headActive = false
    /// Срез низа колонок (9.11): до двух звеньев Баттерворта на входе свёртки — коэффициенты [звено][b0 b1 b2 a1 a2],
    /// состояние [канал][звено][z1 z2]; hpN 0 — без среза.
    let hpc: UnsafeMutablePointer<Double>
    let hps: UnsafeMutablePointer<Double>
    var hpN = 0

    /// head — набор HEAD (4 пути, наборы по RoomConv.part кадров подряд), from и step — углы, градусы.
    public init(ir: RoomIR, head: RoomIR? = nil, from: Double = -50, step: Double = 2) {
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
        let hc: Int = head.map { $0.frames / p } ?? 0
        headCount = hc
        headFrom = Float(from)
        headStep = Float(step > 0 ? step : 2)
        let hs: Int = Swift.max(1, hc * 4 * b)
        headR = .allocate(capacity: hs)
        headI = .allocate(capacity: hs)
        headR.initialize(repeating: 0, count: hs)
        headI.initialize(repeating: 0, count: hs)
        hpR = .allocate(capacity: 4 * b)
        hpI = .allocate(capacity: 4 * b)
        hnR = .allocate(capacity: 4 * b)
        hnI = .allocate(capacity: 4 * b)
        aoR = .allocate(capacity: 2 * b)
        aoI = .allocate(capacity: 2 * b)
        hpR.initialize(repeating: 0, count: 4 * b)
        hpI.initialize(repeating: 0, count: 4 * b)
        hnR.initialize(repeating: 0, count: 4 * b)
        hnI.initialize(repeating: 0, count: 4 * b)
        aoR.initialize(repeating: 0, count: 2 * b)
        aoI.initialize(repeating: 0, count: 2 * b)
        hpc = .allocate(capacity: 10)
        hps = .allocate(capacity: 8)
        hpc.initialize(repeating: 0, count: 10)
        hps.initialize(repeating: 0, count: 8)
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
        if let hd = head {
            let hf: Int = hd.frames
            for set in 0..<hc {
                for path in 0..<4 {
                    tmp.update(repeating: 0, count: RoomConv.size)
                    for i in 0..<p { tmp[i] = hd.h[path * hf + set * p + i] * scale }
                    let at: Int = (set * 4 + path) * b
                    fft.forward(tmp, headR + at, headI + at)
                }
            }
        }
    }

    deinit {
        hr.deallocate(); hi.deallocate(); xr.deallocate(); xi.deallocate(); ar.deallocate(); ai.deallocate()
        inL.deallocate(); inR.deallocate(); tmp.deallocate(); out.deallocate()
        headR.deallocate(); headI.deallocate(); hpR.deallocate(); hpI.deallocate(); hnR.deallocate(); hnI.deallocate()
        aoR.deallocate(); aoI.deallocate(); hpc.deallocate(); hps.deallocate()
    }

    /// Основной поток, до передачи в колбэк: срез низа колонок — частота (Гц) и порядок Баттерворта (2 или 4; 0 — нет).
    public func setHighpass(hz: Double, order: Int, sampleRate: Double) {
        hpN = 0
        if hz <= 0 || order < 2 { return }
        let qs: [Double] = order >= 4 ? [0.5411961, 1.3065630] : [0.7071068]
        let w: Double = 2 * Double.pi * hz / sampleRate
        let cw: Double = cos(w)
        for (k, q) in qs.enumerated() {
            let al: Double = sin(w) / (2 * q)
            let a0: Double = 1 + al
            let c: UnsafeMutablePointer<Double> = hpc + 5 * k
            c[0] = (1 + cw) / 2 / a0
            c[1] = -(1 + cw) / a0
            c[2] = c[0]
            c[3] = -2 * cw / a0
            c[4] = (1 - al) / a0
        }
        hps.update(repeating: 0, count: 8)
        hpN = qs.count
    }

    /// Колбэк, при смене комнаты: история входа (спектры прошлых блоков, вход и выход текущего блока, HEAD, срез низа) —
    /// из прежнего экземпляра той же длины. История от комнаты не зависит, поэтому новая свёртка сразу звучит с полным
    /// хвостом (EAR TONE, 9.11: без неё каждый шаг ручки обрывал хвост — треск). Другая длина — false, с нуля.
    @discardableResult
    func takeState(from o: RoomConv) -> Bool {
        if o.parts != parts || o.headCount != headCount { return false }
        let n: Int = 2 * parts * RoomConv.bins
        xr.update(from: o.xr, count: n)
        xi.update(from: o.xi, count: n)
        head = o.head
        inL.update(from: o.inL, count: RoomConv.size)
        inR.update(from: o.inR, count: RoomConv.size)
        out.update(from: o.out, count: 4 * RoomConv.part)
        hpR.update(from: o.hpR, count: 4 * RoomConv.bins)
        hpI.update(from: o.hpI, count: 4 * RoomConv.bins)
        headActive = o.headActive
        if o.hpN == hpN { hps.update(from: o.hps, count: 8) }
        return true
    }

    /// Колбэк: отсчёт входа на место k (через срез низа колонок).
    @inline(__always)
    func feed(_ k: Int, _ l: Float, _ r: Float) {
        if hpN == 0 {
            inL[k] = l
            inR[k] = r
            return
        }
        var ch = 0
        while ch < 2 {
            var x: Double = Double(ch == 0 ? l : r)
            var s = 0
            while s < hpN {
                let c: UnsafeMutablePointer<Double> = hpc + 5 * s
                let z: UnsafeMutablePointer<Double> = hps + 4 * ch + 2 * s
                let y: Double = c[0] * x + z[0]
                var z1: Double = c[1] * x - c[3] * y + z[1]
                var z2: Double = c[2] * x - c[4] * y
                if abs(z1) < 1e-25 { z1 = 0 }
                if abs(z2) < 1e-25 { z2 = 0 }
                z[0] = z1
                z[1] = z2
                x = y
                s += 1
            }
            if ch == 0 { inL[k] = Float(x) } else { inR[k] = Float(x) }
            ch += 1
        }
    }

    /// Спектры прямой части без HEAD (партиция 0 импульса) → dst [путь][бин].
    @inline(__always)
    private func copyStatic(_ dr: UnsafeMutablePointer<Float>, _ di: UnsafeMutablePointer<Float>) {
        let b: Int = RoomConv.bins
        var path = 0
        while path < 4 {
            let f: Int = path * parts * b
            (dr + path * b).update(from: hr + f, count: b)
            (di + path * b).update(from: hi + f, count: b)
            path += 1
        }
    }

    /// Спектры прямой части для поворота yaw (градусы, вправо +) → hn: линейно между соседними наборами.
    @inline(__always)
    private func headSpectra(_ yaw: Float) {
        let n: Int = 4 * RoomConv.bins
        let last: Float = Float(headCount - 1)
        var x: Float = (yaw - headFrom) / headStep
        if x < 0 { x = 0 }
        if x > last { x = last }
        let i0: Int = Int(x)
        let i1: Int = Swift.min(i0 + 1, headCount - 1)
        let t: Float = x - Float(i0)
        let ar0 = headR + i0 * n, ai0 = headI + i0 * n
        let ar1 = headR + i1 * n, ai1 = headI + i1 * n
        var q = 0
        while q < n {
            hnR[q] = ar0[q] + (ar1[q] - ar0[q]) * t
            hnI[q] = ai0[q] + (ai1[q] - ai0[q]) * t
            q += 1
        }
    }

    /// Блок: новые 128 отсчётов — в inL[128…], inR[128…] (кладёт RoomStage); выход — out (4 × 128).
    /// yaw — поворот головы (градусы, вправо +), headOn — HEAD включён (без набора — как выключен).
    @inline(__always)
    func step(yaw: Float = 0, headOn: Bool = false) {
        let b: Int = RoomConv.bins
        let p: Int = RoomConv.part
        let np: Int = parts
        let h: Int = head
        let useHead: Bool = headOn && headCount > 0
        let mix: Bool = useHead || headActive
        if mix {
            if useHead { headSpectra(yaw) } else { copyStatic(hnR, hnI) }
            if !headActive { copyStatic(hpR, hpI) }
        }
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
                let a: Int = (acc + ear) * b
                if mix && k == 0 {
                    let f: Int = path * b
                    RoomConv.cmac(xr + x, xi + x, hnR + f, hnI + f, ar + a, ai + a, b)
                } else {
                    let f: Int = (path * np + k) * b
                    RoomConv.cmac(xr + x, xi + x, hr + f, hi + f, ar + a, ai + a, b)
                }
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
        if mix { blendDirect(h) }
        headActive = useHead
        inL.update(from: inL + p, count: p)
        inR.update(from: inR + p, count: p)
        head = (h + 1) % np
    }

    /// HEAD: прямая часть ещё и по прошлым спектрам (hp); выход прямой части — линейно от прошлых к новым за блок;
    /// новые спектры становятся прошлыми.
    @inline(__always)
    private func blendDirect(_ h: Int) {
        let b: Int = RoomConv.bins
        let p: Int = RoomConv.part
        let np: Int = parts
        aoR.update(repeating: 0, count: 2 * b)
        aoI.update(repeating: 0, count: 2 * b)
        var path = 0
        while path < 4 {
            let ch: Int = path < 2 ? 0 : 1
            let ear: Int = path & 1
            let x: Int = (ch * np + h) * b
            RoomConv.cmac(xr + x, xi + x, hpR + path * b, hpI + path * b, aoR + ear * b, aoI + ear * b, b)
            path += 1
        }
        let inv: Float = 1 / Float(p)
        var ear = 0
        while ear < 2 {
            fft.inverse(aoR + ear * b, aoI + ear * b, tmp)
            let o: UnsafeMutablePointer<Float> = out + ear * p
            var i = 0
            while i < p {
                let old: Float = tmp[p + i]
                let w: Float = Float(i + 1) * inv
                o[i] = old + (o[i] - old) * w
                i += 1
            }
            ear += 1
        }
        hpR.update(from: hnR, count: 4 * b)
        hpI.update(from: hnI, count: 4 * b)
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
    /// Сглаживание угла HEAD за блок 128 отсчётов: 1 − e^(−128 / (0,008 · 48000)).
    static let yawGlide: Float = 0.2835
    /// Новые комнаты от интерфейса (nil — Off) и отработавшие — обратно (освобождает основной поток).
    let incoming = SPSCQueue<Unmanaged<RoomConv>?>(capacity: 16, filler: nil)
    public let retired = SPSCQueue<Unmanaged<RoomConv>?>(capacity: 64, filler: nil)
    /// Громкость хвоста (множитель; 0 — −∞).
    public let ambience = AtomicFloat(0.5)
    /// HEAD (8.11): поворот головы (градусы, вправо +) и вкл. (1) — от трекера; в колбэке угол сглаживается по блокам
    /// (≈ 8 мс), выключение — сначала угол к нулю, потом спектры без HEAD.
    public let headYaw = AtomicFloat(0)
    public let headOn = AtomicFloat(0)
    private var yaw: Float = 0
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

    /// Колбэк: комната звучит или идёт переход (цепочка не нейтральна).
    var active: Bool { return cur != nil || fading || hasPending }

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
                if let a = cur?.takeUnretainedValue(), let b = next?.takeUnretainedValue() { b.takeState(from: a) }
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
                    c.feed(p + k, dl, dr)
                    ol = c.out[k] + amb * c.out[2 * p + k]
                    or = c.out[p + k] + amb * c.out[3 * p + k]
                }
                if fading {
                    var nl: Float = dl, nr: Float = dr
                    if let c = b {
                        c.feed(p + k, dl, dr)
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
                let on: Bool = headOn.load() > 0.5
                let target: Float = on ? headYaw.load() : 0
                yaw += (target - yaw) * RoomStage.yawGlide
                let use: Bool = on || yaw > 0.05 || yaw < -0.05
                a?.step(yaw: yaw, headOn: use)
                b?.step(yaw: yaw, headOn: use)
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
