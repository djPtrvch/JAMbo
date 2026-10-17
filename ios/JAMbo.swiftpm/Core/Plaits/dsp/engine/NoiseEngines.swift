// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/noise_engine.h, .cc, particle_engine.h, .cc.

/// Движок 9 (NOISE, Filtered noise): шум с тактом (TIMBRE) через SVF ФНЧ → полосовой → ФВЧ (HARMONICS),
/// резонанс — MORPH. AUX — два полосовых фильтра (второй — на HARMONICS полутонов от первого).
final class NoiseEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let random: StmRandom
    private var clockedNoise0 = ClockedNoise()
    private var clockedNoise1 = ClockedNoise()
    private var lpHpFilter = Svf()
    private var bpFilter0 = Svf()
    private var bpFilter1 = Svf()
    private var previousF0: Float = 0
    private var previousF1: Float = 0
    private var previousQ: Float = 0
    private var previousMode: Float = 0
    private let tempBuffer: UnsafeMutablePointer<Float>

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        clockedNoise0.initialize()
        clockedNoise1.initialize()
        lpHpFilter.initialize()
        bpFilter0.initialize()
        bpFilter1.initialize()
        tempBuffer = plaitsAllocate(kMaxBlockSize)
    }

    deinit { tempBuffer.deallocate() }

    func reset() {}

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0Target = r.noteToFrequency(parameters.note)
        let f1Target = r.noteToFrequency(parameters.note + parameters.harmonics * 48 - 24)
        let clockLowestNote: Float = (parameters.trigger & triggerUnpatched) != 0 ? 0 : -24
        let clockF = r.noteToFrequency(parameters.timbre * (128 - clockLowestNote) + clockLowestNote)
        let qTarget = 0.5 * r.semitonesToRatio(parameters.morph * 120)
        let sync = (parameters.trigger & triggerRisingEdge) != 0
        clockedNoise0.render(random, sync, clockF, aux, size)
        clockedNoise1.render(random, sync, clockF * f1Target / f0Target, tempBuffer, size)

        var f0Modulation = ParameterInterpolator(previousF0, f0Target, size)
        var f1Modulation = ParameterInterpolator(previousF1, f1Target, size)
        var qModulation = ParameterInterpolator(previousQ, qTarget, size)
        var modeModulation = ParameterInterpolator(previousMode, parameters.harmonics, size)

        for i in 0..<size {
            let f0 = f0Modulation.next()
            let f1 = f1Modulation.next()
            let q = qModulation.next()
            let gain = 1 / ((0.5 + q) * 40 * f0).squareRoot()
            lpHpFilter.setFQ(f0, q, .accurate)
            bpFilter0.setFQ(f0, q, .accurate)
            bpFilter1.setFQ(f1, q, .accurate)

            var input1 = aux[i] * gain
            let input2 = tempBuffer[i] * gain
            lpHpFilter.processMultimodeLPtoHP(&input1, out + i, 1, modeModulation.next())
            aux[i] = bpFilter0.process(input1, .bandPass) + bpFilter1.process(input2, .bandPass)
        }
        previousF0 = f0Modulation.value
        previousF1 = f1Modulation.value
        previousQ = qModulation.value
        previousMode = modeModulation.value
        lpHpFilter.flush()
        bpFilter0.flush()
        bpFilter1.flush()
    }
}

let kNumParticles = 6

/// Движок 10 (PARTICLE, Particle noise): случайные импульсы через полосовые фильтры, затем ФНЧ и диффузор
/// (MORPH < 0,5 — диффузия, > 0,5 — резонанс). AUX — сырые импульсы.
final class ParticleEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let random: StmRandom
    private let particle: UnsafeMutablePointer<Particle>
    private let diffuser = Diffuser()
    private var postFilter = Svf()

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        particle = .allocate(capacity: kNumParticles)
        particle.initialize(repeating: Particle(), count: kNumParticles)
        for i in 0..<kNumParticles { particle[i].initialize() }
        postFilter.initialize()
    }

    deinit { particle.deallocate() }

    func reset() {
        diffuser.reset()
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0 = r.noteToFrequency(parameters.note)
        let densitySqrt = r.noteToFrequency(60 + parameters.timbre * parameters.timbre * 72)
        let density = densitySqrt * densitySqrt * (1 / Float(kNumParticles))
        let gain = 1 / density
        let qSqrt = r.semitonesToRatio(parameters.morph >= 0.5 ? (parameters.morph - 0.5) * 120 : 0)
        let q = 0.5 + qSqrt * qSqrt
        let spread = 48 * parameters.harmonics * parameters.harmonics
        let rawDiffusionSqrt = 2 * abs(parameters.morph - 0.5)
        let rawDiffusion = rawDiffusionSqrt * rawDiffusionSqrt
        let diffusion: Float = parameters.morph < 0.5 ? rawDiffusion : 0
        let sync = (parameters.trigger & triggerRisingEdge) != 0

        for i in 0..<size {
            out[i] = 0
            aux[i] = 0
        }

        for i in 0..<kNumParticles {
            particle[i].render(r, random, sync, density, gain, f0, spread, q, out, aux, size)
        }

        postFilter.setFQ(min(f0, 0.49), 0.5, .dirty)
        postFilter.process(out, out, size, .lowPass)
        postFilter.flush()

        diffuser.process(0.8 * diffusion * diffusion, 0.5 * diffusion + 0.25, out, size)
    }
}
