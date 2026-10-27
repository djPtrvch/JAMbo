import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

// Векторные операции фазового вокодера (StretchPV.swift): на iPad — vDSP, иначе — обычные циклы (по ним идут тесты
// на Linux, так что логика вокодера проверяется и там). Без выделений памяти; n > 0.

/// o = a · b.
func pvMul(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    vDSP_vmul(a, 1, b, 1, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] * b[i]; i += 1 }
    #endif
}

/// o = a · b + c.
func pvMa(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, _ c: UnsafePointer<Float>,
          _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    vDSP_vma(a, 1, b, 1, c, 1, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] * b[i] + c[i]; i += 1 }
    #endif
}

/// o = a · s + c.
func pvSma(_ a: UnsafePointer<Float>, _ s: Float, _ c: UnsafePointer<Float>, _ o: UnsafeMutablePointer<Float>,
           _ n: Int) {
    #if canImport(Accelerate)
    var sv = s
    vDSP_vsma(a, 1, &sv, c, 1, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] * s + c[i]; i += 1 }
    #endif
}

/// o = a · s + b · t.
func pvSmsma(_ a: UnsafePointer<Float>, _ s: Float, _ b: UnsafePointer<Float>, _ t: Float,
             _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    var sv = s
    var tv = t
    vDSP_vsmsma(a, 1, &sv, b, 1, &tv, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] * s + b[i] * t; i += 1 }
    #endif
}

/// o = a + b.
func pvAdd(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    vDSP_vadd(a, 1, b, 1, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] + b[i]; i += 1 }
    #endif
}

/// o = a − b.
func pvSub(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    vDSP_vsub(b, 1, a, 1, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] - b[i]; i += 1 }
    #endif
}

/// o = a + s.
func pvSAdd(_ a: UnsafePointer<Float>, _ s: Float, _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    var sv = s
    vDSP_vsadd(a, 1, &sv, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] + s; i += 1 }
    #endif
}

/// o = a · s.
func pvScale(_ a: UnsafePointer<Float>, _ s: Float, _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    var sv = s
    vDSP_vsmul(a, 1, &sv, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = a[i] * s; i += 1 }
    #endif
}

/// Наибольшее значение.
func pvMax(_ a: UnsafePointer<Float>, _ n: Int) -> Float {
    #if canImport(Accelerate)
    var m: Float = 0
    vDSP_maxv(a, 1, &m, vDSP_Length(n))
    return m
    #else
    var m: Float = a[0]
    var i = 1
    while i < n { if a[i] > m { m = a[i] }; i += 1 }
    return m
    #endif
}

/// Углы x — к −π…π (вычесть ближайшее кратное 2π); qi, qf — рабочие буферы n.
func pvWrap(_ x: UnsafeMutablePointer<Float>, _ qi: UnsafeMutablePointer<Int32>, _ qf: UnsafeMutablePointer<Float>,
            _ n: Int) {
    let twoPi: Float = 6.2831855
    let inv2Pi: Float = 0.15915494
    #if canImport(Accelerate)
    pvScale(x, inv2Pi, qf, n)
    vDSP_vfixr32(qf, 1, qi, 1, vDSP_Length(n))
    vDSP_vflt32(qi, 1, qf, 1, vDSP_Length(n))
    pvSma(qf, -twoPi, x, x, n)
    #else
    var i = 0
    while i < n {
        let q: Float = x[i] * inv2Pi
        x[i] -= twoPi * Float(Int(q >= 0 ? q + 0.5 : q - 0.5))
        i += 1
    }
    #endif
}

/// Поворот спектра на месте: (re + i·im) · (c + i·s).
func pvRotate(_ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>, _ c: UnsafeMutablePointer<Float>,
              _ s: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    var a = DSPSplitComplex(realp: re, imagp: im)
    var b = DSPSplitComplex(realp: c, imagp: s)
    var o = DSPSplitComplex(realp: re, imagp: im)
    vDSP_zvmul(&a, 1, &b, 1, &o, 1, vDSP_Length(n), 1)
    #else
    var i = 0
    while i < n {
        let x = re[i], y = im[i], cs = c[i], sn = s[i]
        re[i] = x * cs - y * sn
        im[i] = x * sn + y * cs
        i += 1
    }
    #endif
}

/// Кольцо (размер size, степень двойки) с позиции at: ring += x · w (n ≤ size).
func pvRingMa(_ ring: UnsafeMutablePointer<Float>, _ size: Int, _ at: Int, _ x: UnsafePointer<Float>,
              _ w: UnsafePointer<Float>, _ n: Int) {
    let a = at & (size - 1)
    let first = Swift.min(n, size - a)
    pvMa(x, w, ring + a, ring + a, first)
    if n > first { pvMa(x + first, w + first, ring, ring, n - first) }
}

/// Позиции start + i·step (Double): целая часть (k ≥ 0, Int32 и Float) и дробная (Float).
func pvSplitRamp(_ start: Double, _ step: Double, _ xd: UnsafeMutablePointer<Double>,
                 _ ki: UnsafeMutablePointer<Int32>, _ kf: UnsafeMutablePointer<Float>,
                 _ fr: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    var s0 = start
    var st = step
    let len = vDSP_Length(n)
    vDSP_vrampD(&s0, &st, xd, 1, len)
    vDSP_vfix32D(xd, 1, ki, 1, len)
    vDSP_vflt32(ki, 1, kf, 1, len)
    // Дробная часть — в Double (позиции в сэмпле велики для Float), затем в Float.
    vDSP_vfracD(xd, 1, xd, 1, len)
    vDSP_vdpsp(xd, 1, fr, 1, len)
    #else
    var i = 0
    while i < n {
        let x: Double = start + Double(i) * step
        let k = Int32(x)
        ki[i] = k
        kf[i] = Float(k)
        fr[i] = Float(x - Double(k))
        i += 1
    }
    #endif
}

/// o[i] = p[k[i]] (индексы — целые ≥ 0 в Float, точные: k < 2^24).
func pvGather(_ p: UnsafePointer<Float>, _ kf: UnsafePointer<Float>, _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    vDSP_vindex(p, kf, 1, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = p[Int(kf[i])]; i += 1 }
    #endif
}

/// Σ a · b.
func pvDot(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, _ n: Int) -> Float {
    #if canImport(Accelerate)
    var r: Float = 0
    vDSP_dotpr(a, 1, b, 1, &r, vDSP_Length(n))
    return r
    #else
    var r: Float = 0
    var i = 0
    while i < n { r += a[i] * b[i]; i += 1 }
    return r
    #endif
}

/// Σ a².
func pvSumSq(_ a: UnsafePointer<Float>, _ n: Int) -> Float {
    #if canImport(Accelerate)
    var r: Float = 0
    vDSP_svesq(a, 1, &r, vDSP_Length(n))
    return r
    #else
    var r: Float = 0
    var i = 0
    while i < n { r += a[i] * a[i]; i += 1 }
    return r
    #endif
}

/// Кубическое чтение сэмпла (Catmull-Rom, как Sampler.cubic) векторно: n отсчётов в позициях x0 + i·step. Буферы —
/// на cap отсчётов, создаются вне колбэка; ki и kf свободны между чтениями (рабочие буферы для вызывающего).
final class PvCubic {
    let cap: Int
    let xd: UnsafeMutablePointer<Double>
    let ki: UnsafeMutablePointer<Int32>
    let kf: UnsafeMutablePointer<Float>
    let fr: UnsafeMutablePointer<Float>
    let g0: UnsafeMutablePointer<Float>
    let g1: UnsafeMutablePointer<Float>
    let g2: UnsafeMutablePointer<Float>
    let g3: UnsafeMutablePointer<Float>
    let t1: UnsafeMutablePointer<Float>

    init(cap n: Int) {
        cap = n
        xd = .allocate(capacity: n)
        xd.initialize(repeating: 0, count: n)
        ki = .allocate(capacity: n)
        ki.initialize(repeating: 0, count: n)
        func buf() -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        kf = buf()
        fr = buf()
        g0 = buf()
        g1 = buf()
        g2 = buf()
        g3 = buf()
        t1 = buf()
    }

    deinit {
        for p in [kf, fr, g0, g1, g2, g3, t1] { p.deallocate() }
        xd.deallocate()
        ki.deallocate()
    }

    /// Все позиции в lo…hi и внутри сэмпла (1 ≤ x < frames − 3) — out и true; иначе false (читать по отсчётам).
    func read(_ p: UnsafePointer<Float>, _ frames: Int, _ x0: Double, _ step: Double, _ n: Int, _ lo: Double,
              _ hi: Double, _ out: UnsafeMutablePointer<Float>) -> Bool {
        let x1: Double = x0 + Double(n - 1) * step
        let xmin: Double = Swift.min(x0, x1)
        if n > cap || xmin < Swift.max(lo, 1) || Swift.max(x0, x1) >= Swift.min(hi, Double(frames - 3)) { return false }
        // Позиции — от base (индексы малы — точны и в Float); g0…g3 — ym1, y0, y1, y2.
        let base = Int(xmin)
        pvSplitRamp(x0 - Double(base), step, xd, ki, kf, fr, n)
        let q = p + (base - 1)
        pvGather(q, kf, g0, n)
        pvGather(q + 1, kf, g1, n)
        pvGather(q + 2, kf, g2, n)
        pvGather(q + 3, kf, g3, n)
        // c3 = 0.5·(y2 − ym1) + 1.5·(y0 − y1) → t1; c2 = (ym1 − 0.5·y2) + (2·y1 − 2.5·y0) → kf;
        // c1 = 0.5·(y1 − ym1) → out; y = ((c3·f + c2)·f + c1)·f + y0.
        pvSub(g3, g0, t1, n)
        pvSub(g1, g2, kf, n)
        pvSmsma(t1, 0.5, kf, 1.5, t1, n)
        pvSmsma(g0, 1, g3, -0.5, kf, n)
        pvSmsma(g2, 2, g1, -2.5, g3, n)
        pvAdd(kf, g3, kf, n)
        pvSmsma(g2, 0.5, g0, -0.5, out, n)
        pvMa(t1, fr, kf, t1, n)
        pvMa(t1, fr, out, t1, n)
        pvMa(t1, fr, g1, out, n)
        return true
    }
}
