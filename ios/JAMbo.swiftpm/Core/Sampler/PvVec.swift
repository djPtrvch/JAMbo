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

/// o[i] = p[k[i]] (индексы — целые в Float, точные: k < 2^24).
func pvGather(_ p: UnsafePointer<Float>, _ kf: UnsafePointer<Float>, _ ki: UnsafePointer<Int32>,
              _ o: UnsafeMutablePointer<Float>, _ n: Int) {
    #if canImport(Accelerate)
    vDSP_vindex(p, kf, 1, o, 1, vDSP_Length(n))
    #else
    var i = 0
    while i < n { o[i] = p[Int(ki[i])]; i += 1 }
    #endif
}
