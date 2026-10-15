// Перенос движков Plaits 5–6 (Copyright Emilie Gillet, MIT): wavetable_engine, chord_engine.

/// 5 — WAVETABLE: 4 банка по 64 волны (8×8), интерполяция по x, y и банку z.
final class WavetableEngine: PlaitsEngine {
    let lut: PlaitsLUT
    var phase: Float = 0
    var xPre: Float = 0, yPre: Float = 0, zPre: Float = 0
    var xLp: Float = 0, yLp: Float = 0, zLp: Float = 0
    var prevX: Float = 0, prevY: Float = 0, prevZ: Float = 0, prevF0 = plaitsA0
    var diffLp: Float = 0, diffPrev: Float = 0
    /// Смещения волн в wav_integrated_waves (LoadUserData без своих волн).
    let waveMap: UnsafeMutablePointer<Int>

    init(_ lut: PlaitsLUT) {
        self.lut = lut
        waveMap = .allocate(capacity: 256)
        for bank in 0..<4 {
            for wave in 0..<64 {
                let i = bank * 64 + wave
                let w = bank == 3 ? (i * 101 % 192) : i
                waveMap[i] = w * (128 + 4)
            }
        }
    }
    func reset() {}

    @inline(__always) private func clampQ(_ x: Float, _ amount: Float) -> Float {
        var v = (x - 0.5) * amount
        constrain(&v, -0.5, 0.5)
        return v + 0.5
    }

    @inline(__always) private func read(_ x: Int, _ y: Int, _ z: Int, _ pi: Int, _ pf: Float) -> Float {
        let t = lut.integratedWaves + waveMap[x + y * 8 + z * 64] + pi
        let xm1 = Float(t[0]), x0 = Float(t[1]), x1 = Float(t[2]), x2 = Float(t[3])
        let c = (x1 - xm1) * 0.5
        let v = x0 - x1
        let w = c + v
        let a = w + v + (x2 - x0) * 0.5
        let bNeg = w + a
        return (((a * pf) - bNeg) * pf + c) * pf + x0
    }

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        let f0 = lut.noteToFrequency(p.note)
        onePole(&xPre, p.timbre * 6.9999, 0.2)
        onePole(&yPre, p.morph * 6.9999, 0.2)
        onePole(&zPre, p.harmonics * 6.9999, 0.05)
        let quantization = min(max(zPre - 3, 0), 1)
        let lpc = min(max(2 * f0 * (4 - 3 * quantization), 0.01), 0.1)
        let xi = trunc32(xPre), yi = trunc32(yPre), zi = trunc32(zPre)
        var xf = xPre - Float(xi), yf = yPre - Float(yi), zf = zPre - Float(zi)
        xf += quantization * (clampQ(xf, 16) - xf)
        yf += quantization * (clampQ(yf, 16) - yf)
        zf += quantization * (clampQ(zf, 16) - zf)
        var xm = PInterp(prevX, Float(xi) + xf, size)
        var ym = PInterp(prevY, Float(yi) + yf, size)
        var zm = PInterp(prevZ, Float(zi) + zf, size)
        var fm = PInterp(prevF0, f0, size)
        for n in 0..<size {
            let f = fm.next()
            let gain = (1 / (f * 131072)) * (0.95 - f)
            let cutoff = min(128 * f, 1)
            onePole(&xLp, xm.next(), lpc)
            onePole(&yLp, ym.next(), lpc)
            onePole(&zLp, zm.next(), lpc)
            let x = xLp, y = yLp, z = zLp
            let x0 = trunc32(x), y0 = trunc32(y)
            let zInt = trunc32(z)
            let xfr = x - Float(x0), yfr = y - Float(y0), zfr = z - Float(zInt)
            phase += f
            if phase >= 1 { phase -= 1 }
            let pp = phase * 128
            let pi = trunc32(pp)
            let pf = pp - Float(pi)
            let x1 = x0 + 1, y1 = y0 + 1
            var z0 = zInt, z1 = zInt + 1
            if z0 >= 4 { z0 = 7 - z0 }
            if z1 >= 4 { z1 = 7 - z1 }
            let a000 = read(x0, y0, z0, pi, pf), a100 = read(x1, y0, z0, pi, pf)
            let xy0z0 = a000 + (a100 - a000) * xfr
            let a010 = read(x0, y1, z0, pi, pf), a110 = read(x1, y1, z0, pi, pf)
            let xy1z0 = a010 + (a110 - a010) * xfr
            let xyz0 = xy0z0 + (xy1z0 - xy0z0) * yfr
            let a001 = read(x0, y0, z1, pi, pf), a101 = read(x1, y0, z1, pi, pf)
            let xy0z1 = a001 + (a101 - a001) * xfr
            let a011 = read(x0, y1, z1, pi, pf), a111 = read(x1, y1, z1, pi, pf)
            let xy1z1 = a011 + (a111 - a011) * xfr
            let xyz1 = xy0z1 + (xy1z1 - xy0z1) * yfr
            var mix = xyz0 + (xyz1 - xyz0) * zfr
            onePole(&diffLp, mix - diffPrev, cutoff)
            diffPrev = mix
            mix = diffLp * gain
            out[n] = mix
            aux[n] = Float(trunc32(mix * 32)) / 32
        }
        prevX = xm.value
        prevY = ym.value
        prevZ = zm.value
        prevF0 = fm.value
    }
}

/// stmlib HysteresisQuantizer2.
struct HysteresisQuantizer2 {
    var numSteps = 1, hysteresis: Float = 0, scale: Float = 1, offset: Float = 0, value = 0
    init(_ steps: Int, _ hysteresis: Float, symmetric: Bool) {
        numSteps = steps
        self.hysteresis = hysteresis
        scale = Float(symmetric ? steps - 1 : steps)
        offset = symmetric ? 0 : -0.5
    }
    @inline(__always) mutating func process(_ v: Float, base: Int = 0) -> Int {
        var x = v * scale
        x += offset
        x += Float(base)
        let sign: Float = x > Float(value) ? -1 : 1
        var q = trunc32(x + sign * hysteresis + 0.5)
        q = min(max(q, 0), numSteps - 1)
        value = q
        return q
    }
}

/// string_synth_oscillator.h: делитель частоты (органные регистры 8′, 4′, 2′, 1′).
struct StringSynthOscillator {
    var phase: Float = 0, nextSample: Float = 0, segment = 0
    var frequency: Float = 0.001, saw8: Float = 0, saw4: Float = 0, saw2: Float = 0, saw1: Float = 0

    mutating func render(_ f: Float, _ reg0: UnsafePointer<Float>, _ gain: Float, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var freq = f * 8
        var shift = 0
        while freq > 0.5 { shift += 2; freq *= 0.5 }
        if shift >= 8 { return }
        var r: (Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &r) { raw in
            let reg = raw.bindMemory(to: Float.self)
            for i in 0..<(7 - shift) { reg[shift + i] = reg0[i] }
        }
        var fm = PInterp(frequency, freq, size)
        var g8 = PInterp(saw8, (r.0 + 2 * r.1) * gain, size)
        var g4 = PInterp(saw4, (r.2 - r.1 + 2 * r.3) * gain, size)
        var g2 = PInterp(saw2, (r.4 - r.3 + 2 * r.5) * gain, size)
        var g1 = PInterp(saw1, (r.6 - r.5) * gain, size)
        var ph = phase
        var next = nextSample
        var seg = segment
        for n in 0..<size {
            var this = next
            next = 0
            let fr = fm.next()
            let s8 = g8.next(), s4 = g4.next(), s2 = g2.next(), s1 = g1.next()
            ph += fr
            var ns = trunc32(ph)
            if ns != seg {
                var d: Float = 0
                if ns == 8 { ph -= 8; ns -= 8; d -= s8 }
                if ns & 3 == 0 { d -= s4 }
                if ns & 1 == 0 { d -= s2 }
                d -= s1
                if d != 0 {
                    let t = (ph - Float(ns)) / fr
                    this += thisBlep(t) * d
                    next += nextBlep(t) * d
                }
            }
            seg = ns
            next += (ph - 4) * s8 * 0.125
            next += (ph - Float(seg & 4) - 2) * s4 * 0.25
            next += (ph - Float(seg & 6) - 1) * s2 * 0.5
            next += (ph - Float(seg & 7) - 0.5) * s1
            out[n] += 2 * this
        }
        nextSample = next
        phase = ph
        segment = seg
        frequency = fm.value
        saw8 = g8.value; saw4 = g4.value; saw2 = g2.value; saw1 = g1.value
    }
}

/// wavetable_oscillator.h: WavetableOscillator<128, 15> (approximate_scale, attenuate_high_frequencies).
struct ChordWavetableOscillator {
    var phase: Float = 0, frequency: Float = 0, amplitude: Float = 0, waveform: Float = 0, lp: Float = 0
    var diffLp: Float = 0, diffPrev: Float = 0

    mutating func render(_ f: Float, _ amp: Float, _ wf: Float, _ table: UnsafePointer<Int16>, _ offsets: [Int],
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var freq = f
        constrain(&freq, 0.0000001, kMaxFrequency)
        var a = amp * (1 - 2 * freq)
        a *= 1 / (freq * 131072)
        var fm = PInterp(frequency, freq, size)
        var am = PInterp(amplitude, a, size)
        var wm = PInterp(waveform, wf * Float(15 - 1.0001), size)
        var l = lp, ph = phase
        for n in 0..<size {
            let f0 = fm.next()
            let cutoff = min(128 * f0, 1)
            ph += f0
            if ph >= 1 { ph -= 1 }
            let w = wm.next()
            let wi = trunc32(w)
            let wfr = w - Float(wi)
            let pp = ph * 128
            let pi = trunc32(pp)
            let pf = pp - Float(pi)
            let t0 = table + offsets[wi] + pi, t1 = table + offsets[wi + 1] + pi
            let x0 = Float(t0[0]) + (Float(t0[1]) - Float(t0[0])) * pf
            let x1 = Float(t1[0]) + (Float(t1[1]) - Float(t1[0])) * pf
            let input = (x0 + (x1 - x0) * wfr) * 1
            onePole(&diffLp, input - diffPrev, cutoff)
            diffPrev = input
            onePole(&l, diffLp, cutoff)
            out[n] += am.next() * l
        }
        lp = l
        phase = ph
        frequency = fm.value
        amplitude = am.value
        waveform = wm.value
    }
}

/// 6 — CHORDS: аккорд из 4 нот (+ обращение), делитель частоты или волновые таблицы.
final class ChordEngine: PlaitsEngine {
    static let numNotes = 4, numVoices = 5, numChords = 11
    static let chords: [[Float]] = [
        [0, 0.01, 11.99, 12], [0, 7, 7.01, 12], [0, 5, 7, 12], [0, 3, 7, 12], [0, 3, 7, 10], [0, 3, 10, 14],
        [0, 3, 10, 17], [0, 2, 9, 16], [0, 4, 11, 14], [0, 4, 7, 11], [0, 4, 7, 12],
    ]
    static let fadePoint: [Float] = [0.55, 0.47, 0.49, 0.51, 0.53]
    static let registrations: [[Float]] = [
        [0, 1, 0, 0, 0, 0], [1, 0, 0, 0, 0, 0], [0.5, 0, 0.5, 0, 0, 0], [0.33, 0, 0.33, 0, 0.33, 0],
        [0.33, 0, 0, 0.33, 0, 0.33], [0.5, 0, 0, 0, 0, 0.5], [0, 0.5, 0, 0, 0, 0.5], [0, 0.1, 0.1, 0, 0.2, 0.6],
    ]
    /// Волны wav_integrated_waves (банк, строка, столбец) → смещение (·132).
    static let waves: [Int] = [(2, 6, 1), (2, 6, 6), (2, 6, 4), (0, 6, 0), (0, 6, 1), (0, 6, 2), (0, 6, 7),
                               (2, 4, 7), (2, 4, 6), (2, 4, 5), (2, 4, 4), (2, 4, 3), (2, 4, 2), (2, 4, 1), (2, 4, 0)]
        .map { ($0.0 * 64 + $0.1 * 8 + $0.2) * 132 }

    let lut: PlaitsLUT
    var divideDown = [StringSynthOscillator](repeating: StringSynthOscillator(), count: 5)
    var wavetable = [ChordWavetableOscillator](repeating: ChordWavetableOscillator(), count: 5)
    var quantizer = HysteresisQuantizer2(11, 0.075, symmetric: false)
    var morphLp: Float = 0, timbreLp: Float = 0
    let ratiosTable = plaitsBuffer(44)
    let harmonics = plaitsBuffer(8)
    let ratios = plaitsBuffer(5)
    let amplitudes = plaitsBuffer(5)

    init(_ lut: PlaitsLUT) { self.lut = lut }

    func reset() {
        for i in 0..<Self.numChords {
            for j in 0..<4 { ratiosTable[i * 4 + j] = lut.semitonesToRatio(Self.chords[i][j]) }
        }
    }

    private func inversion(_ inv: Float) -> Int {
        let base = ratiosTable + quantizer.value * 4
        let x = inv * Float(4 * 5)
        let ii = trunc32(x)
        let fr = x - Float(ii)
        let rotations = ii / 4
        let rotated = ii % 4
        let g: Float = 0.25
        var mask = 0
        for i in 0..<4 {
            let transposition = 0.25 * Float(1 << ((4 - 1 + ii - i) / 4))
            let target = (i - rotations + 5) % 5
            let previous = (target - 1 + 5) % 5
            if i == rotated {
                ratios[target] = base[i] * transposition
                ratios[previous] = ratios[target] * 2
                amplitudes[previous] = g * fr
                amplitudes[target] = g * (1 - fr)
            } else if i < rotated {
                ratios[previous] = base[i] * transposition
                amplitudes[previous] = g
            } else {
                ratios[target] = base[i] * transposition
                amplitudes[target] = g
            }
            if i == 0 {
                if i >= rotated { mask |= 1 << target }
                if i <= rotated { mask |= 1 << previous }
            }
        }
        return mask
    }

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        onePole(&morphLp, p.morph, 0.1)
        onePole(&timbreLp, p.timbre, 0.1)
        _ = quantizer.process(p.harmonics * 1.02)
        let reg = max(1 - morphLp * 2.15, 0) * (8 - 1.001)
        let ri = trunc32(reg)
        let rf = reg - Float(ri)
        for i in 0..<6 {
            let a = Self.registrations[ri][i], b = Self.registrations[ri + 1][i]
            harmonics[i] = a + (b - a) * rf
        }
        harmonics[6] = 0
        let auxMask = inversion(timbreLp)
        out.update(repeating: 0, count: size)
        aux.update(repeating: 0, count: size)
        let f0 = lut.noteToFrequency(p.note) * 0.998
        let waveform = max((morphLp - 0.535) * 2.15, 0)
        for note in 0..<5 {
            var wtAmount = 50 * (morphLp - Self.fadePoint[note])
            constrain(&wtAmount, 0, 1)
            var ddAmount = 1 - wtAmount
            let dest = (1 << note) & auxMask != 0 ? aux : out
            let nf = f0 * ratios[note]
            var ddGain = 4 - nf * 32
            constrain(&ddGain, 0, 1)
            ddAmount *= ddGain
            if wtAmount != 0 {
                wavetable[note].render(nf * 1.004, amplitudes[note] * wtAmount, waveform, lut.integratedWaves,
                                       Self.waves, dest, size)
            }
            if ddAmount != 0 {
                divideDown[note].render(nf, harmonics, amplitudes[note] * ddAmount, dest, size)
            }
        }
        for i in 0..<size {
            out[i] += aux[i]
            aux[i] *= 3
        }
    }
}
