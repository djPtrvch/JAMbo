// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/drums/analog_bass_drum.h, synthetic_bass_drum.h.

/// Бочка 808: импульс → резонансный SVF (частота с FM от атаки и самомодуляцией); sustain — синус.
struct AnalogBassDrum {
    private var pulseRemainingSamples = 0
    private var fmPulseRemainingSamples = 0
    private var pulse: Float = 0
    private var pulseHeight: Float = 0
    private var pulseLp: Float = 0
    private var fmPulseLp: Float = 0
    private var retrigPulse: Float = 0
    private var lpOut: Float = 0
    private var toneLp: Float = 0
    private var sustainGain: Float = 0
    private var resonator = Svf()
    private var oscillator = SineOscillator()

    mutating func initialize() {
        pulseRemainingSamples = 0
        fmPulseRemainingSamples = 0
        pulse = 0
        pulseHeight = 0
        pulseLp = 0
        fmPulseLp = 0
        retrigPulse = 0
        lpOut = 0
        toneLp = 0
        sustainGain = 0
        resonator.initialize()
        oscillator.initialize()
    }

    @inline(__always) private func diode(_ xIn: Float) -> Float {
        if xIn >= 0 { return xIn }
        let x = xIn * 2
        return 0.7 * x / (1 + abs(x))
    }

    mutating func render(_ r: PlaitsResources, _ sustain: Bool, _ trigger: Bool, _ accent: Float, _ f0: Float,
                         _ tone: Float, _ decay: Float, _ attackFmAmount: Float, _ selfFmAmount: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let kTriggerPulseDuration = stmInt(1.0e-3 * kSampleRate)
        let kFMPulseDuration = stmInt(6.0e-3 * kSampleRate)
        let kPulseDecayTime: Float = 0.2e-3 * kSampleRate
        let kPulseFilterTime: Float = 0.1e-3 * kSampleRate
        let kRetrigPulseDuration: Float = 0.05 * kSampleRate

        let scale = 0.001 / f0
        let q = 1500 * r.semitonesToRatio(decay * 80)
        let toneF = min(4 * f0 * r.semitonesToRatio(tone * 108), 1)
        let exciterLeak = 0.08 * (tone + 0.25)

        if trigger {
            pulseRemainingSamples = kTriggerPulseDuration
            fmPulseRemainingSamples = kFMPulseDuration
            pulseHeight = 3 + 7 * accent
            lpOut = 0
        }

        var sustainGainMod = ParameterInterpolator(sustainGain, accent * decay, size)

        for i in 0..<size {
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
            if sustain { p = 0 }
            onePole(&pulseLp, p, 1 / kPulseFilterTime)
            p = diode((p - pulseLp) + p * 0.044)

            // Импульс FM.
            var fmPulse: Float = 0
            if fmPulseRemainingSamples > 0 {
                fmPulseRemainingSamples -= 1
                fmPulse = 1
                // Конец импульса FM — повторный импульс в фильтр.
                retrigPulse = fmPulseRemainingSamples > 0 ? 0 : -0.8
            } else {
                retrigPulse *= 1 - 1 / kRetrigPulseDuration
            }
            if sustain { fmPulse = 0 }
            onePole(&fmPulseLp, fmPulse, 1 / kPulseFilterTime)

            // Частота резонатора.
            let punch = 0.7 + diode(10 * lpOut - 1)
            let attackFm = fmPulseLp * 1.7 * attackFmAmount
            let selfFm = punch * 0.08 * selfFmAmount
            var f = f0 * (1 + attackFm + selfFm)
            constrain(&f, 0, 0.4)

            var resonatorOut: Float
            if sustain {
                (resonatorOut, lpOut) = oscillator.next(r, f, sustainGainMod.next())
            } else {
                resonator.setFQ(f, 1 + q * f, .dirty)
                (resonatorOut, lpOut) = resonator.process((p - retrigPulse * 0.2) * scale, .bandPass, .lowPass)
            }

            onePole(&toneLp, p * exciterLeak + resonatorOut, toneF)
            out[i] = toneLp
        }
        sustainGain = sustainGainMod.value
    }
}

/// Бочка 909-подобная: синус с искажением и огибающими (тело, щелчок, шум атаки).
struct SyntheticBassDrum {
    private var f0: Float = 0
    private var phase: Float = 0
    private var phaseNoise: Float = 0
    private var fm: Float = 0
    private var fmLp: Float = 0
    private var bodyEnv: Float = 0
    private var bodyEnvLp: Float = 0
    private var transientEnv: Float = 0
    private var transientEnvLp: Float = 0
    private var sustainGain: Float = 0
    private var toneLp: Float = 0
    // SyntheticBassDrumClick.
    private var clickLp: Float = 0
    private var clickHp: Float = 0
    private var clickFilter = Svf()
    // SyntheticBassDrumAttackNoise.
    private var noiseLp: Float = 0
    private var noiseHp: Float = 0
    private var bodyEnvPulseWidth = 0
    private var fmPulseWidth = 0

    mutating func initialize() {
        phase = 0
        phaseNoise = 0
        f0 = 0
        fm = 0
        fmLp = 0
        bodyEnvLp = 0
        bodyEnv = 0
        bodyEnvPulseWidth = 0
        fmPulseWidth = 0
        toneLp = 0
        sustainGain = 0
        clickLp = 0
        clickHp = 0
        clickFilter.initialize()
        clickFilter.setFQ(5000 / kSampleRate, 2, .fast)
        noiseLp = 0
        noiseHp = 0
    }

    @inline(__always) private func distortedSine(_ r: PlaitsResources, _ phaseIn: Float, _ phaseNoise: Float,
                                                 _ dirtiness: Float) -> Float {
        var phase = phaseIn + phaseNoise * dirtiness
        phase -= Float(stmInt(phase))
        let triangle = (phase < 0.5 ? phase : 1 - phase) * 4 - 1
        let sine = 2 * triangle / (1 + abs(triangle))
        let cleanSine = r.sine(phase + 0.75)
        return sine + (1 - dirtiness) * (cleanSine - sine)
    }

    @inline(__always) private func transistorVCA(_ sIn: Float, _ gain: Float) -> Float {
        let s = (sIn - 0.6) * gain
        return 3 * s / (2 + abs(s)) + gain * 0.3
    }

    mutating func render(_ r: PlaitsResources, _ random: StmRandom, _ sustain: Bool, _ trigger: Bool,
                         _ accent: Float, _ f0In: Float, _ tone: Float, _ decayIn: Float, _ dirtinessIn: Float,
                         _ fmEnvelopeAmount: Float, _ fmEnvelopeDecayIn: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        let decay = decayIn * decayIn
        let fmEnvelopeDecay = fmEnvelopeDecayIn * fmEnvelopeDecayIn

        var f0Mod = ParameterInterpolator(f0, f0In, size)

        let dirtiness = dirtinessIn * max(1 - 8 * f0In, 0)

        let fmDecay = 1 - 1 / (0.008 * (1 + fmEnvelopeDecay * 4) * kSampleRate)
        let bodyEnvDecay = 1 - 1 / (0.02 * kSampleRate) * r.semitonesToRatio(-decay * 60)
        let transientEnvDecay = 1 - 1 / (0.005 * kSampleRate)
        let toneF = min(4 * f0In * r.semitonesToRatio(tone * 108), 1)
        let transientLevel = tone

        if trigger {
            fm = 1
            transientEnv = 0.3 + 0.7 * accent
            bodyEnv = transientEnv
            bodyEnvPulseWidth = stmInt(kSampleRate * 0.001)
            fmPulseWidth = stmInt(kSampleRate * 0.0013)
        }

        var sustainGainMod = ParameterInterpolator(sustainGain, accent * decay, size)

        for i in 0..<size {
            onePole(&phaseNoise, random.getFloat() - 0.5, 0.002)

            var mix: Float = 0

            if sustain {
                phase += f0Mod.next()
                if phase >= 1 { phase -= 1 }
                let body = distortedSine(r, phase, phaseNoise, dirtiness)
                mix -= transistorVCA(body, sustainGainMod.next())
            } else {
                if fmPulseWidth > 0 {
                    fmPulseWidth -= 1
                    phase = 0.25
                } else {
                    fm *= fmDecay
                    let fmAmount = 1 + fmEnvelopeAmount * 3.5 * fmLp
                    phase += min(f0Mod.next() * fmAmount, 0.5)
                    if phase >= 1 { phase -= 1 }
                }

                if bodyEnvPulseWidth > 0 {
                    bodyEnvPulseWidth -= 1
                } else {
                    bodyEnv *= bodyEnvDecay
                    transientEnv *= transientEnvDecay
                }

                let envelopeLpF: Float = 0.1
                onePole(&bodyEnvLp, bodyEnv, envelopeLpF)
                onePole(&transientEnvLp, transientEnv, envelopeLpF)
                onePole(&fmLp, fm, envelopeLpF)

                let body = distortedSine(r, phase, phaseNoise, dirtiness)
                // click_.Process(…) + noise_.Render().
                slope(&clickLp, bodyEnvPulseWidth > 0 ? 0 : 1, 0.5, 0.1)
                onePole(&clickHp, clickLp, 0.04)
                let click = clickFilter.process(clickLp - clickHp, .lowPass)
                let sample = random.getFloat()
                onePole(&noiseLp, sample, 0.05)
                onePole(&noiseHp, noiseLp, 0.005)
                let transient = click + (noiseLp - noiseHp)

                mix -= transistorVCA(body, bodyEnvLp)
                mix -= transient * transientEnvLp * transientLevel
            }

            onePole(&toneLp, mix, toneF)
            out[i] = toneLp
        }
        f0 = f0Mod.value
        sustainGain = sustainGainMod.value
    }
}
