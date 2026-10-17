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

        // Без вызовов на каждом отсчёте: интерполяторы, Svf.setFQ(.accurate) (у ФНЧ/ФВЧ и первого полосового — одни
        // и те же f0 и q, коэффициенты считаются один раз) и шаги фильтров развёрнуты в том же порядке операций —
        // в отладочной сборке (Playgrounds) вызовы дороже арифметики.
        let piF = Float.pi
        let accA = FilterK.accA, accB = FilterK.accB, accC = FilterK.accC, accD = FilterK.accD, accE = FilterK.accE
        var vF0 = f0Modulation.value, vF1 = f1Modulation.value, vQ = qModulation.value, vMode = modeModulation.value
        let iF0 = f0Modulation.increment, iF1 = f1Modulation.increment
        let iQ = qModulation.increment, iMode = modeModulation.increment
        var m1 = lpHpFilter.state1, m2 = lpHpFilter.state2
        var p1 = bpFilter0.state1, p2 = bpFilter0.state2
        var q1 = bpFilter1.state1, q2 = bpFilter1.state2
        var g0: Float = 0, g1: Float = 0, rr: Float = 0, h0: Float = 0, h1: Float = 0
        var i = 0
        while i < size {
            vF0 += iF0
            vF1 += iF1
            vQ += iQ
            let f0 = vF0, f1 = vF1, q = vQ
            let gain = 1 / ((0.5 + q) * 40 * f0).squareRoot()
            // tan<FREQUENCY_ACCURATE>(f): f · (π + f²(a + f²(b + f²(c + f²(d + f²·e))))).
            let f0s = f0 * f0
            g0 = f0 * (piF + f0s * (accA + f0s * (accB + f0s * (accC + f0s * (accD + f0s * accE)))))
            let f1s = f1 * f1
            g1 = f1 * (piF + f1s * (accA + f1s * (accB + f1s * (accC + f1s * (accD + f1s * accE)))))
            rr = 1 / q
            h0 = 1 / (1 + rr * g0 + g0 * g0)
            h1 = 1 / (1 + rr * g1 + g1 * g1)

            let input1 = aux[i] * gain
            let input2 = tempBuffer[i] * gain
            // ProcessMultimodeLPtoHP.
            vMode += iMode
            let mode = vMode
            let hx = -mode * 2 + 1
            let hpGain: Float = 0 < hx ? 0 : hx
            let dm = mode - 0.5
            let bpGain = 1 - 2 * (dm < 0 ? -dm : dm)
            let lx = 1 - mode * 2
            let lpGain: Float = 0 >= lx ? 0 : lx
            let mhp = (input1 - rr * m1 - g0 * m1 - m2) * h0
            let mbp = g0 * mhp + m1
            m1 = g0 * mhp + mbp
            let mlp = g0 * mbp + m2
            m2 = g0 * mbp + mlp
            out[i] = hpGain * mhp + bpGain * mbp + lpGain * mlp
            // Два полосовых.
            let php = (input1 - rr * p1 - g0 * p1 - p2) * h0
            let pbp = g0 * php + p1
            p1 = g0 * php + pbp
            let plp = g0 * pbp + p2
            p2 = g0 * pbp + plp
            let qhp = (input2 - rr * q1 - g1 * q1 - q2) * h1
            let qbp = g1 * qhp + q1
            q1 = g1 * qhp + qbp
            let qlp = g1 * qbp + q2
            q2 = g1 * qbp + qlp
            aux[i] = pbp + qbp
            i += 1
        }
        f0Modulation.value = vF0
        f1Modulation.value = vF1
        qModulation.value = vQ
        modeModulation.value = vMode
        lpHpFilter.state1 = m1
        lpHpFilter.state2 = m2
        bpFilter0.state1 = p1
        bpFilter0.state2 = p2
        bpFilter1.state1 = q1
        bpFilter1.state2 = q2
        if size > 0 {
            // Коэффициенты — как после последнего setFQ (Svf хранит их).
            lpHpFilter.setGR(g0, rr)
            bpFilter0.setGR(g0, rr)
            bpFilter1.setGR(g1, rr)
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
