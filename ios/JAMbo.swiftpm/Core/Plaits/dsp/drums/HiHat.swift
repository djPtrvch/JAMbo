// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/drums/hi_hat.h. Шаблон HiHat<MetallicNoiseSource, VCA, resonance, two_stage_envelope> —
// один класс с флажками: OUT — SquareNoise, SwingVCA, резонанс; AUX — RingModNoise, LinearVCA, две стадии.

/// Шесть квадратов несоизмеримых частот (808).
struct SquareNoise {
    private var phase0: UInt32 = 0, phase1: UInt32 = 0, phase2: UInt32 = 0
    private var phase3: UInt32 = 0, phase4: UInt32 = 0, phase5: UInt32 = 0

    mutating func initialize() {
        phase0 = 0; phase1 = 0; phase2 = 0; phase3 = 0; phase4 = 0; phase5 = 0
    }

    @inline(__always) private static func increment(_ f0: Float, _ ratio: Float) -> UInt32 {
        var f = f0 * ratio
        if f >= 0.499 { f = 0.499 }
        return stmU32(f * 4294967296.0)
    }

    @inline(__always) mutating func render(_ f0: Float, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let i0 = SquareNoise.increment(f0, 1.0), i1 = SquareNoise.increment(f0, 1.304)
        let i2 = SquareNoise.increment(f0, 1.466), i3 = SquareNoise.increment(f0, 1.787)
        let i4 = SquareNoise.increment(f0, 1.932), i5 = SquareNoise.increment(f0, 2.536)
        for i in 0..<size {
            phase0 &+= i0; phase1 &+= i1; phase2 &+= i2
            phase3 &+= i3; phase4 &+= i4; phase5 &+= i5
            var noise: UInt32 = 0
            noise += phase0 >> 31
            noise += phase1 >> 31
            noise += phase2 >> 31
            noise += phase3 >> 31
            noise += phase4 >> 31
            noise += phase5 >> 31
            out[i] = 0.33 * Float(noise) - 1
        }
    }
}

/// Три пары кольцевой модуляции квадрат × пила (606).
final class RingModNoise {
    private let oscillator: UnsafeMutablePointer<Oscillator>
    private let f = plaitsAllocate(6)

    init() {
        oscillator = .allocate(capacity: 6)
        oscillator.initialize(repeating: Oscillator(), count: 6)
    }

    deinit {
        oscillator.deallocate()
        f.deallocate()
    }

    func initialize() {
        for i in 0..<6 { oscillator[i] = Oscillator() }
    }

    func render(_ f0: Float, _ temp1: UnsafeMutablePointer<Float>, _ temp2: UnsafeMutablePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let ratio = f0 / (0.01 + f0)
        f[0] = 200 / kSampleRate * ratio
        f[1] = 7530 / kSampleRate * ratio
        f[2] = 510 / kSampleRate * ratio
        f[3] = 8075 / kSampleRate * ratio
        f[4] = 730 / kSampleRate * ratio
        f[5] = 10500 / kSampleRate * ratio
        for i in 0..<size { out[i] = 0 }
        for k in 0..<3 {
            oscillator[2 * k].render(.square, f[2 * k], 0.5, temp1, size)
            oscillator[2 * k + 1].render(.saw, f[2 * k + 1], 0.5, temp2, size)
            for i in 0..<size { out[i] += temp1[i] * temp2[i] }
        }
    }
}

final class HiHat {
    private let ringMod: Bool
    private var envelope: Float = 0
    private var noiseClock: Float = 0
    private var noiseSample: Float = 0
    private var sustainGain: Float = 0
    private var squareNoise = SquareNoise()
    private let ringModNoise: RingModNoise
    private var noiseColorationSvf = Svf()
    private var hpf = Svf()

    /// ringMod: false — HiHat<SquareNoise, SwingVCA, true, false>; true — HiHat<RingModNoise, LinearVCA, false, true>.
    init(ringMod: Bool) {
        self.ringMod = ringMod
        ringModNoise = RingModNoise()
        initialize()
    }

    func initialize() {
        envelope = 0
        noiseClock = 0
        noiseSample = 0
        sustainGain = 0
        squareNoise.initialize()
        ringModNoise.initialize()
        noiseColorationSvf.initialize()
        hpf.initialize()
    }

    func render(_ r: PlaitsResources, _ random: StmRandom, _ sustain: Bool, _ trigger: Bool, _ accent: Float,
                _ f0: Float, _ tone: Float, _ decay: Float, _ noisinessIn: Float,
                _ temp1: UnsafeMutablePointer<Float>, _ temp2: UnsafeMutablePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let resonance = !ringMod
        let twoStageEnvelope = ringMod
        let envelopeDecay = 1 - 0.003 * r.semitonesToRatio(-decay * 84)
        let cutDecay = 1 - 0.0025 * r.semitonesToRatio(-decay * 36)

        if trigger {
            envelope = (1.5 + 0.5 * (1 - decay)) * (0.3 + 0.7 * accent)
        }

        // Металлический шум.
        if ringMod {
            ringModNoise.render(2 * f0, temp1, temp2, out, size)
        } else {
            squareNoise.render(2 * f0, out, size)
        }

        // Окраска полосовым фильтром.
        var cutoff = 150 / kSampleRate * r.semitonesToRatio(tone * 72)
        constrain(&cutoff, 0, 16000 / kSampleRate)
        noiseColorationSvf.setFQ(cutoff, resonance ? 3 + 3 * tone : 1, .accurate)
        noiseColorationSvf.process(out, out, size, .bandPass)

        // Подмешивание шума с тактом.
        let noisiness = noisinessIn * noisinessIn
        // Как в plaits.wasm (-ffast-math): (−16·n² + 32)·f0 — при n² ≠ 0,25 даёт другой последний бит,
        // чем f0·(16 + 16·(1 − n²)), и такт шума уходит на отсчёт.
        var noiseF = (noisiness * -16 + 32) * f0
        constrain(&noiseF, 0, 0.5)

        for i in 0..<size {
            noiseClock += noiseF
            if noiseClock >= 1 {
                noiseClock -= 1
                noiseSample = random.getFloat() - 0.5
            }
            out[i] += noisiness * (noiseSample - out[i])
        }

        // VCA.
        var sustainGainMod = ParameterInterpolator(sustainGain, accent * decay, size)
        for i in 0..<size {
            envelope *= envelope > 0.5 || !twoStageEnvelope ? envelopeDecay : cutDecay
            let gain = sustain ? sustainGainMod.next() : envelope
            if ringMod {
                out[i] = out[i] * gain
            } else {
                // SwingVCA.
                var s = out[i]
                s *= s > 0 ? 4 : 0.1
                s = s / (1 + abs(s))
                out[i] = (s + 0.1) * gain
            }
        }
        sustainGain = sustainGainMod.value

        hpf.setFQ(cutoff, 0.5, .accurate)
        hpf.process(out, out, size, .highPass)
        flushDenormal(&envelope)
        noiseColorationSvf.flush()
        hpf.flush()
    }
}

