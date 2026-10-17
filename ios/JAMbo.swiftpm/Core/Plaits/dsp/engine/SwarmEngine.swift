// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/swarm_engine.h, .cc.

let kNumSwarmVoices = 8

/// Огибающая зерна: случайные интервалы частоты и длительности.
struct GrainEnvelope {
    private var from: Float = 0
    private var interval: Float = 1
    private var phase: Float = 1
    private var fm: Float = 0
    private var amplitude: Float = 0.5
    private var previousSizeRatio: Float = 0
    private var filterCoefficient: Float = 0

    mutating func initialize() {
        from = 0
        interval = 1
        phase = 1
        fm = 0
        amplitude = 0.5
        previousSizeRatio = 0
        filterCoefficient = 0
    }

    @inline(__always) mutating func step(_ random: StmRandom, _ rate: Float, _ burstMode: Bool, _ startBurst: Bool) {
        var randomize = false
        if startBurst {
            phase = 0.5
            fm = 16
            randomize = true
        } else {
            phase += rate * fm
            if phase >= 1 {
                phase -= Float(stmInt(phase))
                randomize = true
            }
        }

        if randomize {
            from += interval
            interval = random.getFloat() - from
            // Случайная длительность зерна.
            if burstMode {
                fm *= 0.8 + 0.2 * random.getFloat()
            } else {
                fm = 0.5 + 1.5 * random.getFloat()
            }
        }
    }

    /// Два перекрывающихся зерна частот f1 и f2 — как тон, скользящий от f1 к f2: непрерывный переход
    /// между «облаком зёрен» и «роем глиссандо».
    @inline(__always) func frequency(_ sizeRatio: Float) -> Float {
        sizeRatio < 1 ? 2 * (from + interval * phase) - 1 : from
    }

    @inline(__always) mutating func amplitude(_ r: PlaitsResources, _ sizeRatio: Float) -> Float {
        var targetAmplitude: Float = 1
        if sizeRatio >= 1 {
            var p = (phase - 0.5) * sizeRatio
            constrain(&p, -1, 1)
            let e = r.sine(0.5 * p + 1.25)
            targetAmplitude = 0.5 * (e + 1)
        }

        if (sizeRatio >= 1) != (previousSizeRatio >= 1) {
            filterCoefficient = 0.5
        }
        filterCoefficient *= 0.95

        previousSizeRatio = sizeRatio
        onePole(&amplitude, targetAmplitude, 0.5 - filterCoefficient)
        return amplitude
    }
}

/// Пила polyBLEP, прибавляется к out.
struct AdditiveSawOscillator {
    private var phase: Float = 0
    private var nextSample: Float = 0
    private var frequency: Float = 0.01
    private var gain: Float = 0

    mutating func initialize() {
        phase = 0
        nextSample = 0
        frequency = 0.01
        gain = 0
    }

    @inline(__always) mutating func render(_ frequencyIn: Float, _ level: Float,
                                           _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let target = frequencyIn >= kMaxFrequency ? kMaxFrequency : frequencyIn
        var fm = ParameterInterpolator(frequency, target, size)
        var gainMod = ParameterInterpolator(gain, level, size)

        var nextSample = self.nextSample
        var phase = self.phase

        for i in 0..<size {
            var thisSample = nextSample
            nextSample = 0

            let f = fm.next()

            phase += f

            if phase >= 1 {
                phase -= 1
                let t = phase / f
                thisSample -= thisBlepSample(t)
                nextSample -= nextBlepSample(t)
            }

            nextSample += phase
            out[i] += (2 * thisSample - 1) * gainMod.next()
        }
        self.phase = phase
        self.nextSample = nextSample
        frequency = fm.value
        gain = gainMod.value
    }
}

struct SwarmVoice {
    private var rank: Float = 0
    private var envelope = GrainEnvelope()
    private var saw = AdditiveSawOscillator()
    private var sine = FastSineOscillator()

    mutating func initialize(_ rank: Float) {
        self.rank = rank
        envelope.initialize()
        saw.initialize()
        sine.initialize()
    }

    @inline(__always) mutating func render(_ r: PlaitsResources, _ random: StmRandom, _ f0In: Float, _ density: Float,
                                           _ burstMode: Bool, _ startBurst: Bool, _ spread: Float, _ sizeRatio: Float,
                                           _ sawOut: UnsafeMutablePointer<Float>, _ sineOut: UnsafeMutablePointer<Float>,
                                           _ size: Int) {
        envelope.step(random, density, burstMode, startBurst)

        let scale = 1 / Float(kNumSwarmVoices)
        let amplitude = envelope.amplitude(r, sizeRatio) * scale

        let expoAmount = envelope.frequency(sizeRatio)
        var f0 = f0In * r.semitonesToRatio(48 * expoAmount * spread * rank)

        let linearAmount = rank * (rank + 0.01) * spread * 0.25
        f0 *= 1 + linearAmount

        saw.render(f0, amplitude, sawOut, size)
        sine.render(f0, amplitude, sineOut, size)
    }
}

/// Движок 8 (SWARM, Granular cloud): 8 пил (OUT) и синусов (AUX) с зёрнами частоты; HARMONICS — разброс,
/// TIMBRE — плотность, MORPH — длина зерна.
final class SwarmEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let random: StmRandom
    private let swarmVoice: UnsafeMutablePointer<SwarmVoice>

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        swarmVoice = .allocate(capacity: kNumSwarmVoices)
        swarmVoice.initialize(repeating: SwarmVoice(), count: kNumSwarmVoices)
    }

    deinit { swarmVoice.deallocate() }

    func reset() {
        let n = Float((kNumSwarmVoices - 1) / 2)
        for i in 0..<kNumSwarmVoices {
            let rank = (Float(i) - n) / n
            swarmVoice[i].initialize(rank)
        }
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0 = r.noteToFrequency(parameters.note)
        let controlRate = Float(size)
        let density = r.noteToFrequency(parameters.timbre * 120) * 0.025 * controlRate
        let spread = parameters.harmonics * parameters.harmonics * parameters.harmonics
        var sizeRatio = 0.25 * r.semitonesToRatio((1 - parameters.morph) * 84)

        let burstMode = (parameters.trigger & triggerUnpatched) == 0
        let startBurst = (parameters.trigger & triggerRisingEdge) != 0

        for i in 0..<size {
            out[i] = 0
            aux[i] = 0
        }

        for i in 0..<kNumSwarmVoices {
            swarmVoice[i].render(r, random, f0, density, burstMode, startBurst, spread, sizeRatio, out, aux, size)
            sizeRatio *= 0.97
        }
    }
}
