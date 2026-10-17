// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/physical_modelling/resonator.h, .cc, modal_voice.h, .cc.

let kMaxNumModes = 24
let kModeBatchSize = 4

/// ResonatorSvf<batch_size>: пачка SVF на один вход; состояния — state1[i], state2[i] (указатели владельца).
/// Process<mode, add>: сумма выходов gain[i] · (ФНЧ или полосовой).
@inline(__always)
func resonatorSvfProcess(_ batch: Int, _ state1: UnsafeMutablePointer<Float>, _ state2: UnsafeMutablePointer<Float>,
                         lowPass: Bool, add: Bool,
                         _ f: UnsafePointer<Float>, _ q: UnsafePointer<Float>, _ gain: UnsafePointer<Float>,
                         _ input: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ size: Int,
                         _ scratch: UnsafeMutablePointer<Float>) {
    // scratch: g, r + g, h, s1, s2 — по batch.
    let g = scratch, rPlusG = scratch + batch, h = scratch + 2 * batch
    let s1 = scratch + 3 * batch, s2 = scratch + 4 * batch
    for i in 0..<batch {
        g[i] = filterTan(f[i], .fast)
        let r = 1 / q[i]
        h[i] = 1 / (1 + r * g[i] + g[i] * g[i])
        rPlusG[i] = r + g[i]
        s1[i] = state1[i]
        s2[i] = state2[i]
    }
    for n in 0..<size {
        let sIn = input[n]
        var sOut: Float = 0
        for i in 0..<batch {
            let hp = (sIn - rPlusG[i] * s1[i] - s2[i]) * h[i]
            let bp = g[i] * hp + s1[i]
            s1[i] = g[i] * hp + bp
            let lp = g[i] * bp + s2[i]
            s2[i] = g[i] * bp + lp
            sOut += gain[i] * (lowPass ? lp : bp)
        }
        if add { out[n] += sOut } else { out[n] = sOut }
    }
    for i in 0..<batch {
        state1[i] = s1[i]
        state2[i] = s2[i]
        flushDenormal(&state1[i])
        flushDenormal(&state2[i])
    }
}

/// Модальный резонатор: до 24 мод (пачками по 4), растяжение по STRUCTURE (lut_stiffness).
final class Resonator {
    private let resources: PlaitsResources
    private var resolution = kMaxNumModes
    private let modeAmplitude = plaitsAllocate(kMaxNumModes)
    private let state1 = plaitsAllocate(kMaxNumModes)
    private let state2 = plaitsAllocate(kMaxNumModes)
    private let modeQ = plaitsAllocate(kModeBatchSize)
    private let modeF = plaitsAllocate(kModeBatchSize)
    private let modeA = plaitsAllocate(kModeBatchSize)
    private let scratch = plaitsAllocate(kModeBatchSize * 5)

    init(resources: PlaitsResources) {
        self.resources = resources
    }

    deinit {
        for p in [modeAmplitude, state1, state2, modeQ, modeF, modeA, scratch] { p.deallocate() }
    }

    func initialize(_ position: Float, _ resolutionIn: Int) {
        resolution = min(resolutionIn, kMaxNumModes)
        var amplitudes = CosineOscillator()
        amplitudes.initApproximate(position)
        for i in 0..<resolutionIn { modeAmplitude[i] = amplitudes.next() * 0.25 }
        for i in 0..<kMaxNumModes {
            state1[i] = 0
            state2[i] = 0
        }
    }

    @inline(__always) private static func nthHarmonicCompensation(_ n: Int, _ stiffnessIn: Float) -> Float {
        var stiffness = stiffnessIn
        var stretchFactor: Float = 1
        for _ in 0..<(n - 1) {
            stretchFactor += stiffness
            if stiffness < 0 {
                stiffness *= 0.93
            } else {
                stiffness *= 0.98
            }
        }
        return 1 / stretchFactor
    }

    func process(_ f0In: Float, _ structure: Float, _ brightnessIn: Float, _ damping: Float,
                 _ input: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let r = resources
        var stiffness = stmInterpolate(r.lutStiffness, structure, 64)
        let f0 = f0In * Resonator.nthHarmonicCompensation(3, stiffness)

        var harmonic = f0
        var stretchFactor: Float = 1
        let qSqrt = r.semitonesToRatio(damping * 79.7)
        var q = 500 * qSqrt * qSqrt
        var brightness = brightnessIn
        brightness *= 1 - structure * 0.3
        brightness *= 1 - damping * 0.3
        let qLoss = brightness * (2 - brightness) * 0.85 + 0.15

        var batchCounter = 0
        var batch = 0
        for i in 0..<resolution {
            var modeFrequency = harmonic * stretchFactor
            if modeFrequency >= 0.499 { modeFrequency = 0.499 }
            let modeAttenuation = 1 - modeFrequency * 2

            modeF[batchCounter] = modeFrequency
            modeQ[batchCounter] = 1 + modeFrequency * q
            modeA[batchCounter] = modeAmplitude[i] * modeAttenuation
            batchCounter += 1

            if batchCounter == kModeBatchSize {
                batchCounter = 0
                let base = batch * kModeBatchSize
                resonatorSvfProcess(kModeBatchSize, state1 + base, state2 + base, lowPass: false, add: true,
                                    modeF, modeQ, modeA, input, out, size, scratch)
                batch += 1
            }

            stretchFactor += stiffness
            if stiffness < 0 {
                // Растяжение отрицательное — у мод нижние частоты сближаются.
                stiffness *= 0.93
            } else {
                stiffness *= 0.98
            }
            harmonic += f0
            q *= qLoss
        }
    }
}

/// Модальный голос: возбуждение (импульс по триггеру или Dust при sustain) → ФНЧ → резонатор. AUX — возбуждение.
final class ModalVoice {
    private let resources: PlaitsResources
    private let random: StmRandom
    private let excitationState = plaitsAllocate(2)
    private let scratch = plaitsAllocate(5)
    private let resonator: Resonator

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        resonator = Resonator(resources: resources)
        initialize()
    }

    deinit {
        excitationState.deallocate()
        scratch.deallocate()
    }

    func initialize() {
        excitationState[0] = 0
        excitationState[1] = 0
        resonator.initialize(0.015, kMaxNumModes)
    }

    func render(_ sustain: Bool, _ trigger: Bool, _ accent: Float, _ f0: Float, _ structure: Float,
                _ brightnessIn: Float, _ dampingIn: Float, _ temp: UnsafeMutablePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>, _ size: Int) {
        let r = resources
        var brightness = brightnessIn
        var damping = dampingIn
        let density = brightness * brightness

        brightness += 0.25 * accent * (1 - brightness)
        damping += 0.25 * accent * (1 - damping)

        let range: Float = sustain ? 36 : 60
        let f: Float = sustain ? 4 * f0 : 2 * f0
        var cutoff = min(f * r.semitonesToRatio((brightness * (2 - brightness) - 0.5) * range), 0.499)
        var q: Float = sustain ? 0.7 : 1.5

        // Возбуждение.
        if sustain {
            let dustF = 0.00005 + 0.99995 * density * density
            for i in 0..<size {
                temp[i] = plaitsDust(random, dustF) * (4 - dustF * 3) * accent
            }
        } else {
            for i in 0..<size { temp[i] = 0 }
            if trigger {
                let attenuation = 1 - damping * 0.5
                let amplitude = (0.12 + 0.08 * accent) * attenuation
                temp[0] = amplitude * r.semitonesToRatio(cutoff * cutoff * 24) / cutoff
            }
        }
        var one: Float = 1
        resonatorSvfProcess(1, excitationState, excitationState + 1, lowPass: true, add: false,
                            &cutoff, &q, &one, temp, temp, size, scratch)

        for i in 0..<size { aux[i] += temp[i] }

        resonator.process(f0, structure, brightness, damping, temp, out, size)
    }
}
