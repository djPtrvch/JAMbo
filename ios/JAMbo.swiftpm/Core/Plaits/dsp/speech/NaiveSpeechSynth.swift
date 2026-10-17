// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/speech/naive_speech_synth.h, .cc.

let kNaiveSpeechNumFormants = 5
let kNaiveSpeechNumPhonemes = 5
let kNaiveSpeechNumRegisters = 5

/// Formant: импульсы голосовой щели через 5 полосовых фильтров формант (фонема — phoneme, регистр — vocal register).
struct NaiveSpeechSynth {
    private var pulse = Oscillator()
    private var clickDuration = 0
    private var filter0 = Svf()
    private var filter1 = Svf()
    private var filter2 = Svf()
    private var filter3 = Svf()
    private var filter4 = Svf()
    private var pulseColoration = Svf()

    init() {
        filter0.initialize()
        filter1.initialize()
        filter2.initialize()
        filter3.initialize()
        filter4.initialize()
        pulseColoration.initialize()
        pulseColoration.setFQ(800 / kSampleRate, 0.5, .dirty)
    }

    /// (frequency, amplitude) форманты i фонемы p в регистре r.
    @inline(__always) private func formant(_ r: PlaitsResources, _ p: Int, _ reg: Int, _ i: Int) -> (Float, Float) {
        let k = ((p * kNaiveSpeechNumRegisters + reg) * kNaiveSpeechNumFormants + i) * 2
        return (Float(r.naivePhonemes[k]), Float(r.naivePhonemes[k + 1]))
    }

    @inline(__always) private mutating func processFormant(_ i: Int, _ f: Float, _ excitation: UnsafePointer<Float>,
                                                           _ output: UnsafeMutablePointer<Float>, _ size: Int,
                                                           _ a: Float) {
        switch i {
        case 0:
            filter0.setFQ(f, 20, .dirty)
            filter0.processAdd(excitation, output, size, a, .bandPass)
        case 1:
            filter1.setFQ(f, 20, .dirty)
            filter1.processAdd(excitation, output, size, a, .bandPass)
        case 2:
            filter2.setFQ(f, 20, .dirty)
            filter2.processAdd(excitation, output, size, a, .bandPass)
        case 3:
            filter3.setFQ(f, 20, .dirty)
            filter3.processAdd(excitation, output, size, a, .bandPass)
        default:
            filter4.setFQ(f, 20, .dirty)
            filter4.processAdd(excitation, output, size, a, .bandPass)
        }
    }

    @inline(__always)
    mutating func render(_ r: PlaitsResources, _ click: Bool, _ frequencyIn: Float, _ phoneme: Float,
                         _ vocalRegister: Float, _ excitation: UnsafeMutablePointer<Float>,
                         _ output: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequency = frequencyIn
        if click { clickDuration = 2400 }  // kSampleRate · 0,05
        clickDuration -= min(clickDuration, size)

        if clickDuration != 0 { frequency *= 0.5 }

        // Возбуждение — импульсы голосовой щели.
        pulse.render(.impulseTrain, frequency, 0.5, excitation, size)
        for i in 0..<size {
            excitation[i] = pulseColoration.process(excitation[i], .bandPass)
        }
        for i in 0..<size { excitation[i] *= 4 }

        let p = phoneme * (Float(kNaiveSpeechNumPhonemes) - 1.001)
        let rr = vocalRegister * (Float(kNaiveSpeechNumRegisters) - 1.001)
        let pIntegral = stmInt(p)
        let pFractional = p - Float(pIntegral)
        let rIntegral = stmInt(rr)
        let rFractional = rr - Float(rIntegral)

        output.update(repeating: 0, count: size)
        for i in 0..<kNaiveSpeechNumFormants {
            let p0r0 = formant(r, pIntegral, rIntegral, i)
            let p0r1 = formant(r, pIntegral, rIntegral + 1, i)
            let p1r0 = formant(r, pIntegral + 1, rIntegral, i)
            let p1r1 = formant(r, pIntegral + 1, rIntegral + 1, i)

            let p0rF = p0r0.0 + (p0r1.0 - p0r0.0) * rFractional
            let p1rF = p1r0.0 + (p1r1.0 - p1r0.0) * rFractional
            var f = p0rF + (p1rF - p0rF) * pFractional

            let p0rA = p0r0.1 + (p0r1.1 - p0r0.1) * rFractional
            let p1rA = p1r0.1 + (p1r1.1 - p1r0.1) * rFractional
            let a = (p0rA + (p1rA - p0rA) * pFractional) / 256

            if f >= 160 { f = 160 }
            f = r.a0 * r.semitonesToRatio(f - 33)
            if clickDuration != 0 && i == 0 { f *= 0.5 }
            processFormant(i, f, excitation, output, size, a)
        }
    }
}
