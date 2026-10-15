// Перенос осцилляторов Plaits (Copyright Emilie Gillet, MIT): oscillator.h, variable_shape_oscillator.h,
// variable_saw_oscillator.h, sine_oscillator.h, grainlet_oscillator.h, z_oscillator.h, harmonic_oscillator.h.

enum OscShape { case impulseTrain, saw, triangle, slope, square, squareBright, squareDark, squareTriangle }

/// oscillator.h (без внешней FM — в первых движках она не нужна).
struct PlaitsOscillator {
    var phase: Float = 0.5, nextSample: Float = 0, lpState: Float = 1, hpState: Float = 0
    var high = true, frequency: Float = 0.001, pw: Float = 0.5

    mutating func initialize() { self = PlaitsOscillator() }

    mutating func render(_ shape: OscShape, _ freq: Float, _ pwIn: Float, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var f0 = freq
        constrain(&f0, kMinFrequency, kMaxFrequency)
        var pw0 = pwIn
        constrain(&pw0, abs(f0) * 2, 1 - 2 * abs(f0))
        var fm = PInterp(frequency, f0, size)
        var pwm = PInterp(pw, pw0, size)
        var next = nextSample
        for n in 0..<size {
            var this = next
            next = 0
            let frequency = fm.next()
            let pw = (shape == .squareTriangle || shape == .triangle) ? 0.5 : pwm.next()
            phase += frequency
            if shape == .impulseTrain || shape == .saw {
                if phase >= 1 {
                    phase -= 1
                    let t = phase / frequency
                    this -= thisBlep(t)
                    next -= nextBlep(t)
                }
                next += phase
                if shape == .saw {
                    out[n] = 2 * this - 1
                } else {
                    lpState += 0.25 * ((hpState - this) - lpState)
                    out[n] = 4 * lpState
                    hpState = this
                }
            } else if shape == .triangle || shape == .slope {
                var up: Float = 2, down: Float = 2
                if shape == .slope { up = 1 / pw; down = 1 / (1 - pw) }
                if high != (phase < pw) {
                    let t = (phase - pw) / frequency
                    let d = (up + down) * frequency
                    this -= thisIntBlep(t) * d
                    next -= nextIntBlep(t) * d
                    high = phase < pw
                }
                if phase >= 1 {
                    phase -= 1
                    let t = phase / frequency
                    let d = (up + down) * frequency
                    this += thisIntBlep(t) * d
                    next += nextIntBlep(t) * d
                    high = true
                }
                next += high ? phase * up : 1 - (phase - pw) * down
                out[n] = 2 * this - 1
            } else {
                if high != (phase >= pw) {
                    let t = (phase - pw) / frequency
                    this += thisBlep(t)
                    next += nextBlep(t)
                    high = phase >= pw
                }
                if phase >= 1 {
                    phase -= 1
                    let t = phase / frequency
                    this -= thisBlep(t)
                    next -= nextBlep(t)
                    high = false
                }
                next += phase < pw ? 0 : 1
                switch shape {
                case .squareTriangle:
                    let c = frequency * 0.0625
                    this = 128 * (this - 0.5)
                    lpState += c * (this - lpState)
                    out[n] = lpState
                case .squareDark:
                    let c = frequency * 2
                    this = 4 * (this - 0.5)
                    lpState += c * (this - lpState)
                    out[n] = lpState
                case .squareBright:
                    let c = frequency * 2
                    this = 2 * this - 1
                    lpState += c * (this - lpState)
                    out[n] = (this - lpState) * 0.5
                default:
                    out[n] = 2 * this - 1
                }
            }
        }
        nextSample = next
        frequency = fm.value
        pw = pwm.value
    }
}

/// variable_shape_oscillator.h.
struct VariableShapeOscillator {
    var masterPhase: Float = 0, slavePhase: Float = 0, nextSample: Float = 0, previousPw: Float = 0.5
    var high = false
    var masterFrequency: Float = 0, slaveFrequency: Float = 0.01, pw: Float = 0.5, waveshape: Float = 0
    var phaseModulation: Float = 0

    mutating func initialize() { self = VariableShapeOscillator() }

    @inline(__always) private func naive(_ phase: Float, _ pw: Float, _ up: Float, _ down: Float, _ tri: Float, _ sq: Float) -> Float {
        var saw = phase
        let square: Float = phase < pw ? 0 : 1
        let triangle = phase < pw ? phase * up : 1 - (phase - pw) * down
        saw += (square - saw) * sq
        saw += (triangle - saw) * tri
        return saw
    }

    mutating func render(_ frequency: Float, _ pw: Float, _ waveshape: Float, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        render(sync: false, outputPhase: false, 0, frequency, pw, waveshape, 0, out, size)
    }

    mutating func render(_ master: Float, _ frequency: Float, _ pw: Float, _ waveshape: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        render(sync: true, outputPhase: false, master, frequency, pw, waveshape, 0, out, size)
    }

    mutating func render(sync: Bool, outputPhase: Bool, _ masterIn: Float, _ freqIn: Float, _ pwIn: Float,
                         _ shapeIn: Float, _ pmAmount: Float, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let master0 = masterIn >= kMaxFrequency ? kMaxFrequency : masterIn
        let freq0 = freqIn >= kMaxFrequency ? kMaxFrequency : freqIn
        var pw0 = pwIn
        if freq0 >= 0.25 { pw0 = 0.5 } else { constrain(&pw0, freq0 * 2, 1 - 2 * freq0) }
        var masterFm = PInterp(masterFrequency, master0, size)
        var fm = PInterp(slaveFrequency, freq0, size)
        var pwm = PInterp(pw, pw0, size)
        var wsm = PInterp(waveshape, shapeIn, size)
        var pmm = PInterp(phaseModulation, pmAmount, size)
        var next = nextSample
        for n in 0..<size {
            var reset = false
            var transition = false
            var resetTime: Float = 0
            var this = next
            next = 0
            let mf = masterFm.next()
            let sf = fm.next()
            let pw = pwm.next()
            let ws = wsm.next()
            let sq = max(ws - 0.5, 0) * 2
            let tri = max(1 - ws * 2, 0)
            let up = 1 / pw
            let down = 1 / (1 - pw)
            if sync {
                masterPhase += mf
                if masterPhase >= 1 {
                    masterPhase -= 1
                    resetTime = masterPhase / mf
                    var at = slavePhase + (1 - resetTime) * sf
                    reset = true
                    if at >= 1 { at -= 1; transition = true }
                    if !high && at >= pw { transition = true }
                    let v = naive(at, pw, up, down, tri, sq)
                    this -= v * thisBlep(resetTime)
                    next -= v * nextBlep(resetTime)
                }
            } else if outputPhase {
                masterPhase += mf
                if masterPhase >= 1 { masterPhase -= 1 }
            }
            slavePhase += sf
            while transition || !reset {
                if !high {
                    if slavePhase < pw { break }
                    let t = (slavePhase - pw) / (previousPw - pw + sf)
                    var step = (up + down) * sf
                    step *= tri
                    this += sq * thisBlep(t)
                    next += sq * nextBlep(t)
                    this -= step * thisIntBlep(t)
                    next -= step * nextIntBlep(t)
                    high = true
                }
                if high {
                    if slavePhase < 1 { break }
                    slavePhase -= 1
                    let t = slavePhase / sf
                    var step = (up + down) * sf
                    step *= tri
                    this -= (1 - tri) * thisBlep(t)
                    next -= (1 - tri) * nextBlep(t)
                    this += step * thisIntBlep(t)
                    next += step * nextIntBlep(t)
                    high = false
                }
            }
            if sync && reset {
                slavePhase = resetTime * sf
                high = false
            }
            next += naive(slavePhase, pw, up, down, tri, sq)
            previousPw = pw
            if outputPhase {
                var phasor = masterPhase
                if sync {
                    let w = 4 * (1 - masterPhase) * masterPhase
                    this *= w * (2 - w)
                    let p2 = phasor * phasor
                    phasor += (p2 * p2 - phasor) * abs(pw - 0.5) * 2
                }
                out[n] = phasor + pmm.next() * this
            } else {
                out[n] = 2 * this - 1
            }
        }
        nextSample = next
        masterFrequency = masterFm.value
        slaveFrequency = fm.value
        pw = pwm.value
        waveshape = wsm.value
        phaseModulation = pmm.value
    }
}

/// variable_saw_oscillator.h.
struct VariableSawOscillator {
    var phase: Float = 0, nextSample: Float = 0, previousPw: Float = 0.5, high = false
    var frequency: Float = 0.01, pw: Float = 0.5, waveshape: Float = 0
    static let notchDepth: Float = 0.2

    mutating func initialize() { self = VariableSawOscillator() }

    mutating func render(_ freqIn: Float, _ pwIn: Float, _ shapeIn: Float, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let freq0 = freqIn >= kMaxFrequency ? kMaxFrequency : freqIn
        var pw0 = pwIn
        if freq0 >= 0.25 { pw0 = 0.5 } else { constrain(&pw0, freq0 * 2, 1 - 2 * freq0) }
        var fm = PInterp(frequency, freq0, size)
        var pwm = PInterp(pw, pw0, size)
        var wsm = PInterp(waveshape, shapeIn, size)
        var next = nextSample
        let depth = VariableSawOscillator.notchDepth
        for n in 0..<size {
            var this = next
            next = 0
            let f = fm.next()
            let pw = pwm.next()
            let ws = wsm.next()
            let tri = ws
            let notchAmount = 1 - ws
            let up = 1 / pw
            let down = 1 / (1 - pw)
            phase += f
            if !high && phase >= pw {
                let step = (up + down) * f * tri
                let notch = (depth + 1 - pw) * notchAmount
                let t = (phase - pw) / (previousPw - pw + f)
                this += notch * thisBlep(t)
                next += notch * nextBlep(t)
                this -= step * thisIntBlep(t)
                next -= step * nextIntBlep(t)
                high = true
            } else if phase >= 1 {
                phase -= 1
                let step = (up + down) * f * tri
                let notch = (depth + 1) * notchAmount
                let t = phase / f
                this -= notch * thisBlep(t)
                next -= notch * nextBlep(t)
                this += step * thisIntBlep(t)
                next += step * nextIntBlep(t)
                high = false
            }
            let notchSaw = phase < pw ? phase : 1 + depth
            let triangle = phase < pw ? phase * up : 1 - (phase - pw) * down
            next += notchSaw * notchAmount + triangle * tri
            previousPw = pw
            out[n] = (2 * this - 1) / (1 + depth)
        }
        nextSample = next
        frequency = fm.value
        pw = pwm.value
        waveshape = wsm.value
    }
}

/// sine_oscillator.h: SineOscillator.
struct SineOscillator {
    var phase: Float = 0, frequency: Float = 0, amplitude: Float = 0

    @inline(__always) mutating func next(_ f: Float, _ lut: PlaitsLUT) -> Float {
        phase += min(f, 0.5)
        if phase >= 1 { phase -= 1 }
        return lut.sinNoWrap(phase)
    }

    mutating func render(_ f: Float, _ amp: Float, additive: Bool, _ out: UnsafeMutablePointer<Float>, _ size: Int, _ lut: PlaitsLUT) {
        var fm = PInterp(frequency, min(f, 0.5), size)
        var am = PInterp(amplitude, amp, size)
        for n in 0..<size {
            phase += fm.next()
            if phase >= 1 { phase -= 1 }
            let s = lut.sinNoWrap(phase)
            if additive { out[n] += am.next() * s } else { out[n] = s }
        }
        frequency = fm.value
        amplitude = am.value
    }
}

/// grainlet_oscillator.h.
struct GrainletOscillator {
    var carrierPhase: Float = 0, formantPhase: Float = 0, nextSample: Float = 0
    var carrierFrequency: Float = 0, formantFrequency: Float = 0, carrierShape: Float = 0, carrierBleed: Float = 0

    @inline(__always) private func carrier(_ p: Float, _ s: Float, _ lut: PlaitsLUT) -> Float {
        var phase = p
        let shape = s * 3
        let si = trunc32(shape)
        let sf = shape - Float(si)
        var t = 1 - sf
        if si == 0 {
            phase = phase * (1 + t * t * t * 15)
            if phase >= 1 { phase = 1 }
            phase += 0.75
        } else if si == 1 {
            let bp = 0.001 + 0.499 * t * t * t
            if phase < bp { phase *= (0.5 / bp) } else { phase = 0.5 + (phase - bp) * 0.5 / (1 - bp) }
            phase += 0.75
        } else {
            t = 1 - t
            phase = 0.25 + phase * (0.5 + t * t * t * 14.5)
            if phase >= 0.75 { phase = 0.75 }
        }
        return (lut.sin(phase) + 1) * 0.25
    }

    @inline(__always) private func grainlet(_ cp: Float, _ fp: Float, _ shape: Float, _ bleed: Float, _ lut: PlaitsLUT) -> Float {
        let c = carrier(cp, shape, lut)
        let f = lut.sin(fp)
        return c * (f + bleed) / (1 + bleed)
    }

    mutating func render(_ cf: Float, _ ff: Float, _ shape: Float, _ bleed: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int, _ lut: PlaitsLUT) {
        let cf0 = cf >= kMaxFrequency * 0.5 ? kMaxFrequency * 0.5 : cf
        let ff0 = ff >= kMaxFrequency ? kMaxFrequency : ff
        var cfm = PInterp(carrierFrequency, cf0, size)
        var ffm = PInterp(formantFrequency, ff0, size)
        var csm = PInterp(carrierShape, shape, size)
        var cbm = PInterp(carrierBleed, bleed, size)
        var next = nextSample
        for n in 0..<size {
            var this = next
            next = 0
            let f0 = cfm.next()
            let f1 = ffm.next()
            carrierPhase += f0
            if carrierPhase >= 1 {
                carrierPhase -= 1
                let rt = carrierPhase / f0
                let before = grainlet(1, formantPhase + (1 - rt) * f1, csm.subsample(1 - rt), cbm.subsample(1 - rt), lut)
                let after = grainlet(0, 0, csm.subsample(1), cbm.subsample(1), lut)
                let d = after - before
                this += d * thisBlep(rt)
                next += d * nextBlep(rt)
                formantPhase = rt * f1
            } else {
                formantPhase += f1
                if formantPhase >= 1 { formantPhase -= 1 }
            }
            next += grainlet(carrierPhase, formantPhase, csm.next(), cbm.next(), lut)
            out[n] = this
        }
        nextSample = next
        carrierFrequency = cfm.value
        formantFrequency = ffm.value
        carrierShape = csm.value
        carrierBleed = cbm.value
    }
}

/// z_oscillator.h.
struct ZOscillator {
    var carrierPhase: Float = 0, discontinuityPhase: Float = 0, formantPhase: Float = 0, nextSample: Float = 0
    var carrierFrequency: Float = 0, formantFrequency: Float = 0, carrierShape: Float = 0, mode: Float = 0

    @inline(__always) private func z(_ c: Float, _ d: Float, _ f: Float, _ s: Float, _ mode: Float, _ lut: PlaitsLUT) -> Float {
        var rampDown = 0.5 * (1 + lut.sin(0.5 * d + 0.25))
        let offset: Float
        let phaseShift: Float
        if mode < 0.333 {
            offset = 1
            phaseShift = 0.25 + mode * 1.50
        } else if mode < 0.666 {
            phaseShift = 0.7495 - (mode - 0.33) * 0.75
            offset = -lut.sin(phaseShift)
        } else {
            phaseShift = 0.7495 - (mode - 0.33) * 0.75
            offset = 0.001
        }
        let disc = lut.sin(f + phaseShift)
        let contour: Float
        var shape = s
        if shape < 0.5 {
            shape *= 2
            if c >= 0.5 { rampDown *= shape }
            contour = 1 + (lut.sin(c + 0.25) - 1) * shape
        } else {
            contour = lut.sin(c + shape * 0.5)
        }
        return (rampDown * (offset + disc) - offset) * contour
    }

    mutating func render(_ cf: Float, _ ff: Float, _ shape: Float, _ modeIn: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int, _ lut: PlaitsLUT) {
        let cf0 = cf >= kMaxFrequency * 0.5 ? kMaxFrequency * 0.5 : cf
        let ff0 = ff >= kMaxFrequency ? kMaxFrequency : ff
        var cfm = PInterp(carrierFrequency, cf0, size)
        var ffm = PInterp(formantFrequency, ff0, size)
        var csm = PInterp(carrierShape, shape, size)
        var mm = PInterp(mode, modeIn, size)
        var next = nextSample
        for n in 0..<size {
            var this = next
            next = 0
            let f0 = cfm.next()
            let f1 = ffm.next()
            discontinuityPhase += 2 * f0
            carrierPhase += f0
            if discontinuityPhase >= 1 {
                discontinuityPhase -= 1
                let rt = discontinuityPhase / (2 * f0)
                let before = z(carrierPhase >= 1 ? 1 : 0.5, 1, formantPhase + (1 - rt) * f1,
                               csm.subsample(1 - rt), mm.subsample(1 - rt), lut)
                let after = z(carrierPhase >= 1 ? 0 : 0.5, 0, 0, csm.subsample(1), mm.subsample(1), lut)
                let d = after - before
                this += d * thisBlep(rt)
                next += d * nextBlep(rt)
                formantPhase = rt * f1
                if carrierPhase > 1 { carrierPhase = discontinuityPhase * 0.5 }
            } else {
                formantPhase += f1
                if formantPhase >= 1 { formantPhase -= 1 }
            }
            if carrierPhase >= 1 { carrierPhase -= 1 }
            next += z(carrierPhase, discontinuityPhase, formantPhase, csm.next(), mm.next(), lut)
            out[n] = this
        }
        nextSample = next
        carrierFrequency = cfm.value
        formantFrequency = ffm.value
        carrierShape = csm.value
        mode = mm.value
    }
}

/// harmonic_oscillator.h: 12 гармоник от first (1 или 13).
final class HarmonicOscillator {
    static let count = 12
    var phase: Float = 0, frequency: Float = 0
    let amplitude = plaitsBuffer(12)
    private let value = plaitsBuffer(12)
    private let increment = plaitsBuffer(12)

    func render(first: Int, _ f: Float, _ amps: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ size: Int, _ lut: PlaitsLUT) {
        let freq = min(f, 0.5)
        var fm = PInterp(frequency, freq, size)
        for i in 0..<12 {
            var hf = freq * Float(first + i)
            if hf >= 0.5 { hf = 0.5 }
            value[i] = amplitude[i]
            increment[i] = (amps[i] * (1 - hf * 2) - amplitude[i]) / Float(size)
        }
        let k = Float(first)
        for n in 0..<size {
            phase += fm.next()
            if phase >= 1 { phase -= 1 }
            let twoX = 2 * lut.sinNoWrap(phase)
            var previous: Float, current: Float
            if first == 1 {
                previous = 1
                current = twoX * 0.5
            } else {
                previous = lut.sin(phase * (k - 1) + 0.25)
                current = lut.sin(phase * k)
            }
            var sum: Float = 0
            for i in 0..<12 {
                value[i] += increment[i]
                sum += value[i] * current
                let temp = current
                current = twoX * current - previous
                previous = temp
            }
            if first == 1 { out[n] = sum } else { out[n] += sum }
        }
        frequency = fm.value
        for i in 0..<12 { amplitude[i] = value[i] }
    }
}
