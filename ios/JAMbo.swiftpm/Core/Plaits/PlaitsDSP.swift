// Перенос Mutable Instruments Plaits и stmlib (Copyright Emilie Gillet, MIT; см. Resources/licenses).
// Общие утилиты stmlib (dsp.h, units.h, polyblep.h, parameter_interpolator.h, filter.h) и таблицы Plaits.
// Таблицы выгружены из исходников ios/tools/plaits/export_tables.sh в Resources/plaits.
import Foundation

/// Таблицы Plaits: указатели живут всё время работы приложения (освобождать не нужно).
public struct PlaitsLUT {
    public let sine, fmQuantizer, fold, fold2, stiffness, svfShift, fir4x, pitchHigh, pitchLow: UnsafeMutablePointer<Float>
    /// lookup_table_i16_table: inverse tan, inverse sin, linear, bump, double bump, double bump.
    public let ws: [UnsafeMutablePointer<Int16>]
    public let wsTable: UnsafeMutablePointer<UnsafeMutablePointer<Int16>>
    public let integratedWaves: UnsafeMutablePointer<Int16>
    public let lpcPulse: UnsafeMutablePointer<Int8>
    /// Фонемы LPC: 12 значений на кадр (energy, period, k0…k9).
    public let lpcPhonemes: UnsafeMutablePointer<Int16>
    public let lpcPhonemeCount: Int

    /// Таблицы из папки dir (файлы ресурсов). nil — какого-то файла нет.
    public static func load(dir: URL) -> PlaitsLUT? {
        func raw<T>(_ name: String, _ type: T.Type) -> (UnsafeMutablePointer<T>, Int)? {
            guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            let n = d.count / MemoryLayout<T>.stride
            // Запас по краям: Plaits местами читает соседний отсчёт за краем таблицы.
            let pad = 16
            let p = UnsafeMutableRawPointer.allocate(byteCount: (n + 2 * pad) * MemoryLayout<T>.stride, alignment: 16)
            p.initializeMemory(as: UInt8.self, repeating: 0, count: (n + 2 * pad) * MemoryLayout<T>.stride)
            let base = p.advanced(by: pad * MemoryLayout<T>.stride)
            d.withUnsafeBytes { base.copyMemory(from: $0.baseAddress!, byteCount: d.count) }
            return (base.assumingMemoryBound(to: T.self), n)
        }
        func f(_ n: String) -> UnsafeMutablePointer<Float>? { raw(n + ".f32", Float.self)?.0 }
        func i(_ n: String) -> UnsafeMutablePointer<Int16>? { raw(n + ".i16", Int16.self)?.0 }
        guard let sine = f("lut_sine"), let fq = f("lut_fm_frequency_quantizer"), let fold = f("lut_fold"),
              let fold2 = f("lut_fold_2"), let stiff = f("lut_stiffness"), let svf = f("lut_svf_shift"),
              let fir = f("lut_4x_downsampler_fir"), let ph = f("lut_pitch_ratio_high"), let pl = f("lut_pitch_ratio_low"),
              let tan = i("lut_ws_inverse_tan"), let sin = i("lut_ws_inverse_sin"), let lin = i("lut_ws_linear"),
              let bump = i("lut_ws_bump"), let dbump = i("lut_ws_double_bump"),
              let waves = i("wav_integrated_waves"), let pulse = raw("lut_lpc_excitation_pulse.i8", Int8.self)?.0,
              let phon = raw("lpc_phonemes.i16", Int16.self) else { return nil }
        let ws = [tan, sin, lin, bump, dbump, dbump]
        let table = UnsafeMutablePointer<UnsafeMutablePointer<Int16>>.allocate(capacity: ws.count)
        for (k, p) in ws.enumerated() { table[k] = p }
        return PlaitsLUT(sine: sine, fmQuantizer: fq, fold: fold, fold2: fold2, stiffness: stiff, svfShift: svf,
                         fir4x: fir, pitchHigh: ph, pitchLow: pl, ws: ws, wsTable: table, integratedWaves: waves,
                         lpcPulse: pulse, lpcPhonemes: phon.0, lpcPhonemeCount: phon.1 / 12)
    }
}

/// Частота дискретизации Plaits (kCorrectedSampleRate) — как в вебе: a0 по ней, нота сдвигается в голосе.
let kCorrectedSampleRate: Float = 47872.34
let plaitsA0: Float = (440.0 / 8.0) / kCorrectedSampleRate
let kMaxBlockSize = 24
let kMaxFrequency: Float = 0.25
let kMinFrequency: Float = 0.000001

// MARK: - dsp.h

/// static_cast<int32_t>: отбрасывание дробной части (без ловушки на NaN и больших значениях).
@inline(__always) func trunc32(_ x: Float) -> Int {
    (x > -2.0e9 && x < 2.0e9) ? Int(x) : 0
}

@inline(__always) func constrain(_ x: inout Float, _ lo: Float, _ hi: Float) {
    if x < lo { x = lo } else if x > hi { x = hi }
}

@inline(__always) func interpolate(_ t: UnsafePointer<Float>, _ index: Float, _ size: Float) -> Float {
    let x = index * size
    let i = trunc32(x)
    let fr = x - Float(i)
    let a = t[i], b = t[i + 1]
    return a + (b - a) * fr
}

@inline(__always) func interpolateHermite(_ t: UnsafePointer<Float>, _ index: Float, _ size: Float) -> Float {
    let x = index * size
    let i = trunc32(x)
    let f = x - Float(i)
    let xm1 = t[i - 1], x0 = t[i], x1 = t[i + 1], x2 = t[i + 2]
    let c = (x1 - xm1) * 0.5
    let v = x0 - x1
    let w = c + v
    let a = w + v + (x2 - x0) * 0.5
    let bNeg = w + a
    return (((a * f) - bNeg) * f + c) * f + x0
}

@inline(__always) func interpolateWrap(_ t: UnsafePointer<Float>, _ index: Float, _ size: Float) -> Float {
    var x = index - Float(trunc32(index))
    x *= size
    let i = trunc32(x)
    let fr = x - Float(i)
    let a = t[i], b = t[i + 1]
    return a + (b - a) * fr
}

@inline(__always) func softLimit(_ x: Float) -> Float { x * (27 + x * x) / (27 + 9 * x * x) }
@inline(__always) func softClip(_ x: Float) -> Float { x < -3 ? -1 : (x > 3 ? 1 : softLimit(x)) }
@inline(__always) func smoothStep(_ v: Float) -> Float { v * v * (3 - 2 * v) }
@inline(__always) func crossfade(_ a: Float, _ b: Float, _ f: Float) -> Float { a + (b - a) * f }
@inline(__always) func onePole(_ out: inout Float, _ input: Float, _ c: Float) { out += c * (input - out) }
@inline(__always) func slope(_ out: inout Float, _ input: Float, _ pos: Float, _ neg: Float) {
    let e = input - out
    out += (e > 0 ? pos : neg) * e
}

/// float → uint32 (static_cast; значения вне диапазона — с переносом, без ловушки).
@inline(__always) func u32(_ x: Float) -> UInt32 {
    if !(x > -9.0e18 && x < 9.0e18) { return 0 }
    return UInt32(truncatingIfNeeded: Int64(x))
}

// MARK: - units.h

extension PlaitsLUT {
    @inline(__always) func semitonesToRatio(_ semitones: Float) -> Float {
        let pitch = semitones + 128
        let i = trunc32(pitch)
        let fr = pitch - Float(i)
        return pitchHigh[i] * pitchLow[trunc32(fr * 256)]
    }

    @inline(__always) func semitonesToRatioSafe(_ s: Float) -> Float {
        var semitones = s, scale: Float = 1
        while semitones > 120 { semitones -= 120; scale *= 1024 }
        while semitones < -120 { semitones += 120; scale *= 1.0 / 1024 }
        return scale * semitonesToRatio(semitones)
    }

    /// engine.h: NoteToFrequency.
    @inline(__always) func noteToFrequency(_ n: Float) -> Float {
        var note = n - 9
        constrain(&note, -128, 127)
        return plaitsA0 * 0.25 * semitonesToRatio(note)
    }

    // sine_oscillator.h
    @inline(__always) func sin(_ phase: Float) -> Float { interpolateWrap(sine, phase, 512) }
    @inline(__always) func sinNoWrap(_ phase: Float) -> Float { interpolate(sine, phase, 512) }
    @inline(__always) func sinePM(_ phase: UInt32, _ pm: Float) -> Float {
        let scale: Float = 4294967296.0 / 64
        let p = phase &+ (u32((pm + 32) * scale) &* 64)
        let i = Int(p >> 23)
        let fr = Float(p << 9) / 4294967296.0
        let a = sine[i], b = sine[i + 1]
        return a + (b - a) * fr
    }
}

// MARK: - polyblep.h

@inline(__always) func thisBlep(_ t: Float) -> Float { 0.5 * t * t }
@inline(__always) func nextBlep(_ t: Float) -> Float { let u = 1 - t; return -0.5 * u * u }
@inline(__always) func nextIntBlep(_ t: Float) -> Float {
    let t1 = 0.5 * t, t2 = t1 * t1, t4 = t2 * t2
    return 0.1875 - t1 + 1.5 * t2 - t4
}
@inline(__always) func thisIntBlep(_ t: Float) -> Float { nextIntBlep(1 - t) }

// MARK: - parameter_interpolator.h

/// ParameterInterpolator: после цикла значение возвращают в состояние (state = p.value), как деструктор в C++.
struct PInterp {
    var value: Float
    let increment: Float
    @inline(__always) init(_ state: Float, _ target: Float, _ size: Int) {
        value = state
        increment = (target - state) / Float(size)
    }
    @inline(__always) init(_ state: Float, _ target: Float, step: Float) {
        value = state
        increment = (target - state) * step
    }
    @inline(__always) mutating func next() -> Float { value += increment; return value }
    @inline(__always) func subsample(_ t: Float) -> Float { value + increment * t }
}

// MARK: - filter.h

enum FilterMode { case lowPass, bandPass, bandPassNormalized, highPass }

private let piF = Float.pi
private let pi3 = Double.pi * Double.pi * Double.pi
private let pi5 = pi3 * Double.pi * Double.pi
private let pi7 = pi5 * Double.pi * Double.pi
private let pi9 = pi7 * Double.pi * Double.pi
private let pi11 = pi9 * Double.pi * Double.pi
private let dirtyA = Float(Double(Float(3.736e-01)) * pi3)
private let fastA = Float(Double(Float(3.260e-01)) * pi3)
private let fastB = Float(Double(Float(1.823e-01)) * pi5)
private let accA = Float(Double(Float(3.333314036e-01)) * pi3)
private let accB = Float(Double(Float(1.333923995e-01)) * pi5)
private let accC = Float(Double(Float(5.33740603e-02)) * pi7)
private let accD = Float(Double(Float(2.900525e-03)) * pi9)
private let accE = Float(Double(Float(9.5168091e-03)) * pi11)

enum FreqApprox { case exact, accurate, fast, dirty }

@inline(__always) func filterTan(_ f: Float, _ a: FreqApprox) -> Float {
    switch a {
    case .exact: return Foundation.tan(piF * min(f, 0.497))
    case .dirty: return f * (piF + dirtyA * f * f)
    case .fast: let f2 = f * f; return f * (piF + f2 * (fastA + fastB * f2))
    case .accurate:
        let f2 = f * f
        return f * (piF + f2 * (accA + f2 * (accB + f2 * (accC + f2 * (accD + f2 * accE)))))
    }
}

struct OnePoleF {
    var g: Float = 0, gi: Float = 0, state: Float = 0
    mutating func initialize() { setF(0.01, .dirty); state = 0 }
    @inline(__always) mutating func setF(_ f: Float, _ a: FreqApprox) { g = filterTan(f, a); gi = 1 / (1 + g) }
    @inline(__always) mutating func lp(_ x: Float) -> Float {
        let l = (g * x + state) * gi
        state = g * (x - l) + l
        return l
    }
    @inline(__always) mutating func hp(_ x: Float) -> Float { x - lp(x) }
}

struct SvfF {
    var g: Float = 0, r: Float = 0, h: Float = 0, s1: Float = 0, s2: Float = 0
    mutating func initialize() { setFQ(0.01, 100, .dirty); s1 = 0; s2 = 0 }
    mutating func reset() { s1 = 0; s2 = 0 }
    @inline(__always) mutating func setFQ(_ f: Float, _ q: Float, _ a: FreqApprox) {
        g = filterTan(f, a); r = 1 / q; h = 1 / (1 + r * g + g * g)
    }
    @inline(__always) mutating func setGR(_ g: Float, _ r: Float) { self.g = g; self.r = r; h = 1 / (1 + r * g + g * g) }
    @inline(__always) mutating func setGQ(_ g: Float, _ q: Float) { self.g = g; r = 1 / q; h = 1 / (1 + r * g + g * g) }
    /// Один отсчёт: (lp, bp, hp).
    @inline(__always) mutating func step(_ x: Float) -> (lp: Float, bp: Float, hp: Float) {
        let hp = (x - r * s1 - g * s1 - s2) * h
        let bp = g * hp + s1
        s1 = g * hp + bp
        let lp = g * bp + s2
        s2 = g * bp + lp
        return (lp, bp, hp)
    }
    @inline(__always) mutating func process(_ x: Float, _ m: FilterMode) -> Float {
        let o = step(x)
        switch m {
        case .lowPass: return o.lp
        case .bandPass: return o.bp
        case .bandPassNormalized: return o.bp * r
        case .highPass: return o.hp
        }
    }
}

struct NaiveSvfF {
    var f: Float = 0, damp: Float = 0, lp: Float = 0, bp: Float = 0
    mutating func initialize() { setFQ(0.01, 100, .dirty); lp = 0; bp = 0 }
    @inline(__always) mutating func setFQ(_ f0: Float, _ q: Float, _ a: FreqApprox) {
        if a == .exact { f = 2 * Foundation.sin(piF * min(f0, 0.497)) } else { f = 2 * piF * min(f0, 0.158) }
        damp = 1 / q
    }
    @inline(__always) mutating func process(_ x: Float, _ m: FilterMode) -> Float {
        let bpn = bp * damp
        let notch = x - bpn
        lp += f * bp
        let hp = notch - lp
        bp += f * hp
        switch m {
        case .lowPass: return lp
        case .bandPass: return bp
        case .bandPassNormalized: return bpn
        case .highPass: return hp
        }
    }
}

/// 4x_downsampler.h: состояние — одно число (head), хранится в движке.
struct Downsampler4x {
    var head: Float, tail: Float = 0
    let fir: UnsafeMutablePointer<Float>
    @inline(__always) init(_ state: Float, _ fir: UnsafeMutablePointer<Float>) { head = state; self.fir = fir }
    @inline(__always) mutating func accumulate(_ i: Int, _ s: Float) {
        head += s * fir[3 - (i & 3)]
        tail += s * fir[i & 3]
    }
    @inline(__always) mutating func read() -> Float { let v = head; head = tail; tail = 0; return v }
}

/// stmlib/utils/random.h: общий генератор (LCG), как глобальный в Plaits. На голос — свой экземпляр.
final class PlaitsRandom {
    var state: UInt32 = 0x21
    @inline(__always) func word() -> UInt32 { state = state &* 1664525 &+ 1013904223; return state }
    @inline(__always) func float() -> Float { Float(word()) / 4294967296.0 }
}

// MARK: - Движок

struct EngineParameters {
    var trigger: Int = 0
    var note: Float = 48
    var timbre: Float = 0.5
    var morph: Float = 0.5
    var harmonics: Float = 0.5
    var accent: Float = 0.8
}
let triggerLow = 0, triggerRisingEdge = 1, triggerUnpatched = 2, triggerHigh = 4

protocol PlaitsEngine: AnyObject {
    func reset()
    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool)
}

/// Буфер Float на всё время жизни движка.
func plaitsBuffer(_ n: Int) -> UnsafeMutablePointer<Float> {
    let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
    p.initialize(repeating: 0, count: n)
    return p
}
