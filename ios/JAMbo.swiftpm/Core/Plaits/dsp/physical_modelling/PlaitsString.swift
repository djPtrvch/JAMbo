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

        // Состояние — в локальных переменных на время блока: в отладочной сборке (Playgrounds) каждый вызов метода
        // структуры-свойства класса в цикле — проверка доступа, STRING перегружал процессор.
        // Линии задержки (Read, ReadHermite, Write, Allpass), DC-блокер, ФНЧ затухания, шум, интерполятор задержки —
        // развёрнуты, в том же порядке операций; состояние — в локальных переменных на блок.
        let sLine = string.line, sMask = string.mask, sMax = string.maxDelay
        var sWp = string.writePtr
        let tLine = stretch.line, tMask = stretch.mask, tMax = stretch.maxDelay
        var tWp = stretch.writePtr
        let fg = iirDampingFilter.g, fr = iirDampingFilter.r, fh = iirDampingFilter.h
        var fs1 = iirDampingFilter.state1, fs2 = iirDampingFilter.state2
        let dcPole = dcBlocker.pole
        var dcX = dcBlocker.x, dcY = dcBlocker.y
        var lNoise = dispersionNoise, lBridge = curvedBridge
        var lSrc = srcPhase, lOut0 = outSample0, lOut1 = outSample1
        var dVal = delayModulation.value
        let dInc = delayModulation.increment
        var rnd = random.state
        var i = 0
        while i < size {
            lSrc += srcRatio
            if lSrc > 1 {
                lSrc -= 1

                dVal += dInc
                var d = dVal
                var s: Float = 0

                if dispersion {
                    rnd = rnd &* 1664525 &+ 1013904223
                    let noise = Float(rnd) / 4294967296.0 - 0.5
                    lNoise += noiseFilter * (noise - lNoise)
                    d *= 1 + lNoise * noiseAmount
                } else {
                    d *= 1 - lBridge * bridgeCurving
                }

                var hermite = true
                if dispersion {
                    let apDelay = d * stretchPoint
                    let mainDelay = d - apDelay * (0.408 - stretchPoint * 0.308) * stretchCorrection
                    if apDelay >= 4 && mainDelay >= 4 {
                        hermite = false
                        // string_.Read(mainDelay).
                        let mi = (mainDelay > -2147483648 && mainDelay < 2147483648) ? Int(mainDelay) : 0
                        let mf = mainDelay - Float(mi)
                        let ma = sLine[(sWp + mi) & sMask]
                        let mb = sLine[(sWp + mi + 1) & sMask]
                        s = ma + (mb - ma) * mf
                        // stretch_.Allpass(s, size_t(apDelay), apGain).
                        let ai = (apDelay > -2147483648 && apDelay < 2147483648) ? Int(apDelay) : 0
                        let read = tLine[(tWp + ai) & tMask]
                        let w = s + apGain * read
                        tLine[tWp] = (w < 0 ? -w : w) < 1e-20 ? 0 : w
                        tWp = (tWp - 1 + tMax) & tMask
                        s = -w * apGain + read
                    }
                }
                if hermite {
                    // string_.ReadHermite(d).
                    let hi = (d > -2147483648 && d < 2147483648) ? Int(d) : 0
                    let f = d - Float(hi)
                    let t = sWp + hi + sMax
                    let xm1 = sLine[(t - 1) & sMask]
                    let x0 = sLine[t & sMask]
                    let x1 = sLine[(t + 1) & sMask]
                    let x2 = sLine[(t + 2) & sMask]
                    let c = (x1 - xm1) * 0.5
                    let v = x0 - x1
                    let w = c + v
                    let a = w + v + (x2 - x0) * 0.5
                    let bNeg = w + a
                    s = (((a * f) - bNeg) * f + c) * f + x0
                }

                if !dispersion {
                    let value = (s < 0 ? -s : s) - 0.025
                    let sign: Float = s > 0 ? 1 : -1.5
                    lBridge = ((value < 0 ? -value : value) + value) * sign
                }

                s += input[i]
                if s < -20 { s = -20 } else if s > 20 { s = 20 }

                // DCBlocker.
                let oldX = dcX
                dcX = s
                dcY = dcY * dcPole + dcX - oldX
                s = dcY

                // Svf ФНЧ.
                let hp = (s - fr * fs1 - fg * fs1 - fs2) * fh
                let bp = fg * hp + fs1
                fs1 = fg * hp + bp
                let lp = fg * bp + fs2
                fs2 = fg * bp + lp
                s = lp

                // string_.Write(s).
                sLine[sWp] = (s < 0 ? -s : s) < 1e-20 ? 0 : s
                sWp = (sWp - 1 + sMax) & sMask

                lOut1 = lOut0
                lOut0 = s
            }
            out[i] += lOut1 + (lOut0 - lOut1) * lSrc
            i += 1
        }
        random.state = rnd
        self.delay = dVal
        flushDenormal(&lNoise)
        flushDenormal(&lBridge)
        flushDenormal(&lOut0)
        flushDenormal(&lOut1)
        flushDenormal(&fs1)
        flushDenormal(&fs2)
        flushDenormal(&dcX)
        flushDenormal(&dcY)
        string.writePtr = sWp
        stretch.writePtr = tWp
        iirDampingFilter.state1 = fs1
        iirDampingFilter.state2 = fs2
        dcBlocker.x = dcX
        dcBlocker.y = dcY
        dispersionNoise = lNoise
        curvedBridge = lBridge
        srcPhase = lSrc
        outSample0 = lOut0
        outSample1 = lOut1
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
