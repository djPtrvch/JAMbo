import Foundation

// Таймстретч голоса сэмплера (RATE в режиме TSTR): WSOLA — зёрна по 2048 отсчётов (≈43 мс) через 1024, окно Ханна
// (два зерна в сумме дают 1). Указатель времени (pos голоса) идёт со скоростью темпа и RATE, внутри зерна сэмпл читается
// со скоростью высоты (нота и Pitch) — высота не зависит от скорости. Новое зерно ищется возле указателя времени
// (±288 отсчётов) там, где сэмпл лучше всего продолжает прежнее зерно (нормированная корреляция по 96 точкам через 4) —
// без биений и провалов на тональном звуке. Первое зерно ноты — без нарастания (атака удара не смазывается).
// Всё — в колбэке, без выделений памяти: состояние голосов — массивы указателей.

final class Stretcher {
    static let grain = 2048
    static let hop = 1024
    static let search = 288
    static let searchStep = 4
    static let corrPoints = 96
    static let corrStep = 4
    /// Кусок голоса за один вызов fill (кусочек сглаживания renderVoice).
    static let maxChunk = 32

    let slots: Int
    /// Окно Ханна на grain отсчётов.
    let window: UnsafeMutablePointer<Float>
    /// Зёрна голоса (голос·2 + k): позиция чтения, возраст (≥ grain — зерно не звучит), первое зерно ноты.
    let gPos: UnsafeMutablePointer<Double>
    let gAge: UnsafeMutablePointer<Int>
    let gFirst: UnsafeMutablePointer<UInt8>
    /// Направление чтения зерна (+1 / −1).
    let gDir: UnsafeMutablePointer<Double>
    /// Отсчётов до следующего зерна; направление последнего зерна (при скорости 0 — прежнее).
    let phase: UnsafeMutablePointer<Int>
    let lastDir: UnsafeMutablePointer<Double>
    /// Выход куска (отсчёты до умножения на огибающую).
    let outL: UnsafeMutablePointer<Float>
    let outR: UnsafeMutablePointer<Float>
    /// Поиск зерна: продолжение звучащего зерна и смещения точек.
    let target: UnsafeMutablePointer<Float>
    let offsets: UnsafeMutablePointer<Double>

    init(slots n: Int) {
        slots = n
        let g = Stretcher.grain
        window = .allocate(capacity: g)
        var i = 0
        while i < g {
            window[i] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(g)))
            i += 1
        }
        gPos = .allocate(capacity: n * 2)
        gPos.initialize(repeating: 0, count: n * 2)
        gAge = .allocate(capacity: n * 2)
        gAge.initialize(repeating: g, count: n * 2)
        gFirst = .allocate(capacity: n * 2)
        gFirst.initialize(repeating: 0, count: n * 2)
        gDir = .allocate(capacity: n * 2)
        gDir.initialize(repeating: 1, count: n * 2)
        phase = .allocate(capacity: n)
        phase.initialize(repeating: 0, count: n)
        lastDir = .allocate(capacity: n)
        lastDir.initialize(repeating: 1, count: n)
        outL = .allocate(capacity: Stretcher.maxChunk)
        outL.initialize(repeating: 0, count: Stretcher.maxChunk)
        outR = .allocate(capacity: Stretcher.maxChunk)
        outR.initialize(repeating: 0, count: Stretcher.maxChunk)
        target = .allocate(capacity: Stretcher.corrPoints)
        target.initialize(repeating: 0, count: Stretcher.corrPoints)
        offsets = .allocate(capacity: Stretcher.corrPoints)
        offsets.initialize(repeating: 0, count: Stretcher.corrPoints)
    }

    deinit {
        window.deallocate()
        gPos.deallocate()
        gAge.deallocate()
        gFirst.deallocate()
        gDir.deallocate()
        phase.deallocate()
        lastDir.deallocate()
        outL.deallocate()
        outR.deallocate()
        target.deallocate()
        offsets.deallocate()
    }

    /// Новая нота голоса v: зёрен нет, первое начнётся на первом отсчёте.
    func start(_ v: Int, dir: Double) {
        let g = Stretcher.grain
        gAge[v * 2] = g
        gAge[v * 2 + 1] = g
        phase[v] = 0
        lastDir[v] = dir < 0 ? -1 : 1
    }

    @inline(__always)
    static func cubic(_ p: UnsafeMutablePointer<Float>, _ n: Int, _ x: Double) -> Float {
        if x < 0 { return 0 }
        let i = Int(x)
        let f = Float(x - Double(i))
        let ym1: Float = i >= 1 && i - 1 < n ? p[i - 1] : 0
        let y0: Float = i < n ? p[i] : 0
        let y1: Float = i + 1 < n ? p[i + 1] : 0
        let y2: Float = i + 2 < n ? p[i + 2] : 0
        let c1: Float = 0.5 * (y1 - ym1)
        let c2: Float = ym1 - 2.5 * y0 + 2 * y1 - 0.5 * y2
        let c3: Float = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1)
        return ((c3 * f + c2) * f + c1) * f + y0
    }

    /// Начало нового зерна возле base (лучшее продолжение звучащего зерна prev; −1 — его нет), в пределах lo…hi.
    func place(_ l: UnsafeMutablePointer<Float>, _ frames: Int, _ base: Double, _ step: Double, _ prev: Int,
               _ lo: Double, _ hi: Double) -> Double {
        let b0: Double = Swift.min(hi, Swift.max(lo, base))
        if prev < 0 { return b0 }
        let pp: Double = gPos[prev]
        let ps: Double = gDir[prev] * Swift.abs(step)
        let pts: Int = Stretcher.corrPoints
        let cs: Double = Double(Stretcher.corrStep)
        // Продолжение звучащего зерна и смещения точек кандидата — один раз на зерно (без вызовов в циклах поиска).
        let tgt = target
        let off = offsets
        var k = 0
        while k < pts {
            let x: Double = pp + Double(k) * cs * ps
            let i: Int = x < 0 ? frames : Int(x)
            tgt[k] = i < frames ? l[i] : 0
            off[k] = Double(k) * cs * step
            k += 1
        }
        let n: Double = Double(frames)
        var best: Double = b0
        var bestScore: Float = -Float.greatestFiniteMagnitude
        var d: Int = -Stretcher.search
        while d <= Stretcher.search {
            let c: Double = b0 + Double(d)
            if c >= lo && c <= hi {
                var xy: Float = 0
                var yy: Float = 1e-9
                k = 0
                while k < pts {
                    let x: Double = c + off[k]
                    if x >= 0 && x < n {
                        let y: Float = l[Int(x)]
                        xy += tgt[k] * y
                        yy += y * y
                    }
                    k += 1
                }
                let sc: Float = xy / yy.squareRoot()
                if sc > bestScore {
                    bestScore = sc
                    best = c
                }
            }
            d += Stretcher.searchStep
        }
        return best
    }

    /// m отсчётов голоса v в outL/outR: первые skip — тишина (голос ещё не начался); указатель времени от pos0 со
    /// скоростью speed (со знаком), чтение внутри зерна — со скоростью ratio (> 0) по направлению скорости; зёрна
    /// начинаются в пределах lo…hi (Start…End или маркер).
    func fill(_ v: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ frames: Int, _ stereo: Bool,
              _ pos0: Double, _ speed: Double, _ ratio: Double, _ m: Int, _ skip: Int, _ lo: Double, _ hi: Double) {
        let g = Stretcher.grain
        let h = Stretcher.hop
        let w = window
        let a0 = v * 2
        if speed > 1e-9 { lastDir[v] = 1 } else if speed < -1e-9 { lastDir[v] = -1 }
        let dir: Double = lastDir[v]
        var j = 0
        while j < skip && j < m {
            outL[j] = 0
            outR[j] = 0
            j += 1
        }
        var t: Double = pos0
        while j < m {
            if phase[v] <= 0 {
                // Новое зерно — в ячейку отзвучавшего (старшего) зерна.
                let k0: Bool = gAge[a0] >= gAge[a0 + 1]
                let k: Int = k0 ? a0 : a0 + 1
                let other: Int = k0 ? a0 + 1 : a0
                let prev: Int = gAge[other] < g ? other : -1
                gPos[k] = place(l, frames, t, dir * ratio, prev, lo, hi)
                gDir[k] = dir
                gAge[k] = 0
                gFirst[k] = prev < 0 ? 1 : 0
                phase[v] = h
            }
            var sl: Float = 0
            var sr: Float = 0
            var k = a0
            while k < a0 + 2 {
                let age = gAge[k]
                if age < g {
                    let wk: Float = gFirst[k] != 0 && age < h ? 1 : w[age]
                    let x: Double = gPos[k]
                    let yl: Float = Stretcher.cubic(l, frames, x)
                    sl += yl * wk
                    sr += (stereo ? Stretcher.cubic(r, frames, x) : yl) * wk
                    gPos[k] = x + gDir[k] * ratio
                    gAge[k] = age + 1
                }
                k += 1
            }
            outL[j] = sl
            outR[j] = sr
            phase[v] -= 1
            t += speed
            j += 1
        }
    }
}
