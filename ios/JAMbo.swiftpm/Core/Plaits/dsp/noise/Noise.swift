// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/noise/dust.h, clocked_noise.h, particle.h.

/// Dust: редкие случайные импульсы (вероятность frequency на отсчёт).
@inline(__always) func plaitsDust(_ random: StmRandom, _ frequency: Float) -> Float {
    let invFrequency = 1 / frequency
    let u = random.getFloat()
    return u < frequency ? u * invFrequency : 0
}

/// ClockedNoise: шум с тактом (sample & hold с polyBLEP); выше четверти частоты дискретизации — сырой шум.
struct ClockedNoise {
    private var phase: Float = 0
    private var sample: Float = 0
    private var nextSample: Float = 0
    private var frequency: Float = 0.001

    mutating func initialize() {
        phase = 0
        sample = 0
        nextSample = 0
        frequency = 0.001
    }

    @inline(__always) mutating func render(_ random: StmRandom, _ sync: Bool, _ frequencyIn: Float,
                                           _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var target = frequencyIn
        constrain(&target, 0, 1)
        var fm = ParameterInterpolator(frequency, target, size)
        var nextSample = self.nextSample
        var sample = self.sample
        if sync { phase = 1 }
        for i in 0..<size {
            var thisSample = nextSample
            nextSample = 0
            let f = fm.next()
            let rawSample = random.getFloat() * 2 - 1
            var rawAmount = 4 * (f - 0.25)
            constrain(&rawAmount, 0, 1)
            phase += f
            if phase >= 1 {
                phase -= 1
                let t = phase / f
                let newSample = rawSample
                let discontinuity = newSample - sample
                thisSample += discontinuity * thisBlepSample(t)
                nextSample += discontinuity * nextBlepSample(t)
                sample = newSample
            }
            nextSample += sample
            out[i] = thisSample + rawAmount * (rawSample - thisSample)
        }
        self.nextSample = nextSample
        self.sample = sample
        frequency = fm.value
    }
}

/// Particle: случайные импульсы через полосовой фильтр со случайной частотой (одна на блок).
struct Particle {
    private var preGain: Float = 0
    private var filter = Svf()

    mutating func initialize() {
        preGain = 0
        filter.initialize()
    }

    @inline(__always) mutating func render(_ r: PlaitsResources, _ random: StmRandom, _ sync: Bool, _ density: Float,
                                           _ gain: Float, _ frequency: Float, _ spread: Float, _ q: Float,
                                           _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                                           _ size: Int) {
        var u = random.getFloat()
        if sync { u = density }
        var canRandomizeFrequency = true
        for i in 0..<size {
            var s: Float = 0
            if u <= density {
                s = u * gain
                if canRandomizeFrequency {
                    let v = 2 * random.getFloat() - 1
                    let f = min(r.semitonesToRatio(spread * v) * frequency, 0.25)
                    preGain = 0.5 / (q * f * density.squareRoot()).squareRoot()
                    filter.setFQ(f, q, .dirty)
                    // Частота среза — одна на весь блок.
                    canRandomizeFrequency = false
                }
            }
            aux[i] += s
            out[i] += filter.process(preGain * s, .bandPass)
            u = random.getFloat()
        }
    }
}
