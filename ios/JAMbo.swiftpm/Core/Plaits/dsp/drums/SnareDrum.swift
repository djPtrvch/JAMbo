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
        if sustain {
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
        } else {
            // Удар: 5 мод корпуса и шум без вызовов на каждом отсчёте (Svf.process, onePole, SoftClip, StmRandom
            // развёрнуты в том же порядке): в отладочной сборке (Playgrounds) вызовы дороже арифметики.
            let g0 = resonator[0].g, r0 = resonator[0].r, h0 = resonator[0].h, k0 = gain[0]
            var a0 = resonator[0].state1, b0 = resonator[0].state2
            let g1 = resonator[1].g, r1 = resonator[1].r, h1 = resonator[1].h, k1 = gain[1]
            var a1 = resonator[1].state1, b1 = resonator[1].state2
            let g2 = resonator[2].g, r2 = resonator[2].r, h2 = resonator[2].h, k2 = gain[2]
            var a2 = resonator[2].state1, b2 = resonator[2].state2
            let g3 = resonator[3].g, r3 = resonator[3].r, h3 = resonator[3].h, k3 = gain[3]
            var a3 = resonator[3].state1, b3 = resonator[3].state2
            let g4 = resonator[4].g, r4 = resonator[4].r, h4 = resonator[4].h, k4 = gain[4]
            var a4 = resonator[4].state1, b4 = resonator[4].state2
            let ng = noiseFilter.g, nr = noiseFilter.r, nh = noiseFilter.h
            var na = noiseFilter.state1, nb = noiseFilter.state2
            let pulseDecay = 1 - 1 / kPulseDecayTime
            var lRemaining = pulseRemainingSamples, lPulse = pulse, lPulseLp = pulseLp, lNoiseEnv = noiseEnvelope
            var rnd = random.state
            var n = 0
            while n < size {
                // Импульс возбуждения.
                var p: Float = 0
                if lRemaining > 0 {
                    lRemaining -= 1
                    p = lRemaining > 0 ? pulseHeight : pulseHeight - 1
                    lPulse = p
                } else {
                    lPulse *= pulseDecay
                    p = lPulse
                }
                // sustainGainMod.next() (значение в ударе не нужно, интерполятор идёт дальше).
                sustainGainMod.value += sustainGainMod.increment
                lPulseLp += 0.75 * (p - lPulseLp)
                let e1: Float = 0.026 * p
                var shell: Float = 0
                let x0: Float = (p - lPulseLp) + 0.006 * p
                let hp0 = (x0 - r0 * a0 - g0 * a0 - b0) * h0
                let bp0 = g0 * hp0 + a0
                a0 = g0 * hp0 + bp0
                let lp0 = g0 * bp0 + b0
                b0 = g0 * bp0 + lp0
                shell += k0 * (bp0 + x0 * exciterLeak)
                let x1: Float = e1
                let hp1 = (x1 - r1 * a1 - g1 * a1 - b1) * h1
                let bp1 = g1 * hp1 + a1
                a1 = g1 * hp1 + bp1
                let lp1 = g1 * bp1 + b1
                b1 = g1 * bp1 + lp1
                shell += k1 * (bp1 + x1 * exciterLeak)
                let x2: Float = e1
                let hp2 = (x2 - r2 * a2 - g2 * a2 - b2) * h2
                let bp2 = g2 * hp2 + a2
                a2 = g2 * hp2 + bp2
                let lp2 = g2 * bp2 + b2
                b2 = g2 * bp2 + lp2
                shell += k2 * (bp2 + x2 * exciterLeak)
                let x3: Float = e1
                let hp3 = (x3 - r3 * a3 - g3 * a3 - b3) * h3
                let bp3 = g3 * hp3 + a3
                a3 = g3 * hp3 + bp3
                let lp3 = g3 * bp3 + b3
                b3 = g3 * bp3 + lp3
                shell += k3 * (bp3 + x3 * exciterLeak)
                let x4: Float = e1
                let hp4 = (x4 - r4 * a4 - g4 * a4 - b4) * h4
                let bp4 = g4 * hp4 + a4
                a4 = g4 * hp4 + bp4
                let lp4 = g4 * bp4 + b4
                b4 = g4 * bp4 + lp4
                shell += k4 * (bp4 + x4 * exciterLeak)
                // SoftClip.
                if shell < -3 { shell = -1 } else if shell > 3 { shell = 1 } else {
                    shell = shell * (27 + shell * shell) / (27 + 9 * shell * shell)
                }

                // Шум.
                rnd = rnd &* 1664525 &+ 1013904223
                var noise = 2 * (Float(rnd) / 4294967296.0) - 1
                if noise < 0 { noise = 0 }
                lNoiseEnv *= noiseEnvelopeDecay
                noise *= lNoiseEnv * snappy * 2
                let nhp = (noise - nr * na - ng * na - nb) * nh
                let nbp = ng * nhp + na
                na = ng * nhp + nbp
                let nlp = ng * nbp + nb
                nb = ng * nbp + nlp

                out[n] = nbp + shell * (1 - snappy)
                n += 1
            }
            random.state = rnd
            pulseRemainingSamples = lRemaining
            pulse = lPulse
            pulseLp = lPulseLp
            noiseEnvelope = lNoiseEnv
            resonator[0].state1 = a0
            resonator[0].state2 = b0
            resonator[1].state1 = a1
            resonator[1].state2 = b1
            resonator[2].state1 = a2
            resonator[2].state2 = b2
            resonator[3].state1 = a3
            resonator[3].state2 = b3
            resonator[4].state1 = a4
            resonator[4].state2 = b4
            noiseFilter.state1 = na
            noiseFilter.state2 = nb
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
