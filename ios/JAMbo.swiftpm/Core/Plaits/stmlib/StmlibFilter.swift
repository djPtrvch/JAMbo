// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// stmlib/dsp/filter.h: OnePole, Svf, NaiveSvf (то, что нужно движкам Plaits).
import Foundation

enum FilterMode { case lowPass, bandPass, bandPassNormalized, highPass }
enum FrequencyApproximation { case exact, accurate, fast, dirty }

/// Константы tan<approximation>: в C++ — float·M_PI_POW_n (double), результат приводится к float.
private enum FilterK {
    static let pi = Double.pi
    static let dirtyA = Float(Double(Float(3.736e-01)) * pi * pi * pi)
    static let fastA = Float(Double(Float(3.260e-01)) * pi * pi * pi)
    static let fastB = Float(Double(Float(1.823e-01)) * pi * pi * pi * pi * pi)
    static let accA = Float(Double(Float(3.333314036e-01)) * pi * pi * pi)
    static let accB = Float(Double(Float(1.333923995e-01)) * pi * pi * pi * pi * pi)
    static let accC = Float(Double(Float(5.33740603e-02)) * pow(pi, 7))
    static let accD = Float(Double(Float(2.900525e-03)) * pow(pi, 9))
    static let accE = Float(Double(Float(9.5168091e-03)) * pow(pi, 11))
}

/// OnePole::tan<approximation>(f).
@inline(__always) func filterTan(_ f: Float, _ approximation: FrequencyApproximation) -> Float {
    let piF = Float.pi
    switch approximation {
    case .exact:
        return Foundation.tan(piF * (f < 0.497 ? f : 0.497))
    case .dirty:
        return f * (piF + FilterK.dirtyA * f * f)
    case .fast:
        let f2 = f * f
        return f * (piF + f2 * (FilterK.fastA + FilterK.fastB * f2))
    case .accurate:
        let f2 = f * f
        return f * (piF + f2 * (FilterK.accA + f2 * (FilterK.accB + f2 * (FilterK.accC + f2 * (FilterK.accD + f2 * FilterK.accE)))))
    }
}

struct OnePole {
    var g: Float = 0, gi: Float = 0, state: Float = 0

    mutating func initialize() {
        setF(0.01, .dirty)
        state = 0
    }

    @inline(__always) mutating func setF(_ f: Float, _ approximation: FrequencyApproximation) {
        g = filterTan(f, approximation)
        gi = 1 / (1 + g)
    }

    @inline(__always) mutating func process(_ input: Float, _ mode: FilterMode) -> Float {
        let lp = (g * input + state) * gi
        state = g * (input - lp) + lp
        switch mode {
        case .lowPass: return lp
        case .highPass: return input - lp
        default: return 0
        }
    }
}

struct Svf {
    var g: Float = 0, r: Float = 0, h: Float = 0, state1: Float = 0, state2: Float = 0

    mutating func initialize() {
        setFQ(0.01, 100, .dirty)
        state1 = 0
        state2 = 0
    }

    @inline(__always) mutating func setFQ(_ f: Float, _ resonance: Float, _ approximation: FrequencyApproximation) {
        g = filterTan(f, approximation)
        r = 1 / resonance
        h = 1 / (1 + r * g + g * g)
    }

    @inline(__always) mutating func setGR(_ g: Float, _ r: Float) {
        self.g = g
        self.r = r
        h = 1 / (1 + r * g + g * g)
    }

    @inline(__always) mutating func setGQ(_ g: Float, _ resonance: Float) {
        self.g = g
        r = 1 / resonance
        h = 1 / (1 + r * g + g * g)
    }

    @inline(__always) mutating func process(_ input: Float, _ mode: FilterMode) -> Float {
        let hp = (input - r * state1 - g * state1 - state2) * h
        let bp = g * hp + state1
        state1 = g * hp + bp
        let lp = g * bp + state2
        state2 = g * bp + lp
        switch mode {
        case .lowPass: return lp
        case .bandPass: return bp
        case .bandPassNormalized: return bp * r
        case .highPass: return hp
        }
    }

    /// ProcessAdd<mode>: out += gain · фильтр(in).
    @inline(__always) mutating func processAdd(_ input: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>,
                                               _ size: Int, _ gain: Float, _ mode: FilterMode) {
        for i in 0..<size { out[i] += gain * process(input[i], mode) }
    }
}

struct NaiveSvf {
    var f: Float = 0, damp: Float = 0, lp: Float = 0, bp: Float = 0

    mutating func initialize() {
        setFQ(0.01, 100, .dirty)
        lp = 0
        bp = 0
    }

    @inline(__always) mutating func setFQ(_ freq: Float, _ resonance: Float, _ approximation: FrequencyApproximation) {
        if approximation == .exact {
            f = 2 * Foundation.sin(Float.pi * (freq < 0.497 ? freq : 0.497))
        } else {
            f = 2 * Float.pi * (freq < 0.158 ? freq : 0.158)
        }
        damp = 1 / resonance
    }

    @inline(__always) mutating func process(_ input: Float, _ mode: FilterMode) -> Float {
        let bpNormalized = bp * damp
        let notch = input - bpNormalized
        lp += f * bp
        let hp = notch - lp
        bp += f * hp
        switch mode {
        case .lowPass: return lp
        case .bandPass: return bp
        case .bandPassNormalized: return bpNormalized
        case .highPass: return hp
        }
    }
}
