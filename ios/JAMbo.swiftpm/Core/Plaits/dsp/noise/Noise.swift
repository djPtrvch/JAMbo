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
        // Генератор шума и фильтр — в локальных переменных на время блока (в отладочной сборке вызов метода класса
        // на каждый отсчёт дорог); последовательность та же, что у StmRandom.getFloat.
        var state = random.state
        @inline(__always) func next() -> Float {
            state = state &* 1664525 &+ 1013904223
            return Float(state) / 4294967296.0
        }
        var filter = self.filter
        var preGain = self.preGain
        var u = next()
        if sync { u = density }
        var canRandomizeFrequency = true
        var i = 0
        while i < size {
            var s: Float = 0
            if u <= density {
                s = u * gain
                if canRandomizeFrequency {
                    let v = 2 * next() - 1
                    let f = min(r.semitonesToRatio(spread * v) * frequency, 0.25)
                    preGain = 0.5 / (q * f * density.squareRoot()).squareRoot()
                    filter.setFQ(f, q, .dirty)
                    // Частота среза — одна на весь блок.
                    canRandomizeFrequency = false
                }
            }
            aux[i] += s
            // Svf, полосовой (process(…, .bandPass) без вызова метода).
            let x = preGain * s
            let hp = (x - filter.r * filter.state1 - filter.g * filter.state1 - filter.state2) * filter.h
            let bp = filter.g * hp + filter.state1
            filter.state1 = filter.g * hp + bp
            let lp = filter.g * bp + filter.state2
            filter.state2 = filter.g * bp + lp
            out[i] += bp
            u = next()
            i += 1
        }
        random.state = state
        self.filter = filter
        self.preGain = preGain
        filter.flush()
    }
}
