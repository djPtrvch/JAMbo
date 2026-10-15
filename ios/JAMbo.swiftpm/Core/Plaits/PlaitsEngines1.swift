// Перенос движков Plaits 0–4 (Copyright Emilie Gillet, MIT): virtual_analog_engine (VA_VARIANT 2),
// waveshaping_engine, fm_engine, grain_engine, additive_engine.

/// 0 — VA: две пары осцилляторов (variable square + variable saw, на AUX — «monster sync»).
final class VirtualAnalogEngine: PlaitsEngine {
    let lut: PlaitsLUT
    var primary = VariableShapeOscillator()
    var auxiliary = VariableShapeOscillator()
    var sync = VariableShapeOscillator()
    var variableSaw = VariableSawOscillator()
    var auxiliaryAmount: Float = 0, xmodAmount: Float = 0
    let temp = plaitsBuffer(kMaxBlockSize)
    private static let intervals: [Float] = [0, 7.01, 12.01, 19.01, 24.01]

    init(_ lut: PlaitsLUT) {
        self.lut = lut
        auxiliary.masterPhase = 0.25
    }
    func reset() {}

    private func detuning(_ d: Float) -> Float {
        var detune = 2.05 * d - 1.025
        constrain(&detune, -1, 1)
        let sign: Float = detune < 0 ? -1 : 1
        detune = detune * sign * 3.9999
        let i = trunc32(detune)
        let fr = detune - Float(i)
        let a = Self.intervals[i], b = Self.intervals[i + 1]
        return (a + (b - a) * smoothStep(smoothStep(fr))) * sign
    }

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        let syncAmount = p.timbre * p.timbre
        let auxDetune = detuning(p.harmonics)
        let primaryF = lut.noteToFrequency(p.note)
        let auxiliaryF = lut.noteToFrequency(p.note + auxDetune)
        let primarySyncF = lut.noteToFrequency(p.note + syncAmount * 48)
        let auxiliarySyncF = lut.noteToFrequency(p.note + auxDetune + syncAmount * 48)
        var shape = p.morph * 1.5
        constrain(&shape, 0, 1)
        var pw = 0.5 + (p.morph - 0.66) * 1.46
        constrain(&pw, 0.5, 0.995)
        primary.render(primaryF, primarySyncF, pw, shape, out, size)
        auxiliary.render(auxiliaryF, auxiliarySyncF, pw, shape, aux, size)
        for i in 0..<size { aux[i] = (aux[i] - out[i]) * 0.5 }

        var squarePw = 1.3 * p.timbre - 0.15
        constrain(&squarePw, 0.005, 0.5)
        let squareSyncRatio: Float = p.timbre < 0.5 ? 0 : (p.timbre - 0.5) * (p.timbre - 0.5) * 4 * 48
        let squareGain = min(p.timbre * 8, 1)
        var sawPw = p.morph < 0.5 ? p.morph + 0.5 : 1 - (p.morph - 0.5) * 2
        sawPw *= 1.1
        constrain(&sawPw, 0.005, 1)
        var sawShape = 10 - 21 * p.morph
        constrain(&sawShape, 0, 1)
        var sawGain = 8 * (1 - p.morph)
        constrain(&sawGain, 0.02, 1)
        let squareSyncF = lut.noteToFrequency(p.note + squareSyncRatio)
        sync.render(primaryF, squareSyncF, squarePw, 1, temp, size)
        variableSaw.render(auxiliaryF, sawPw, sawShape, out, size)
        let norm = 1 / max(squareGain, sawGain)
        var sq = PInterp(auxiliaryAmount, squareGain * 0.3 * norm, size)
        var sw = PInterp(xmodAmount, sawGain * 0.5 * norm, size)
        for i in 0..<size {
            out[i] = out[i] * sw.next() + sq.next() * temp[i]
        }
        auxiliaryAmount = sq.value
        xmodAmount = sw.value
    }
}

/// 1 — WAVESHAPE.
final class WaveshapingEngine: PlaitsEngine {
    let lut: PlaitsLUT
    var slope = PlaitsOscillator()
    var triangle = PlaitsOscillator()
    var previousShape: Float = 0, previousWavefolderGain: Float = 0, previousOvertoneGain: Float = 0

    init(_ lut: PlaitsLUT) { self.lut = lut }
    func reset() {}

    private func tame(_ f: Float, _ harmonics: Float, _ order: Float) -> Float {
        let f0 = f * harmonics
        let maxF = 0.5 / order
        var a = 1 - (f0 - maxF) / (0.5 - maxF)
        constrain(&a, 0, 1)
        return a * a * a
    }

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        let f0 = lut.noteToFrequency(p.note)
        let pw = p.morph * 0.45 + 0.5
        slope.render(.slope, f0, pw, out, size)
        triangle.render(.slope, f0, 0.5, aux, size)
        let slopeK = 3 + abs(p.morph - 0.5) * 5
        let shapeAmount = abs(p.harmonics - 0.5) * 2
        let shapeAtt = tame(f0, slopeK, 16)
        let wfGain = p.timbre
        let wfAtt = tame(f0, slopeK * (3 + shapeAmount * shapeAtt * 5), 12)
        var shapeMod = PInterp(previousShape, 0.5 + (p.harmonics - 0.5) * shapeAtt, size)
        var wfMod = PInterp(previousWavefolderGain, 0.03 + 0.46 * wfGain * wfAtt, size)
        let og = p.timbre * (2 - p.timbre)
        var ogMod = PInterp(previousOvertoneGain, og * (2 - og), size)
        let fold1 = lut.fold + 1, fold2 = lut.fold2 + 1
        for i in 0..<size {
            let shape = shapeMod.next() * 3.9999
            let si = trunc32(shape)
            let sf = shape - Float(si)
            let s1 = lut.wsTable[si], s2 = lut.wsTable[si + 1]
            let wsIndex = 127 * out[i] + 128
            var wi = trunc32(wsIndex)
            let wf = wsIndex - Float(wi)
            wi &= 255
            let x0 = Float(s1[wi]) / 32768, x1 = Float(s1[wi + 1]) / 32768
            let x = x0 + (x1 - x0) * wf
            let y0 = Float(s2[wi]) / 32768, y1 = Float(s2[wi + 1]) / 32768
            let y = y0 + (y1 - y0) * wf
            let mix = x + (y - x) * sf
            let index = mix * wfMod.next() + 0.5
            let fold = interpolateHermite(fold1, index, 512)
            let f2 = -interpolateHermite(fold2, index, 512)
            let sine = lut.sin(aux[i] * 0.25 + 0.5)
            out[i] = fold
            aux[i] = sine + (f2 - sine) * ogMod.next()
        }
        previousShape = shapeMod.value
        previousWavefolderGain = wfMod.value
        previousOvertoneGain = ogMod.value
    }
}

/// 2 — FM (два оператора, 4× передискретизация).
final class FMEngine: PlaitsEngine {
    let lut: PlaitsLUT
    var carrierPhase: UInt32 = 0, modulatorPhase: UInt32 = 0, subPhase: UInt32 = 0
    var previousCarrierFrequency = plaitsA0, previousModulatorFrequency = plaitsA0
    var previousAmount: Float = 0, previousFeedback: Float = 0, previousSample: Float = 0
    var subFir: Float = 0, carrierFir: Float = 0

    init(_ lut: PlaitsLUT) { self.lut = lut }
    func reset() {}

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        let note = p.note - 24
        let ratio = interpolate(lut.fmQuantizer, p.harmonics, 128)
        let modNote = note + ratio
        var targetMod = lut.noteToFrequency(modNote)
        constrain(&targetMod, 0, 0.5)
        var taming = 1 - (modNote - 72) * 0.025
        constrain(&taming, 0, 1)
        taming *= taming
        var cf = PInterp(previousCarrierFrequency, lut.noteToFrequency(note), size)
        var mf = PInterp(previousModulatorFrequency, targetMod, size)
        var am = PInterp(previousAmount, 2 * p.timbre * p.timbre * taming, size)
        var fb = PInterp(previousFeedback, 2 * p.morph - 1, size)
        var cd = Downsampler4x(carrierFir, lut.fir4x)
        var sd = Downsampler4x(subFir, lut.fir4x)
        let maxU: Float = 4294967296.0
        for n in 0..<size {
            let amount = am.next()
            let feedback = fb.next()
            let phaseFeedback: Float = feedback < 0 ? 0.5 * feedback * feedback : 0
            let carrierInc = u32(maxU * cf.next())
            let modF = mf.next()
            for j in 0..<4 {
                modulatorPhase &+= u32(maxU * modF * (1 + previousSample * phaseFeedback))
                carrierPhase &+= carrierInc
                subPhase &+= carrierInc >> 1
                let modFb: Float = feedback > 0 ? 0.25 * feedback * feedback : 0
                let modulator = lut.sinePM(modulatorPhase, modFb * previousSample)
                let carrier = lut.sinePM(carrierPhase, amount * modulator)
                let sub = lut.sinePM(subPhase, amount * carrier * 0.25)
                onePole(&previousSample, carrier, 0.05)
                cd.accumulate(j, carrier)
                sd.accumulate(j, sub)
            }
            out[n] = cd.read()
            aux[n] = sd.read()
        }
        carrierFir = cd.head
        subFir = sd.head
        previousCarrierFrequency = cf.value
        previousModulatorFrequency = mf.value
        previousAmount = am.value
        previousFeedback = fb.value
    }
}

/// 3 — GRAIN (гранулярная форманта, на AUX — Z-осциллятор).
final class GrainEngine: PlaitsEngine {
    let lut: PlaitsLUT
    var grainlet0 = GrainletOscillator(), grainlet1 = GrainletOscillator()
    var zOsc = ZOscillator()
    var dc0 = OnePoleF(), dc1 = OnePoleF()

    init(_ lut: PlaitsLUT) {
        self.lut = lut
        dc0.initialize()
        dc1.initialize()
    }
    func reset() {}

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        let root = p.note
        let f0 = lut.noteToFrequency(root)
        let f1 = lut.noteToFrequency(24 + 84 * p.timbre)
        let ratio = lut.semitonesToRatio(-24 + 48 * p.harmonics)
        let bleed: Float = p.harmonics < 0.5 ? 1 - 2 * p.harmonics : 0
        let bleedFixed = bleed * (2 - bleed)
        let shape = 0.33 + (p.morph - 0.33) * max(1 - f0 * 24, 0)
        grainlet0.render(f0, f1, shape, bleedFixed, out, size, lut)
        grainlet1.render(f0, f1 * ratio, shape, bleedFixed, aux, size, lut)
        dc0.setF(0.3 * f0, .dirty)
        for i in 0..<size { out[i] = dc0.hp(out[i] + aux[i]) }
        let cutoff = lut.noteToFrequency(root + 96 * p.timbre)
        zOsc.render(f0, cutoff, p.morph, p.harmonics, aux, size, lut)
        dc1.setF(0.3 * f0, .dirty)
        for i in 0..<size { aux[i] = dc1.hp(aux[i]) }
    }
}

/// 4 — ADDITIVE (24 гармоники на OUT, 8 «органных» на AUX).
final class AdditiveEngine: PlaitsEngine {
    let lut: PlaitsLUT
    let osc = [HarmonicOscillator(), HarmonicOscillator(), HarmonicOscillator()]
    let amplitudes = plaitsBuffer(36)
    private static let integer: [Int] = Array(0..<24)
    private static let organ: [Int] = [0, 1, 2, 3, 5, 7, 9, 11]

    init(_ lut: PlaitsLUT) { self.lut = lut }
    func reset() { amplitudes.update(repeating: 0, count: 36) }

    private func update(_ centroid: Float, _ slope: Float, _ bumps: Float, _ amps: UnsafeMutablePointer<Float>, _ idx: [Int]) {
        let n = Float(idx.count) - 1
        let margin = (1 / slope - 1) / (1 + bumps)
        let center = centroid * (n + margin) - 0.5 * margin
        var sum: Float = 0.001
        for i in 0..<idx.count {
            let order = abs(Float(i) - center) * slope
            var gain = 1 - order
            gain += abs(gain)
            gain *= gain
            let b = 0.25 + order * bumps
            gain *= 1 + lut.sin(b)
            gain *= gain
            gain *= gain
            onePole(&amps[idx[i]], gain, 0.001)
            sum += amps[idx[i]]
        }
        sum = 1 / sum
        for i in 0..<idx.count { amps[idx[i]] *= sum }
    }

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        let f0 = lut.noteToFrequency(p.note)
        let centroid = p.timbre
        let rawBumps = p.harmonics
        let rawSlope = (1 - 0.6 * rawBumps) * p.morph
        let slope = 0.01 + 1.99 * rawSlope * rawSlope * rawSlope
        let bumps = 16 * rawBumps * rawBumps
        update(centroid, slope, bumps, amplitudes, Self.integer)
        osc[0].render(first: 1, f0, amplitudes, out, size, lut)
        osc[1].render(first: 13, f0, amplitudes + 12, out, size, lut)
        update(centroid, slope, bumps, amplitudes + 24, Self.organ)
        osc[2].render(first: 1, f0, amplitudes + 24, aux, size, lut)
    }
}
