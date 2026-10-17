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

        // Цикл без вызовов вспомогательных функций и с состоянием в локальных переменных (onePole, diode, constrain,
        // Svf.setFQ(.dirty) и process развёрнуты в том же порядке операций): в отладочной сборке (Playgrounds)
        // вызов функции на каждом отсчёте дороже самой арифметики.
        let pulseDecay = 1 - 1 / kPulseDecayTime
        let pulseFilter = 1 / kPulseFilterTime
        let retrigDecay = 1 - 1 / kRetrigPulseDuration
        let dirtyA = FilterK.dirtyA, piF = Float.pi
        var pulseRemaining = pulseRemainingSamples, fmPulseRemaining = fmPulseRemainingSamples
        var pulse = self.pulse, pulseLp = self.pulseLp, fmPulseLp = self.fmPulseLp
        var retrigPulse = self.retrigPulse, lpOut = self.lpOut, toneLp = self.toneLp
        var s1 = resonator.state1, s2 = resonator.state2
        var i = 0
        while i < size {
            // Импульс возбуждения.
            var p: Float = 0
            if pulseRemaining > 0 {
                pulseRemaining -= 1
                p = pulseRemaining > 0 ? pulseHeight : pulseHeight - 1
                pulse = p
            } else {
                pulse *= pulseDecay
                p = pulse
            }
            if sustain { p = 0 }
            pulseLp += pulseFilter * (p - pulseLp)
            // Diode.
            var dx = (p - pulseLp) + p * 0.044
            if dx < 0 {
                dx *= 2
                dx = 0.7 * dx / (1 + -dx)
            }
            p = dx

            // Импульс FM.
            var fmPulse: Float = 0
            if fmPulseRemaining > 0 {
                fmPulseRemaining -= 1
                fmPulse = 1
                // Конец импульса FM — повторный импульс в фильтр.
                retrigPulse = fmPulseRemaining > 0 ? 0 : -0.8
            } else {
                retrigPulse *= retrigDecay
            }
            if sustain { fmPulse = 0 }
            fmPulseLp += pulseFilter * (fmPulse - fmPulseLp)

            // Частота резонатора.
            var px = 10 * lpOut - 1
            if px < 0 {
                px *= 2
                px = 0.7 * px / (1 + -px)
            }
            let punch = 0.7 + px
            let attackFm = fmPulseLp * 1.7 * attackFmAmount
            let selfFm = punch * 0.08 * selfFmAmount
            var f = f0 * (1 + attackFm + selfFm)
            if f < 0 { f = 0 } else if f > 0.4 { f = 0.4 }

            var resonatorOut: Float
            if sustain {
                (resonatorOut, lpOut) = oscillator.next(r, f, sustainGainMod.next())
            } else {
                // Svf.setFQ(f, 1 + q·f, .dirty) и Process<BAND_PASS, LOW_PASS>.
                let g = f * (piF + dirtyA * f * f)
                let rr = 1 / (1 + q * f)
                let h = 1 / (1 + rr * g + g * g)
                let x = (p - retrigPulse * 0.2) * scale
                let hp = (x - rr * s1 - g * s1 - s2) * h
                let bp = g * hp + s1
                s1 = g * hp + bp
                let lp = g * bp + s2
                s2 = g * bp + lp
                resonatorOut = bp
                lpOut = lp
            }

            toneLp += toneF * ((p * exciterLeak + resonatorOut) - toneLp)
            out[i] = toneLp
            i += 1
        }
        pulseRemainingSamples = pulseRemaining
        fmPulseRemainingSamples = fmPulseRemaining
        self.pulse = pulse
        self.pulseLp = pulseLp
        self.fmPulseLp = fmPulseLp
        self.retrigPulse = retrigPulse
        self.lpOut = lpOut
        self.toneLp = toneLp
        resonator.state1 = s1
        resonator.state2 = s2
        sustainGain = sustainGainMod.value
        flushDenormal(&self.pulse)
        flushDenormal(&self.pulseLp)
        flushDenormal(&self.fmPulseLp)
        flushDenormal(&self.retrigPulse)
        flushDenormal(&self.lpOut)
        flushDenormal(&self.toneLp)
        resonator.flush()
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

        // Ветка удара — без вызовов вспомогательных функций, генератор шума и состояние — в локальных переменных
        // (порядок операций прежний): в отладочной сборке (Playgrounds) вызовы на каждом отсчёте дороже арифметики.
        let lut = r.lutSine
        var rnd = random.state
        var f0Val = f0Mod.value
        let f0Inc = f0Mod.increment
        var phase = self.phase, phaseNoise = self.phaseNoise, fm = self.fm, fmLp = self.fmLp
        var bodyEnv = self.bodyEnv, bodyEnvLp = self.bodyEnvLp
        var transientEnv = self.transientEnv, transientEnvLp = self.transientEnvLp, toneLp = self.toneLp
        var clickLp = self.clickLp, clickHp = self.clickHp, noiseLp = self.noiseLp, noiseHp = self.noiseHp
        var bodyEnvPulse = bodyEnvPulseWidth, fmPulse = fmPulseWidth
        var cs1 = clickFilter.state1, cs2 = clickFilter.state2
        let cg = clickFilter.g, cr = clickFilter.r, ch = clickFilter.h
        var i = 0
        while i < size {
            rnd = rnd &* 1664525 &+ 1013904223
            phaseNoise += 0.002 * ((Float(rnd) / 4294967296.0 - 0.5) - phaseNoise)

            var mix: Float = 0

            if sustain {
                f0Val += f0Inc
                phase += f0Val
                if phase >= 1 { phase -= 1 }
                let body = distortedSine(r, phase, phaseNoise, dirtiness)
                mix -= transistorVCA(body, sustainGainMod.next())
            } else {
                if fmPulse > 0 {
                    fmPulse -= 1
                    phase = 0.25
                } else {
                    fm *= fmDecay
                    let fmAmount = 1 + fmEnvelopeAmount * 3.5 * fmLp
                    f0Val += f0Inc
                    let inc = f0Val * fmAmount
                    phase += 0.5 < inc ? 0.5 : inc
                    if phase >= 1 { phase -= 1 }
                }

                if bodyEnvPulse > 0 {
                    bodyEnvPulse -= 1
                } else {
                    bodyEnv *= bodyEnvDecay
                    transientEnv *= transientEnvDecay
                }

                let envelopeLpF: Float = 0.1
                bodyEnvLp += envelopeLpF * (bodyEnv - bodyEnvLp)
                transientEnvLp += envelopeLpF * (transientEnv - transientEnvLp)
                fmLp += envelopeLpF * (fm - fmLp)

                // DistortedSine(phase, phaseNoise, dirtiness).
                var ph = phase + phaseNoise * dirtiness
                ph -= (ph > -1e9 && ph < 1e9) ? Float(Int(ph)) : 0
                let triangle = (ph < 0.5 ? ph : 1 - ph) * 4 - 1
                let sine = 2 * triangle / (1 + (triangle < 0 ? -triangle : triangle))
                // Sine(ph + 0.75): InterpolateWrap(lut_sine, …, 512).
                var wx = ph + 0.75
                wx -= (wx > -1e9 && wx < 1e9) ? Float(Int(wx)) : 0
                wx *= 512
                let wi = (wx > -1e9 && wx < 1e9) ? Int(wx) : 0
                let wf = wx - Float(wi)
                let cleanSine = lut[wi] + (lut[wi + 1] - lut[wi]) * wf
                let body = sine + (1 - dirtiness) * (cleanSine - sine)

                // click_.Process(…): SLOPE, ONE_POLE, Svf ФНЧ; noise_.Render().
                let clickIn: Float = bodyEnvPulse > 0 ? 0 : 1
                let ce = clickIn - clickLp
                clickLp += (ce > 0 ? 0.5 : 0.1) * ce
                clickHp += 0.04 * (clickLp - clickHp)
                let cx = clickLp - clickHp
                let chp = (cx - cr * cs1 - cg * cs1 - cs2) * ch
                let cbp = cg * chp + cs1
                cs1 = cg * chp + cbp
                let clp = cg * cbp + cs2
                cs2 = cg * cbp + clp
                rnd = rnd &* 1664525 &+ 1013904223
                noiseLp += 0.05 * (Float(rnd) / 4294967296.0 - noiseLp)
                noiseHp += 0.005 * (noiseLp - noiseHp)
                let transient = clp + (noiseLp - noiseHp)

                // TransistorVCA(body, bodyEnvLp).
                let vs = (body - 0.6) * bodyEnvLp
                mix -= 3 * vs / (2 + (vs < 0 ? -vs : vs)) + bodyEnvLp * 0.3
                mix -= transient * transientEnvLp * transientLevel
            }

            toneLp += toneF * (mix - toneLp)
            out[i] = toneLp
            i += 1
        }
        random.state = rnd
        f0Mod.value = f0Val
        self.phase = phase
        self.phaseNoise = phaseNoise
        self.fm = fm
        self.fmLp = fmLp
        self.bodyEnv = bodyEnv
        self.bodyEnvLp = bodyEnvLp
        self.transientEnv = transientEnv
        self.transientEnvLp = transientEnvLp
        self.toneLp = toneLp
        self.clickLp = clickLp
        self.clickHp = clickHp
        self.noiseLp = noiseLp
        self.noiseHp = noiseHp
        bodyEnvPulseWidth = bodyEnvPulse
        fmPulseWidth = fmPulse
        clickFilter.state1 = cs1
        clickFilter.state2 = cs2
        f0 = f0Mod.value
        sustainGain = sustainGainMod.value
        flushDenormal(&self.fm)
        flushDenormal(&self.fmLp)
        flushDenormal(&self.bodyEnv)
        flushDenormal(&self.bodyEnvLp)
        flushDenormal(&self.transientEnv)
        flushDenormal(&self.transientEnvLp)
        flushDenormal(&self.toneLp)
        flushDenormal(&self.clickLp)
        flushDenormal(&self.clickHp)
        clickFilter.flush()
    }
}
