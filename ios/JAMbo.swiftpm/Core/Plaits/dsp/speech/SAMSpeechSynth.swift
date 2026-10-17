// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/speech/sam_speech_synth.h, .cc.

let kSAMNumFormants = 3
let kSAMNumVowels = 9
let kSAMNumConsonants = 8

/// Phoneme (SAM): три синусные форманты со сбросом фазы на каждом периоде голоса.
struct SAMSpeechSynth {
    private var phase: Float = 0
    private var frequency: Float = 0
    private var pulseNextSample: Float = 0
    private var pulseLp: Float = 0
    private var formantPhase0: UInt32 = 0
    private var formantPhase1: UInt32 = 0
    private var formantPhase2: UInt32 = 0
    private var consonantSamples = 0
    private var consonantIndex: Float = 0

    init() {}

    @inline(__always)
    mutating func render(_ r: PlaitsResources, _ consonant: Bool, _ frequencyIn: Float, _ vowel: Float,
                         _ formantShift: Float, _ excitation: UnsafeMutablePointer<Float>,
                         _ output: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequencyTarget = frequencyIn
        if frequencyTarget >= 0.0625 { frequencyTarget = 0.0625 }

        if consonant {
            consonantSamples = 2400  // kSampleRate · 0,05
            let rnd = stmInt((vowel + 3 * frequencyTarget + 7 * formantShift) * 8)
            consonantIndex = Float(rnd % kSAMNumConsonants)
        }
        consonantSamples -= min(consonantSamples, size)

        let phoneme: Float = consonantSamples != 0
            ? consonantIndex + Float(kSAMNumVowels)
            : vowel * (Float(kSAMNumVowels) - 1.0001)

        // InterpolatePhonemeData.
        let phonemeIntegral = stmInt(phoneme)
        let phonemeFractional = phoneme - Float(phonemeIntegral)
        let shift = 1 + formantShift * 2.5
        var ff0: UInt32 = 0, ff1: UInt32 = 0, ff2: UInt32 = 0
        var fa0: Float = 0, fa1: Float = 0, fa2: Float = 0
        for i in 0..<kSAMNumFormants {
            let k1 = (phonemeIntegral * kSAMNumFormants + i) * 2
            let k2 = ((phonemeIntegral + 1) * kSAMNumFormants + i) * 2
            let f1 = Float(r.samPhonemes[k1])
            let f2 = Float(r.samPhonemes[k2])
            var f = f1 + (f2 - f1) * phonemeFractional
            f *= 8 * shift * 4294967296.0 / kSampleRate
            let a1 = r.samFormantAmplitude[Int(r.samPhonemes[k1 + 1])]
            let a2 = r.samFormantAmplitude[Int(r.samPhonemes[k2 + 1])]
            let a = a1 + (a2 - a1) * phonemeFractional
            switch i {
            case 0: ff0 = stmU32(f); fa0 = a
            case 1: ff1 = stmU32(f); fa1 = a
            default: ff2 = stmU32(f); fa2 = a
            }
        }

        var fm = ParameterInterpolator(frequency, frequencyTarget, size)
        var next = pulseNextSample

        for i in 0..<size {
            var pulseThisSample = next
            next = 0
            let f = fm.next()
            phase += f

            if phase >= 1 {
                phase -= 1
                let t = phase / f
                formantPhase0 = stmU32(t * Float(ff0))
                formantPhase1 = stmU32(t * Float(ff1))
                formantPhase2 = stmU32(t * Float(ff2))
                pulseThisSample -= thisBlepSample(t)
                next -= nextBlepSample(t)
            } else {
                formantPhase0 &+= ff0
                formantPhase1 &+= ff1
                formantPhase2 &+= ff2
            }
            next += phase

            let d = pulseThisSample - 0.5 - pulseLp
            pulseLp += min(16 * f, 1) * d
            excitation[i] = d

            var s: Float = 0
            s += r.sineRaw(formantPhase0) * fa0
            s += r.sineRaw(formantPhase1) * fa1
            s += r.sineRaw(formantPhase2) * fa2
            s *= 1 - phase
            output[i] = s
        }
        pulseNextSample = next
        frequency = fm.value
    }
}
