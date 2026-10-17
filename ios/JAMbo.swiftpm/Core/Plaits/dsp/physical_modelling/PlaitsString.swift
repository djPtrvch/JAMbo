// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/physical_modelling/string.h, .cc, string_voice.h, .cc.
// Класс String назван PlaitsString (имя не должно закрывать Swift.String).

let kStringDelayLineSize = 1024

/// Струна Карплуса–Стронга с дисперсией (STRUCTURE > 0,26) или изогнутым мостом (< 0,24).
final class PlaitsString {
    private let resources: PlaitsResources
    private let random: StmRandom
    private var string = DelayLine(kStringDelayLineSize)
    private var stretch = DelayLine(kStringDelayLineSize / 4)
    private var iirDampingFilter = Svf()
    private var dcBlocker = DCBlocker()
    private var delay: Float = 100
    private var dispersionNoise: Float = 0
    private var curvedBridge: Float = 0
    private var srcPhase: Float = 0
    private var outSample0: Float = 0
    private var outSample1: Float = 0

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        delay = 100
        reset()
    }

    deinit {
        string.deallocate()
        stretch.deallocate()
    }

    func reset() {
        string.reset()
        stretch.reset()
        iirDampingFilter.initialize()
        dcBlocker.initialize(1 - 20 / kSampleRate)
        dispersionNoise = 0
        curvedBridge = 0
        outSample0 = 0
        outSample1 = 0
        srcPhase = 0
    }

    func process(_ f0: Float, _ nonLinearityAmount: Float, _ brightness: Float, _ damping: Float,
                 _ input: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        if nonLinearityAmount <= 0 {
            processInternal(dispersion: false, f0, -nonLinearityAmount, brightness, damping, input, out, size)
        } else {
            processInternal(dispersion: true, f0, nonLinearityAmount, brightness, damping, input, out, size)
        }
    }

    @inline(__always)
    private func processInternal(dispersion: Bool, _ f0: Float, _ nonLinearityAmount: Float, _ brightnessIn: Float,
                                 _ damping: Float, _ input: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>,
                                 _ size: Int) {
        let r = resources
        var brightness = brightnessIn
        var delay = 1 / f0
        constrain(&delay, 4, Float(kStringDelayLineSize) - 4)

        // Выше 4 кГц (задержка меньше 12 отсчётов) — передискретизация вниз.
        var srcRatio = delay * f0
        if srcRatio >= 0.9999 {
            srcPhase = 1
            srcRatio = 1
        }

        var dampingCutoff = min(12 + damping * damping * 60 + brightness * 24, 84)
        var dampingF = min(f0 * r.semitonesToRatio(dampingCutoff), 0.499)

        // Около максимума DAMPING — бесконечное затухание.
        if damping >= 0.95 {
            let toInfinite = 20 * (damping - 0.95)
            brightness += toInfinite * (1 - brightness)
            dampingF += toInfinite * (0.4999 - dampingF)
            dampingCutoff += toInfinite * (128 - dampingCutoff)
        }

        iirDampingFilter.setFQ(dampingF, 0.5, .fast)

        let dampingCompensation = stmInterpolate(r.lutSvfShift, dampingCutoff, 1)

        var delayModulation = ParameterInterpolator(self.delay, delay * dampingCompensation, size)

        let stretchPoint = nonLinearityAmount * (2 - nonLinearityAmount) * 0.225
        var stretchCorrection = (160 / kSampleRate) * delay
        constrain(&stretchCorrection, 1, 2.1)

        let noiseAmountSqrt: Float = nonLinearityAmount > 0.75 ? 4 * (nonLinearityAmount - 0.75) : 0
        let noiseAmount = noiseAmountSqrt * noiseAmountSqrt * 0.1
        let noiseFilter = 0.06 + 0.94 * brightness * brightness

        let bridgeCurvingSqrt = nonLinearityAmount
        let bridgeCurving = bridgeCurvingSqrt * bridgeCurvingSqrt * 0.01

        let apGain = -0.618 * nonLinearityAmount / (0.15 + abs(nonLinearityAmount))

        for i in 0..<size {
            srcPhase += srcRatio
            if srcPhase > 1 {
                srcPhase -= 1

                var d = delayModulation.next()
                var s: Float = 0

                if dispersion {
                    let noise = random.getFloat() - 0.5
                    onePole(&dispersionNoise, noise, noiseFilter)
                    d *= 1 + dispersionNoise * noiseAmount
                } else {
                    d *= 1 - curvedBridge * bridgeCurving
                }

                if dispersion {
                    let apDelay = d * stretchPoint
                    let mainDelay = d - apDelay * (0.408 - stretchPoint * 0.308) * stretchCorrection
                    if apDelay >= 4 && mainDelay >= 4 {
                        s = string.read(mainDelay)
                        // Allpass(s, size_t delay, …): задержка отбрасывает дробную часть.
                        s = stretch.allpass(s, stmInt(apDelay), apGain)
                    } else {
                        s = string.readHermite(d)
                    }
                } else {
                    s = string.readHermite(d)
                }

                if !dispersion {
                    let value = abs(s) - 0.025
                    let sign: Float = s > 0 ? 1 : -1.5
                    curvedBridge = (abs(value) + value) * sign
                }

                s += input[i]
                constrain(&s, -20, 20)

                s = dcBlocker.process(s)

                s = iirDampingFilter.process(s, .lowPass)
                string.write(s)

                outSample1 = outSample0
                outSample0 = s
            }
            out[i] += stmCrossfade(outSample1, outSample0, srcPhase)
        }
        self.delay = delayModulation.value
        flushDenormal(&dispersionNoise)
        flushDenormal(&curvedBridge)
        flushDenormal(&outSample0)
        flushDenormal(&outSample1)
        iirDampingFilter.flush()
        dcBlocker.flush()
    }
}

/// Голос струны: возбуждение (шумовой импульс или Dust при sustain) → фильтр → струна. AUX — возбуждение.
final class StringVoice {
    private let resources: PlaitsResources
    private let random: StmRandom
    private var excitationFilter = Svf()
    private let string: PlaitsString
    private var remainingNoiseSamples = 0

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        excitationFilter.initialize()
        string = PlaitsString(resources: resources, random: random)
        remainingNoiseSamples = 0
    }

    func reset() {
        string.reset()
    }

    func render(_ sustain: Bool, _ trigger: Bool, _ accent: Float, _ f0: Float, _ structure: Float,
                _ brightnessIn: Float, _ dampingIn: Float, _ temp: UnsafeMutablePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>, _ size: Int) {
        let r = resources
        var brightness = brightnessIn
        var damping = dampingIn
        let density = brightness * brightness

        brightness += 0.25 * accent * (1 - brightness)
        damping += 0.25 * accent * (1 - damping)

        // Возбуждение.
        if trigger || sustain {
            let range: Float = 72
            let f = 4 * f0
            let cutoff = min(f * r.semitonesToRatio((brightness * (2 - brightness) - 0.5) * range), 0.499)
            let q: Float = sustain ? 1 : 0.5
            remainingNoiseSamples = Int(stmU32(1 / f0))
            excitationFilter.setFQ(cutoff, q, .dirty)
        }

        if sustain {
            let dustF = 0.00005 + 0.99995 * density * density
            for i in 0..<size {
                temp[i] = plaitsDust(random, dustF) * (8 - dustF * 6) * accent
            }
        } else if remainingNoiseSamples > 0 {
            let noiseSamples = min(remainingNoiseSamples, size)
            remainingNoiseSamples -= noiseSamples
            for i in 0..<noiseSamples { temp[i] = 2 * random.getFloat() - 1 }
            for i in noiseSamples..<size { temp[i] = 0 }
        } else {
            for i in 0..<size { temp[i] = 0 }
        }

        excitationFilter.process(temp, temp, size, .lowPass)
        excitationFilter.flush()
        for i in 0..<size { aux[i] += temp[i] }

        let nonLinearity: Float = structure < 0.24
            ? (structure - 0.24) * 4.166
            : (structure > 0.26 ? (structure - 0.26) * 1.35135 : 0)

        // Струна.
        string.process(f0, nonLinearity, brightness, damping, temp, out, size)
    }
}
