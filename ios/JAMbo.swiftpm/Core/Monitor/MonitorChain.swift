import Foundation

/// Монитор-цепочка в колбэке (Headphone Monitor, фаза 1; параметры — MonitorDesign.make в основном потоке, через очередь
/// номеров заранее выделенных буферов). Без выделений и блокировок; биквады — Direct Form II Transposed в Double.
/// Плавно: коэффициенты — к новым за ~25 мс (выпуклая смесь устойчивых биквадов устойчива), g и задержка Crossfeed,
/// компенсация — линейно в блоке, Mono и вкл./выкл. (Bypass, референс мимо цепочки) — кроссфейд 25 мс.
/// Нейтральные ступени пропускаются: без коррекции, Crossfeed, Mono и компенсации выход равен входу бит в бит.
public final class MonitorChain: @unchecked Sendable {
    static let slots = 8
    static let delaySize = 256
    public let sampleRate: Double
    /// Экспорт песни идёт (1): цепочка не применяется (сразу, без перехода).
    public let paused = AtomicCounter()
    /// Наибольшее снижение лимитером в последнем блоке (1 — нет), для экрана.
    public let limitGain = AtomicFloat(1)

    private let ring: UnsafeMutablePointer<Double>
    private let queue = SPSCQueue<Int>(capacity: 16, filler: -1)
    private var nextSlot = 0
    /// Цель (последние параметры) и действующие коэффициенты.
    private let tgt: UnsafeMutablePointer<Double>
    private let cur: UnsafeMutablePointer<Double>
    /// Состояние биквадов: на биквад [s1 L, s2 L, s1 R, s2 R]; ФНЧ Crossfeed — последним.
    private let state: UnsafeMutablePointer<Double>
    private let delayL: UnsafeMutablePointer<Double>
    private let delayR: UnsafeMutablePointer<Double>
    private var write = 0
    private let wl: UnsafeMutablePointer<Double>
    private let wr: UnsafeMutablePointer<Double>
    private var g: Double = 0
    private var delay: Double = 0
    private var comp: Double = 1
    private var mono: Double = 0
    private var wet: Double = 0
    private var limit: Double = 1
    private let fadeStep: Double
    private let release: Double
    private let ceiling: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let size: Int = MonitorSpec.size
        ring = .allocate(capacity: MonitorChain.slots * size)
        ring.initialize(repeating: 0, count: MonitorChain.slots * size)
        tgt = .allocate(capacity: size)
        tgt.initialize(repeating: 0, count: size)
        cur = .allocate(capacity: size)
        cur.initialize(repeating: 0, count: size)
        let nst: Int = (MonitorSpec.sections + 1) * 4
        state = .allocate(capacity: nst)
        state.initialize(repeating: 0, count: nst)
        delayL = .allocate(capacity: MonitorChain.delaySize)
        delayL.initialize(repeating: 0, count: MonitorChain.delaySize)
        delayR = .allocate(capacity: MonitorChain.delaySize)
        delayR.initialize(repeating: 0, count: MonitorChain.delaySize)
        wl = .allocate(capacity: AudioCore.maxFrames)
        wl.initialize(repeating: 0, count: AudioCore.maxFrames)
        wr = .allocate(capacity: AudioCore.maxFrames)
        wr.initialize(repeating: 0, count: AudioCore.maxFrames)
        fadeStep = 1 / (MonitorSpec.fade * sampleRate)
        release = 1 - exp(-1 / (MonitorSpec.release * sampleRate))
        ceiling = pow(10, MonitorSpec.ceilingDb / 20)
        // До первых параметров — без обработки (компенсация 1, нейтральные биквады, цепочка выключена).
        var k = 0
        while k < MonitorSpec.sections {
            tgt[k * 5] = 1
            cur[k * 5] = 1
            k += 1
        }
        tgt[MonitorSpec.compAt] = 1
        cur[MonitorSpec.compAt] = 1
        tgt[MonitorSpec.crossLpAt] = 1
        cur[MonitorSpec.crossLpAt] = 1
    }

    deinit {
        ring.deallocate(); tgt.deallocate(); cur.deallocate(); state.deallocate()
        delayL.deallocate(); delayR.deallocate(); wl.deallocate(); wr.deallocate()
    }

    /// Новые параметры (основной поток; MonitorDesign.make, MonitorSpec.size значений).
    public func publish(_ p: [Double]) {
        guard p.count == MonitorSpec.size else { return }
        let dst: UnsafeMutablePointer<Double> = ring + nextSlot * MonitorSpec.size
        p.withUnsafeBufferPointer { b in
            if let s = b.baseAddress { dst.update(from: s, count: MonitorSpec.size) }
        }
        _ = queue.push(nextSlot)
        nextSlot = (nextSlot + 1) % MonitorChain.slots
    }

    /// Блок на месте (колбэк). raw — слышен референс, который идёт мимо цепочки: цепочка уходит (кроссфейд).
    @inline(__always)
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ frames: Int, raw: Bool) {
        var latest: Int = -1
        while let k = queue.pop() { latest = k }
        if latest >= 0 { tgt.update(from: ring + latest * MonitorSpec.size, count: MonitorSpec.size) }
        if paused.load() != 0 {
            wet = 0
            return
        }
        let n: Int = Swift.min(frames, AudioCore.maxFrames)
        let wetTarget: Double = tgt[MonitorSpec.onAt] > 0.5 && !raw ? 1 : 0
        glide(n)
        var i = 0
        while i < n {
            wl[i] = Double(left[i])
            wr[i] = Double(right[i])
            i += 1
        }
        processMono(n)
        processCross(n)
        var k = 0
        while k < MonitorSpec.sections {
            section(k, n)
            k += 1
        }
        processGain(n)
        output(left, right, n, wetTarget)
    }

    /// Коэффициенты (биквады и ФНЧ Crossfeed) — к цели за блок на долю 1 − e^(−n/τ); вплотную — ровно цель.
    @inline(__always)
    private func glide(_ n: Int) {
        let a: Double = 1 - exp(-Double(n) / (MonitorSpec.glide * sampleRate))
        let t = tgt, c = cur
        let last: Int = MonitorSpec.crossLpAt + 5
        var k = 0
        while k < last {
            if k == MonitorSpec.compAt { k = MonitorSpec.crossLpAt }
            let d: Double = t[k] - c[k]
            if d != 0 { c[k] = (d < 1e-12 && d > -1e-12) ? t[k] : c[k] + d * a }
            k += 1
        }
    }

    @inline(__always)
    private func processMono(_ n: Int) {
        let target: Double = tgt[MonitorSpec.monoAt]
        var m: Double = mono
        if m == 0 && target == 0 { return }
        let step: Double = fadeStep
        let l = wl, r = wr
        var i = 0
        while i < n {
            if m < target { m = Swift.min(target, m + step) } else if m > target { m = Swift.max(target, m - step) }
            let mid: Double = 0.5 * (l[i] + r[i])
            l[i] += (mid - l[i]) * m
            r[i] += (mid - r[i]) * m
            i += 1
        }
        mono = m
    }

    /// Crossfeed: каждому уху — противоположный канал через задержку (дробную, линейная интерполяция) и ФНЧ, · g;
    /// L = (L + g·LP(delay(R))) / (1 + g). Линия задержки и ФНЧ идут всегда (включение — без щелчка).
    @inline(__always)
    private func processCross(_ n: Int) {
        let l = wl, r = wr, dl = delayL, dr = delayR
        let c: UnsafeMutablePointer<Double> = cur + MonitorSpec.crossLpAt
        let b0: Double = c[0], b1: Double = c[1], b2: Double = c[2], a1: Double = c[3], a2: Double = c[4]
        let s: UnsafeMutablePointer<Double> = state + MonitorSpec.sections * 4
        var s1l: Double = s[0], s2l: Double = s[1], s1r: Double = s[2], s2r: Double = s[3]
        let g0: Double = g, g1: Double = tgt[MonitorSpec.crossGAt]
        let d0: Double = delay, d1: Double = tgt[MonitorSpec.crossDelayAt]
        let dg: Double = (g1 - g0) / Double(n), dd: Double = (d1 - d0) / Double(n)
        let mask: Int = MonitorChain.delaySize - 1
        let active: Bool = g0 > 0 || g1 > 0
        var w: Int = write
        var i = 0
        while i < n {
            let xl: Double = l[i], xr: Double = r[i]
            dl[w] = xl
            dr[w] = xr
            let gi: Double = g0 + dg * Double(i + 1)
            let di: Double = d0 + dd * Double(i + 1)
            let whole: Int = Int(di)
            let frac: Double = di - Double(whole)
            let p0: Int = (w - whole) & mask
            let p1: Int = (w - whole - 1) & mask
            let ql: Double = dl[p0] + (dl[p1] - dl[p0]) * frac
            let qr: Double = dr[p0] + (dr[p1] - dr[p0]) * frac
            // ФНЧ задержанных каналов (DF2T).
            let yl: Double = b0 * ql + s1l
            s1l = b1 * ql - a1 * yl + s2l
            s2l = b2 * ql - a2 * yl
            let yr: Double = b0 * qr + s1r
            s1r = b1 * qr - a1 * yr + s2r
            s2r = b2 * qr - a2 * yr
            if active {
                let k: Double = 1 / (1 + gi)
                l[i] = (xl + gi * yr) * k
                r[i] = (xr + gi * yl) * k
            }
            w = (w + 1) & mask
            i += 1
        }
        write = w
        g = g1
        delay = d1
        if abs(s1l) < 1e-30 { s1l = 0; s2l = 0 }
        if abs(s1r) < 1e-30 { s1r = 0; s2r = 0 }
        s[0] = s1l; s[1] = s2l; s[2] = s1r; s[3] = s2r
    }

    /// Биквад k на оба канала (DF2T); нейтральный (и цель нейтральная) — пропуск, состояние — с нуля.
    @inline(__always)
    private func section(_ k: Int, _ n: Int) {
        let c: UnsafeMutablePointer<Double> = cur + k * 5
        let s: UnsafeMutablePointer<Double> = state + k * 4
        let b0: Double = c[0], b1: Double = c[1], b2: Double = c[2], a1: Double = c[3], a2: Double = c[4]
        if b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0 {
            s[0] = 0; s[1] = 0; s[2] = 0; s[3] = 0
            return
        }
        let l = wl, r = wr
        var s1l: Double = s[0], s2l: Double = s[1], s1r: Double = s[2], s2r: Double = s[3]
        var i = 0
        while i < n {
            let xl: Double = l[i]
            let yl: Double = b0 * xl + s1l
            s1l = b1 * xl - a1 * yl + s2l
            s2l = b2 * xl - a2 * yl
            l[i] = yl
            let xr: Double = r[i]
            let yr: Double = b0 * xr + s1r
            s1r = b1 * xr - a1 * yr + s2r
            s2r = b2 * xr - a2 * yr
            r[i] = yr
            i += 1
        }
        if abs(s1l) < 1e-30 && abs(s2l) < 1e-30 { s1l = 0; s2l = 0 }
        if abs(s1r) < 1e-30 && abs(s2r) < 1e-30 { s1r = 0; s2r = 0 }
        s[0] = s1l; s[1] = s2l; s[2] = s1r; s[3] = s2r
    }

    /// Level compensation (линейно в блоке) и Safety limiter: потолок без задержки — снижение сразу, отпускание 50 мс;
    /// ниже потолка усиление ровно 1.
    @inline(__always)
    private func processGain(_ n: Int) {
        let l = wl, r = wr
        let c0: Double = comp, c1: Double = tgt[MonitorSpec.compAt]
        if c0 != 1 || c1 != 1 {
            let dc: Double = (c1 - c0) / Double(n)
            var i = 0
            while i < n {
                let gi: Double = c0 + dc * Double(i + 1)
                l[i] *= gi
                r[i] *= gi
                i += 1
            }
        }
        comp = c1
        let ceil: Double = ceiling, rel: Double = release
        var lg: Double = limit
        var least: Double = 1
        var i = 0
        while i < n {
            let al: Double = l[i] < 0 ? -l[i] : l[i]
            let ar: Double = r[i] < 0 ? -r[i] : r[i]
            let peak: Double = al > ar ? al : ar
            let need: Double = peak > ceil ? ceil / peak : 1
            if lg < 1 {
                lg += (1 - lg) * rel
                if lg > 0.999999 { lg = 1 }
            }
            if need < lg { lg = need }
            if lg < 1 {
                l[i] *= lg
                r[i] *= lg
                if lg < least { least = lg }
            }
            i += 1
        }
        limit = lg
        limitGain.store(Float(least))
    }

    /// Выход: цепочка (wet 1), вход (wet 0) или кроссфейд между ними.
    @inline(__always)
    private func output(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ n: Int,
                        _ target: Double) {
        let l = wl, r = wr
        var w: Double = wet
        if w == target && w == 0 { return }
        let step: Double = fadeStep
        var i = 0
        if w == target {
            while i < n {
                left[i] = Float(l[i])
                right[i] = Float(r[i])
                i += 1
            }
            return
        }
        while i < n {
            if w < target { w = Swift.min(target, w + step) } else if w > target { w = Swift.max(target, w - step) }
            let dl: Double = Double(left[i]), dr: Double = Double(right[i])
            left[i] = Float(dl + (l[i] - dl) * w)
            right[i] = Float(dr + (r[i] - dr) * w)
            i += 1
        }
        wet = w
    }
}
