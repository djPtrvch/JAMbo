import Foundation

/// Монитор-цепочка в колбэке (Headphone Monitor, фаза 1; параметры — MonitorDesign.make в основном потоке, через очередь
/// номеров заранее выделенных буферов). Без выделений и блокировок; биквады — Direct Form II Transposed в Double.
/// Плавно: коэффициенты — к новым за ~25 мс (выпуклая смесь устойчивых биквадов устойчива), компенсация — линейно в
/// блоке, Mono и вкл./выкл. (Bypass, референс мимо цепочки) — кроссфейд 25 мс. Связь каналов (колонки) — только в
/// комнате (Room; Crossfeed убран 8.11, решение пользователя). Нейтральные ступени пропускаются: без коррекции,
/// комнаты, Mono и компенсации выход равен входу бит в бит.
public final class MonitorChain: @unchecked Sendable {
    static let slots = 8
    public let sampleRate: Double
    /// Экспорт песни идёт (1): цепочка не применяется (сразу, без перехода).
    public let paused = AtomicCounter()
    /// Room (фаза 2): свёртка с импульсами комнаты — после Mono, перед биквадами.
    public let room: RoomStage
    /// Наибольшее снижение лимитером в последнем блоке (1 — нет), для экрана.
    public let limitGain = AtomicFloat(1)

    private let ring: UnsafeMutablePointer<Double>
    private let queue = SPSCQueue<Int>(capacity: 16, filler: -1)
    private var nextSlot = 0
    /// Цель (последние параметры) и действующие коэффициенты.
    private let tgt: UnsafeMutablePointer<Double>
    private let cur: UnsafeMutablePointer<Double>
    /// Состояние биквадов: на биквад [s1 L, s2 L, s1 R, s2 R].
    private let state: UnsafeMutablePointer<Double>
    private let wl: UnsafeMutablePointer<Double>
    private let wr: UnsafeMutablePointer<Double>
    private var comp: Double = 1
    private var mono: Double = 0
    private var wet: Double = 0
    /// Лимитер с упреждением: задержка входа (L, R), требуемое усиление (look + 1), сглаженное (look) и их сумма,
    /// место в кольцах, огибающая и удержание.
    private let ldl: UnsafeMutablePointer<Double>
    private let ldr: UnsafeMutablePointer<Double>
    private let lneed: UnsafeMutablePointer<Double>
    private let lbox: UnsafeMutablePointer<Double>
    private var lpos = 0
    private var limit: Double = 1
    private var holdLeft = 0
    private let holdN: Int
    private let fadeStep: Double
    private let release: Double
    private let ceiling: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        room = RoomStage(sampleRate: sampleRate)
        let size: Int = MonitorSpec.size
        ring = .allocate(capacity: MonitorChain.slots * size)
        ring.initialize(repeating: 0, count: MonitorChain.slots * size)
        tgt = .allocate(capacity: size)
        tgt.initialize(repeating: 0, count: size)
        cur = .allocate(capacity: size)
        cur.initialize(repeating: 0, count: size)
        let nst: Int = MonitorSpec.sections * 4
        state = .allocate(capacity: nst)
        state.initialize(repeating: 0, count: nst)
        wl = .allocate(capacity: AudioCore.maxFrames)
        wl.initialize(repeating: 0, count: AudioCore.maxFrames)
        wr = .allocate(capacity: AudioCore.maxFrames)
        wr.initialize(repeating: 0, count: AudioCore.maxFrames)
        let la: Int = MonitorSpec.look
        ldl = .allocate(capacity: la)
        ldr = .allocate(capacity: la)
        lneed = .allocate(capacity: la + 1)
        lbox = .allocate(capacity: la)
        ldl.initialize(repeating: 0, count: la)
        ldr.initialize(repeating: 0, count: la)
        lneed.initialize(repeating: 1, count: la + 1)
        lbox.initialize(repeating: 1, count: la)
        holdN = Int(MonitorSpec.hold * sampleRate)
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
    }

    deinit {
        ring.deallocate(); tgt.deallocate(); cur.deallocate(); state.deallocate()
        wl.deallocate(); wr.deallocate()
        ldl.deallocate(); ldr.deallocate(); lneed.deallocate(); lbox.deallocate()
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
        let wetTarget: Double = tgt[MonitorSpec.onAt] > 0.5 && !raw && !neutral() ? 1 : 0
        glide(n)
        var i = 0
        while i < n {
            wl[i] = Double(left[i])
            wr[i] = Double(right[i])
            i += 1
        }
        processMono(n)
        room.process(wl, wr, n)
        var k = 0
        while k < MonitorSpec.sections {
            section(k, n)
            k += 1
        }
        processGain(n)
        output(left, right, n, wetTarget)
    }

    /// Цепочка ничего не меняет (без коррекции, комнаты, Mono и компенсации): уходит кроссфейдом — выход бит в бит
    /// равен входу, без задержки лимитера (9.11).
    @inline(__always)
    private func neutral() -> Bool {
        if tgt[MonitorSpec.compAt] != 1 || tgt[MonitorSpec.monoAt] != 0 || mono != 0 || room.active { return false }
        var k = 0
        while k < MonitorSpec.sections {
            let c: UnsafeMutablePointer<Double> = tgt + k * 5
            if c[0] != 1 || c[1] != 0 || c[2] != 0 || c[3] != 0 || c[4] != 0 { return false }
            k += 1
        }
        return true
    }

    /// Коэффициенты биквадов — к цели за блок на долю 1 − e^(−n/τ); вплотную — ровно цель.
    @inline(__always)
    private func glide(_ n: Int) {
        let a: Double = 1 - exp(-Double(n) / (MonitorSpec.glide * sampleRate))
        let t = tgt, c = cur
        let last: Int = MonitorSpec.compAt
        var k = 0
        while k < last {
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

    /// Level compensation (линейно в блоке) и Safety limiter с упреждением look отсчётов (9.11): требуемое усиление —
    /// минимум за look + 1 отсчётов, удержание 30 мс, отпускание 150 мс, затем среднее за look отсчётов — усиление
    /// плавно доходит до нужного к приходу пика и не выше его (потолок не превышается). Выход цепочки задержан на look.
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
        let la: Int = MonitorSpec.look
        let inv: Double = 1 / Double(la)
        let dl = ldl, dr = ldr, nd = lneed, bx = lbox
        var lg: Double = limit
        var hold: Int = holdLeft
        var pos: Int = lpos
        var sum: Double = 0
        var q = 0
        while q < la { sum += bx[q]; q += 1 }
        var least: Double = 1
        var i = 0
        while i < n {
            let xl: Double = l[i], xr: Double = r[i]
            let al: Double = xl < 0 ? -xl : xl
            let ar: Double = xr < 0 ? -xr : xr
            let peak: Double = al > ar ? al : ar
            nd[pos % (la + 1)] = peak > ceil ? ceil / peak : 1
            var held: Double = 1
            q = 0
            while q <= la {
                if nd[q] < held { held = nd[q] }
                q += 1
            }
            if held < lg {
                lg = held
                hold = holdN
            } else if hold > 0 {
                hold -= 1
            } else if lg < held {
                lg += (held - lg) * rel
                if lg > held - 1e-9 { lg = held }
            }
            let k: Int = pos % la
            sum += lg - bx[k]
            bx[k] = lg
            let g: Double = sum * inv
            l[i] = dl[k] * g
            r[i] = dr[k] * g
            dl[k] = xl
            dr[k] = xr
            if g < least { least = g }
            pos = (pos + 1) % (la * (la + 1))
            i += 1
        }
        lpos = pos
        limit = lg
        holdLeft = hold
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
