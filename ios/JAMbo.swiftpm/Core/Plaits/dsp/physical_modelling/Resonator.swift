// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/physical_modelling/resonator.h, .cc, modal_voice.h, .cc.

let kMaxNumModes = 24
let kModeBatchSize = 4

/// ResonatorSvf<4>, Process<BAND_PASS, add = true>: пачка из 4 SVF на один вход, out += Σ gain[i] · полосовой.
/// Состояния — state1[0…3], state2[0…3]. Развёрнуто на отдельные переменные, циклы — while: в отладочной сборке
/// (Playgrounds) цикл for по модам на каждый отсчёт — вызовы итератора, MODAL перегружал процессор.
@inline(__always)
func resonatorSvf4BandPassAdd(_ state1: UnsafeMutablePointer<Float>, _ state2: UnsafeMutablePointer<Float>,
                              _ f: UnsafePointer<Float>, _ q: UnsafePointer<Float>, _ gain: UnsafePointer<Float>,
                              _ input: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
    let g0 = filterTan(f[0], .fast), g1 = filterTan(f[1], .fast), g2 = filterTan(f[2], .fast), g3 = filterTan(f[3], .fast)
    let r0 = 1 / q[0], r1 = 1 / q[1], r2 = 1 / q[2], r3 = 1 / q[3]
    let h0 = 1 / (1 + r0 * g0 + g0 * g0), h1 = 1 / (1 + r1 * g1 + g1 * g1)
    let h2 = 1 / (1 + r2 * g2 + g2 * g2), h3 = 1 / (1 + r3 * g3 + g3 * g3)
    let rg0 = r0 + g0, rg1 = r1 + g1, rg2 = r2 + g2, rg3 = r3 + g3
    let a0 = gain[0], a1 = gain[1], a2 = gain[2], a3 = gain[3]
    var s10 = state1[0], s11 = state1[1], s12 = state1[2], s13 = state1[3]
    var s20 = state2[0], s21 = state2[1], s22 = state2[2], s23 = state2[3]
    var n = 0
    while n < size {
        let x = input[n]
        let hp0 = (x - rg0 * s10 - s20) * h0
        let bp0 = g0 * hp0 + s10
        s10 = g0 * hp0 + bp0
        s20 = g0 * bp0 + (g0 * bp0 + s20)
        let hp1 = (x - rg1 * s11 - s21) * h1
        let bp1 = g1 * hp1 + s11
        s11 = g1 * hp1 + bp1
        s21 = g1 * bp1 + (g1 * bp1 + s21)
        let hp2 = (x - rg2 * s12 - s22) * h2
        let bp2 = g2 * hp2 + s12
        s12 = g2 * hp2 + bp2
        s22 = g2 * bp2 + (g2 * bp2 + s22)
        let hp3 = (x - rg3 * s13 - s23) * h3
        let bp3 = g3 * hp3 + s13
        s13 = g3 * hp3 + bp3
        s23 = g3 * bp3 + (g3 * bp3 + s23)
        out[n] += (((0 + a0 * bp0) + a1 * bp1) + a2 * bp2) + a3 * bp3
        n += 1
    }
    flushDenormal(&s10); flushDenormal(&s11); flushDenormal(&s12); flushDenormal(&s13)
    flushDenormal(&s20); flushDenormal(&s21); flushDenormal(&s22); flushDenormal(&s23)
    state1[0] = s10; state1[1] = s11; state1[2] = s12; state1[3] = s13
    state2[0] = s20; state2[1] = s21; state2[2] = s22; state2[3] = s23
}

/// ResonatorSvf<1>, Process<LOW_PASS, add = false>: возбуждение ModalVoice (in и out могут совпадать).
@inline(__always)
func resonatorSvf1LowPass(_ state: UnsafeMutablePointer<Float>, _ f: Float, _ q: Float,
                          _ input: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
    let g = filterTan(f, .fast)
    let r = 1 / q
    let h = 1 / (1 + r * g + g * g)
    let rg = r + g
    var s1 = state[0], s2 = state[1]
    var n = 0
    while n < size {
        let hp = (input[n] - rg * s1 - s2) * h
        let bp = g * hp + s1
        s1 = g * hp + bp
        let lp = g * bp + s2
        s2 = g * bp + lp
        out[n] = lp
        n += 1
    }
    flushDenormal(&s1)
    flushDenormal(&s2)
    state[0] = s1
    state[1] = s2
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

    init(resources: PlaitsResources) {
        self.resources = resources
    }

    deinit {
        for p in [modeAmplitude, state1, state2, modeQ, modeF, modeA] { p.deallocate() }
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
                resonatorSvf4BandPassAdd(state1 + base, state2 + base, modeF, modeQ, modeA, input, out, size)
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
    private let resonator: Resonator

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        resonator = Resonator(resources: resources)
        initialize()
    }

    deinit {
        excitationState.deallocate()
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
        let cutoff = min(f * r.semitonesToRatio((brightness * (2 - brightness) - 0.5) * range), 0.499)
        let q: Float = sustain ? 0.7 : 1.5

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
        resonatorSvf1LowPass(excitationState, cutoff, q, temp, temp, size)

        for i in 0..<size { aux[i] += temp[i] }

        resonator.process(f0, structure, brightness, damping, temp, out, size)
    }
}
