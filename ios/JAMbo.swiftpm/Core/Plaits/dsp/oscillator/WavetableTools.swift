// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/wavetable_oscillator.h: Differentiator, InterpolateWave, InterpolateWaveHermite.

/// Дифференциатор с ФНЧ (интегрированные таблицы волн → волна).
struct Differentiator {
    private var lp: Float = 0
    private var previous: Float = 0

    @inline(__always) mutating func process(_ coefficient: Float, _ s: Float) -> Float {
        onePole(&lp, s - previous, coefficient)
        previous = s
        return lp
    }
}

@inline(__always) func interpolateWave(_ table: UnsafePointer<Int16>, _ indexIntegral: Int,
                                       _ indexFractional: Float) -> Float {
    let a = Float(table[indexIntegral])
    let b = Float(table[indexIntegral + 1])
    return a + (b - a) * indexFractional
}

/// Эрмит по 4 точкам начиная с table[index] (у волн 4 лишних отсчёта на период).
@inline(__always) func interpolateWaveHermite(_ table: UnsafePointer<Int16>, _ indexIntegral: Int,
                                              _ indexFractional: Float) -> Float {
    let xm1 = Float(table[indexIntegral])
    let x0 = Float(table[indexIntegral + 1])
    let x1 = Float(table[indexIntegral + 2])
    let x2 = Float(table[indexIntegral + 3])
    let c = (x1 - xm1) * 0.5
    let v = x0 - x1
    let w = c + v
    let a = w + v + (x2 - x0) * 0.5
    let bNeg = w + a
    let f = indexFractional
    return (((a * f) - bNeg) * f + c) * f + x0
}
