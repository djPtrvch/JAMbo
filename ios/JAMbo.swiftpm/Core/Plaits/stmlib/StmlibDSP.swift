// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// stmlib/dsp/dsp.h, polyblep.h, parameter_interpolator.h, utils/random.h, dsp/limiter.h, dsp/hysteresis_quantizer.h.
import Foundation

// MARK: - dsp.h

/// static_cast<int32_t>(x): отбрасывание дробной части. Вне диапазона Int32 и NaN — 0 (в C++ — неопределённо;
/// здесь без ловушки в аудиопотоке).
@inline(__always) func stmInt(_ x: Float) -> Int {
    (x > -2147483648 && x < 2147483648) ? Int(x) : 0
}

/// static_cast<uint32_t>(x) для x ≥ 0 (фазы и инкременты); отрицательное и NaN — 0.
@inline(__always) func stmU32(_ x: Float) -> UInt32 {
    (x >= 0 && x < 4294967296) ? UInt32(x) : 0
}

/// CONSTRAIN(x, lo, hi).
@inline(__always) func constrain(_ x: inout Float, _ lo: Float, _ hi: Float) {
    if x < lo { x = lo } else if x > hi { x = hi }
}

@inline(__always) func stmInterpolate(_ table: UnsafePointer<Float>, _ index: Float, _ size: Float) -> Float {
    let x = index * size
    let i = stmInt(x)
    let f = x - Float(i)
    let a = table[i], b = table[i + 1]
    return a + (b - a) * f
}

@inline(__always) func stmInterpolateHermite(_ table: UnsafePointer<Float>, _ index: Float, _ size: Float) -> Float {
    let x = index * size
    let i = stmInt(x)
    let f = x - Float(i)
    let xm1 = table[i - 1], x0 = table[i], x1 = table[i + 1], x2 = table[i + 2]
    let c = (x1 - xm1) * 0.5
    let v = x0 - x1
    let w = c + v
    let a = w + v + (x2 - x0) * 0.5
    let bNeg = w + a
    return (((a * f) - bNeg) * f + c) * f + x0
}

@inline(__always) func stmInterpolateWrap(_ table: UnsafePointer<Float>, _ index: Float, _ size: Float) -> Float {
    var x = index - Float(stmInt(index))
    x *= size
    let i = stmInt(x)
    let f = x - Float(i)
    let a = table[i], b = table[i + 1]
    return a + (b - a) * f
}

@inline(__always) func stmSmoothStep(_ v: Float) -> Float { v * v * (3 - 2 * v) }

/// ONE_POLE(out, in, coefficient).
@inline(__always) func onePole(_ out: inout Float, _ input: Float, _ c: Float) { out += c * (input - out) }

/// SLOPE(out, in, positive, negative).
@inline(__always) func slope(_ out: inout Float, _ input: Float, _ positive: Float, _ negative: Float) {
    let error = input - out
    out += (error > 0 ? positive : negative) * error
}

@inline(__always) func stmSoftLimit(_ x: Float) -> Float { x * (27 + x * x) / (27 + 9 * x * x) }

@inline(__always) func stmSoftClip(_ x: Float) -> Float {
    if x < -3 { return -1 }
    if x > 3 { return 1 }
    return stmSoftLimit(x)
}

// MARK: - polyblep.h

@inline(__always) func thisBlepSample(_ t: Float) -> Float { 0.5 * t * t }

@inline(__always) func nextBlepSample(_ t0: Float) -> Float {
    let t = 1 - t0
    return -0.5 * t * t
}

@inline(__always) func nextIntegratedBlepSample(_ t: Float) -> Float {
    let t1 = 0.5 * t
    let t2 = t1 * t1
    let t4 = t2 * t2
    return 0.1875 - t1 + 1.5 * t2 - t4
}

@inline(__always) func thisIntegratedBlepSample(_ t: Float) -> Float { nextIntegratedBlepSample(1 - t) }

// MARK: - parameter_interpolator.h

/// ParameterInterpolator. В C++ деструктор пишет value_ обратно в *state; здесь — явно: `state = p.value`.
struct ParameterInterpolator {
    var value: Float
    let increment: Float

    @inline(__always) init(_ state: Float, _ newValue: Float, _ size: Int) {
        value = state
        increment = (newValue - state) / Float(size)
    }

    @inline(__always) init(_ state: Float, _ newValue: Float, step: Float) {
        value = state
        increment = (newValue - state) * step
    }

    @inline(__always) mutating func next() -> Float {
        value += increment
        return value
    }

    @inline(__always) func subsample(_ t: Float) -> Float { value + increment * t }
}

// MARK: - utils/random.h

/// stmlib::Random. В оригинале — глобальное состояние (в вебе — одно на экземпляр wasm, т. е. на дорожку);
/// здесь — экземпляр, общий для движков голоса. Начальное состояние 0x21.
final class StmRandom {
    var state: UInt32 = 0x21

    @inline(__always) func getWord() -> UInt32 {
        state = state &* 1664525 &+ 1013904223
        return state
    }

    @inline(__always) func getSample() -> Int16 { Int16(truncatingIfNeeded: getWord() >> 16) }

    @inline(__always) func getFloat() -> Float { Float(getWord()) / 4294967296.0 }
}

// MARK: - dsp/limiter.h

struct StmLimiter {
    var peak: Float = 0.5

    mutating func initialize() { peak = 0.5 }

    mutating func process(_ preGain: Float, _ inOut: UnsafeMutablePointer<Float>, _ size: Int) {
        for i in 0..<size {
            let s = inOut[i] * preGain
            slope(&peak, abs(s), 0.05, 0.00002)
            let gain: Float = peak <= 1 ? 1 : 1 / peak
            inOut[i] = s * gain * 0.8
        }
    }
}

// MARK: - dsp/hysteresis_quantizer.h

/// HysteresisQuantizer2.
struct HysteresisQuantizer2 {
    var numSteps = 1
    var hysteresis: Float = 0
    var scale: Float = 1
    var offset: Float = 0
    var quantizedValue = 0

    mutating func initialize(_ steps: Int, _ hyst: Float, symmetric: Bool) {
        numSteps = steps
        hysteresis = hyst
        scale = Float(symmetric ? steps - 1 : steps)
        offset = symmetric ? 0 : -0.5
        quantizedValue = 0
    }

    @inline(__always) mutating func process(_ v: Float, base: Int = 0) -> Int {
        var value = v * scale
        value += offset
        value += Float(base)
        let sign: Float = value > Float(quantizedValue) ? -1 : 1
        var q = stmInt(value + sign * hysteresis + 0.5)
        if q < 0 { q = 0 } else if q > numSteps - 1 { q = numSteps - 1 }
        quantizedValue = q
        return q
    }
}

// MARK: - dsp/dsp.h, rsqrt.h

/// fast_rsqrt_carmack.
@inline(__always) func fastRsqrtCarmack(_ x: Float) -> Float {
    var i = x.bitPattern
    i = 0x5f3759df &- (i >> 1)
    var y = Float(bitPattern: i)
    let x2 = x * 0.5
    y = y * (1.5 - (x2 * y * y))
    return y
}

/// Crossfade(a, b, fade).
@inline(__always) func stmCrossfade(_ a: Float, _ b: Float, _ fade: Float) -> Float { a + (b - a) * fade }

/// Clip16.
@inline(__always) func stmClip16(_ x: Int32) -> Int32 { x < -32768 ? -32768 : (x > 32767 ? 32767 : x) }

// MARK: - dsp/cosine_oscillator.h

/// CosineOscillator (режим APPROXIMATE — единственный, нужный Plaits).
struct CosineOscillator {
    private var y1: Float = 0
    private var y0: Float = 0
    private var iirCoefficient: Float = 0
    private var initialAmplitude: Float = 0

    mutating func initApproximate(_ frequencyIn: Float) {
        var frequency = frequencyIn
        var sign: Float = 16
        frequency -= 0.25
        if frequency < 0 {
            frequency = -frequency
        } else {
            if frequency > 0.5 {
                frequency -= 0.5
            } else {
                sign = -16
            }
        }
        iirCoefficient = sign * frequency * (1 - 2 * frequency)
        initialAmplitude = iirCoefficient * 0.25
        start()
    }

    mutating func start() {
        y1 = initialAmplitude
        y0 = 0.5
    }

    @inline(__always) var value: Float { y1 + 0.5 }

    @inline(__always) mutating func next() -> Float {
        let temp = y0
        y0 = iirCoefficient * y0 - y1
        y1 = temp
        return temp + 0.5
    }
}
