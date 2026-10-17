// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/drums/analog_snare_drum.h, synthetic_snare_drum.h.

private let kSnareNumModes = 5

/// Малый барабан 808: 5 мод корпуса (резонаторы или синусы при sustain) + шум через полосовой фильтр.
final class AnalogSnareDrum {
    private var pulseRemainingSamples = 0
    private var pulse: Float = 0
    private var pulseHeight: Float = 0
    private var pulseLp: Float = 0
    private var noiseEnvelope: Float = 0
    private var sustainGain: Float = 0
    private let resonator: UnsafeMutablePointer<Svf>
    private var noiseFilter = Svf()
    private let oscillator: UnsafeMutablePointer<SineOscillator>
    private let modeFrequencies = plaitsAllocate(kSnareNumModes)
    private let f = plaitsAllocate(kSnareNumModes)
    private let gain = plaitsAllocate(kSnareNumModes)

    init() {
        resonator = .allocate(capacity: kSnareNumModes)
        resonator.initialize(repeating: Svf(), count: kSnareNumModes)
        oscillator = .allocate(capacity: kSnareNumModes)
        oscillator.initialize(repeating: SineOscillator(), count: kSnareNumModes)
        modeFrequencies[0] = 1.00
        modeFrequencies[1] = 2.00
        modeFrequencies[2] = 3.18
        modeFrequencies[3] = 4.16
        modeFrequencies[4] = 5.62
        initialize()
    }

    deinit {
        resonator.deallocate()
        oscillator.deallocate()
        modeFrequencies.deallocate()
        f.deallocate()
        gain.deallocate()
    }

    func initialize() {
        pulseRemainingSamples = 0
        pulse = 0
        pulseHeight = 0
        pulseLp = 0
        noiseEnvelope = 0
        sustainGain = 0
        for i in 0..<kSnareNumModes {
            resonator[i].initialize()
            oscillator[i].initialize()
        }
        noiseFilter.initialize()
    }

    func render(_ r: PlaitsResources, _ random: StmRandom, _ sustain: Bool, _ trigger: Bool, _ accent: Float,
                _ f0: Float, _ toneIn: Float, _ decay: Float, _ snappyIn: Float,
                _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var tone = toneIn
        var snappy = snappyIn
        let decayXt = decay * (1 + decay * (decay - 1))
        let kTriggerPulseDuration = stmInt(1.0e-3 * kSampleRate)
        let kPulseDecayTime: Float = 0.1e-3 * kSampleRate
        let q = 2000 * r.semitonesToRatio(decayXt * 84)
        let noiseEnvelopeDecay = 1 - 0.0017 * r.semitonesToRatio(-decay * (50 + snappy * 10))
        let exciterLeak = snappy * (2 - snappy) * 0.1

        snappy = snappy * 1.1 - 0.05
        constrain(&snappy, 0, 1)

        if trigger {
            pulseRemainingSamples = kTriggerPulseDuration
            pulseHeight = 3 + 7 * accent
            noiseEnvelope = 2
        }

        for i in 0..<kSnareNumModes {
            f[i] = min(f0 * modeFrequencies[i], 0.499)
            resonator[i].setFQ(f[i], 1 + f[i] * (i == 0 ? q : q * 0.25), .fast)
        }

        if tone < 0.666667 {
            // 808-подобно (2 моды) → 909-подобно (5 мод).
            tone *= 1.5
            gain[0] = 1.5 + (1 - tone) * (1 - tone) * 4.5
            gain[1] = 2 * tone + 0.15
            for i in 2..<kSnareNumModes { gain[i] = 0 }
        } else {
            tone = (tone - 0.666667) * 3
            gain[0] = 1.5 - tone * 0.5
            gain[1] = 2.15 - tone * 0.7
            for i in 2..<kSnareNumModes {
                gain[i] = tone
                tone *= tone
            }
        }

        var fNoise = f0 * 16
        constrain(&fNoise, 0, 0.499)
        noiseFilter.setFQ(fNoise, 1 + fNoise * 1.5, .fast)

        var sustainGainMod = ParameterInterpolator(sustainGain, accent * decay, size)
        for n in 0..<size {
            // Импульс возбуждения.
            var p: Float = 0
            if pulseRemainingSamples > 0 {
                pulseRemainingSamples -= 1
                p = pulseRemainingSamples > 0 ? pulseHeight : pulseHeight - 1
                pulse = p
            } else {
                pulse *= 1 - 1 / kPulseDecayTime
                p = pulse
            }

            let sustainGainValue = sustainGainMod.next()

            onePole(&pulseLp, p, 0.75)

            var shell: Float = 0
            for i in 0..<kSnareNumModes {
                let excitation: Float = i == 0 ? (p - pulseLp) + 0.006 * p : 0.026 * p
                shell += gain[i] * (sustain
                    ? oscillator[i].next(r, f[i]) * sustainGainValue * 0.25
                    : resonator[i].process(excitation, .bandPass) + excitation * exciterLeak)
            }
            shell = stmSoftClip(shell)

            // Шум.
            var noise = 2 * random.getFloat() - 1
            if noise < 0 { noise = 0 }
            noiseEnvelope *= noiseEnvelopeDecay
            noise *= (sustain ? sustainGainValue : noiseEnvelope) * snappy * 2
            noise = noiseFilter.process(noise, .bandPass)

            out[n] = noise + shell * (1 - snappy)
        }
        sustainGain = sustainGainMod.value
        flushDenormal(&pulse)
        flushDenormal(&pulseLp)
        flushDenormal(&noiseEnvelope)
        for i in 0..<kSnareNumModes { resonator[i].flush() }
        noiseFilter.flush()
    }
}

/// Малый барабан 909-подобный: два искажённых синуса и фильтрованный шум.
struct SyntheticSnareDrum {
    private var phase0: Float = 0
    private var phase1: Float = 0
    private var drumAmplitude: Float = 0
    private var snareAmplitude: Float = 0
    private var fm: Float = 0
    private var sustainGain: Float = 0
    private var holdCounter = 0
    private var drumLp = OnePole()
    private var snareHp = OnePole()
    private var snareLp = Svf()

    mutating func initialize() {
        phase0 = 0
        phase1 = 0
        drumAmplitude = 0
        snareAmplitude = 0
        fm = 0
        holdCounter = 0
        sustainGain = 0
        drumLp.initialize()
        snareHp.initialize()
        snareLp.initialize()
    }

    @inline(__always) private func distortedSine(_ phase: Float) -> Float {
        let triangle = (phase < 0.5 ? phase : 1 - phase) * 4 - 1.3
        return 2 * triangle / (1 + abs(triangle))
    }

    mutating func render(_ r: PlaitsResources, _ random: StmRandom, _ sustain: Bool, _ trigger: Bool,
                         _ accent: Float, _ f0: Float, _ fmAmountIn: Float, _ decay: Float, _ snappyIn: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let decayXt = decay * (1 + decay * (decay - 1))
        let fmAmount = fmAmountIn * fmAmountIn
        var snappy = snappyIn
        let drumDecay = 1 - 1 / (0.015 * kSampleRate) * r.semitonesToRatio(
            -decayXt * 72 - fmAmount * 12 + snappy * 7)
        let snareDecay = 1 - 1 / (0.01 * kSampleRate) * r.semitonesToRatio(-decay * 60 - snappy * 7)
        let fmDecay = 1 - 1 / (0.007 * kSampleRate)

        snappy = snappy * 1.1 - 0.05
        constrain(&snappy, 0, 1)

        let drumLevel = (1 - snappy).squareRoot()
        let snareLevel = snappy.squareRoot()

        let snareFMin = min(10 * f0, 0.5)
        let snareFMax = min(35 * f0, 0.5)

        snareHp.setF(snareFMin, .fast)
        snareLp.setFQ(snareFMax, 0.5 + 2 * snappy, .fast)
        drumLp.setF(3 * f0, .fast)

        if trigger {
            drumAmplitude = 0.3 + 0.7 * accent
            snareAmplitude = drumAmplitude
            fm = 1
            phase0 = 0
            phase1 = 0
            holdCounter = stmInt((0.04 + decay * 0.03) * kSampleRate)
        }

        var sustainGainMod = ParameterInterpolator(sustainGain, accent * decay, size)
        for i in 0..<size {
            // В оригинале while (size--): внутри цикла size — число оставшихся отсчётов минус 1.
            let remaining = size - 1 - i
            if sustain {
                snareAmplitude = sustainGainMod.next()
                drumAmplitude = snareAmplitude
                fm = 0
            } else {
                // Огибающая из двух участков, как у 909.
                drumAmplitude *= (drumAmplitude > 0.03 || (remaining & 1) == 0) ? drumDecay : 1
                if holdCounter > 0 {
                    holdCounter -= 1
                } else {
                    snareAmplitude *= snareDecay
                }
                fm *= fmDecay
            }

            // Сброс фазы с шумом — «звон» и шероховатость на низких нотах.
            var resetNoise: Float = 0
            var resetNoiseAmount = (0.125 - f0) * 8
            constrain(&resetNoiseAmount, 0, 1)
            resetNoiseAmount *= resetNoiseAmount
            resetNoiseAmount *= fmAmount
            resetNoise += phase0 > 0.5 ? -1 : 1
            resetNoise += phase1 > 0.5 ? -1 : 1
            resetNoise *= resetNoiseAmount * 0.025

            let f = f0 * (1 + fmAmount * (4 * fm))
            phase0 += f
            phase1 += f * 1.47
            if resetNoiseAmount > 0.1 {
                if phase0 >= 1 + resetNoise { phase0 = 1 - phase0 }
                if phase1 >= 1 + resetNoise { phase1 = 1 - phase1 }
            } else {
                if phase0 >= 1 { phase0 -= 1 }
                if phase1 >= 1 { phase1 -= 1 }
            }

            var drum: Float = -0.1
            drum += distortedSine(phase0) * 0.60
            drum += distortedSine(phase1) * 0.25
            drum *= drumAmplitude * drumLevel
            drum = drumLp.process(drum, .lowPass)

            let noise = random.getFloat()
            var snare = snareLp.process(noise, .lowPass)
            snare = snareHp.process(snare, .highPass)
            snare = (snare + 0.1) * (snareAmplitude + fm) * snareLevel

            out[i] = snare + drum
        }
        sustainGain = sustainGainMod.value
        flushDenormal(&drumAmplitude)
        flushDenormal(&snareAmplitude)
        flushDenormal(&fm)
        drumLp.flush()
        snareHp.flush()
        snareLp.flush()
    }
}
