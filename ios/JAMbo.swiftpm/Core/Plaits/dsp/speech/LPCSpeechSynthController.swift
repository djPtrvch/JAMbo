// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/speech/lpc_speech_synth_controller.h, .cc — только фонемы (bank = −1): банк слов (Words) не перенесён
// (решение в ios/CLAUDE.md, лицензия данных TI — этап 12).

let kLPCSpeechSynthNumVowels = 5
let kLPCSpeechSynthNumConsonants = 10
let kLPCSpeechSynthNumPhonemes = 15
let kLPCSpeechSynthFPS: Float = 40

/// LPC: синтез на 8 кГц (rate) с повышением частоты polyBLEP; address выбирает гласную (между 5 кадрами),
/// триггер — случайную согласную на один кадр.
final class LPCSpeechSynthController {
    private var clockPhase: Float = 0
    private var sample0: Float = 0, sample1: Float = 0
    private var nextSample0: Float = 0, nextSample1: Float = 0
    private var gain: Float = 0
    private let synth: LPCSpeechSynth
    private var playbackFrame = -1
    private var lastPlaybackFrame = -1
    private var remainingFrameSamples = 0
    private let newSample: UnsafeMutablePointer<Float>

    init(random: StmRandom) {
        synth = LPCSpeechSynth(random: random)
        newSample = plaitsAllocate(2)
    }

    deinit { newSample.deallocate() }

    @inline(__always)
    func render(_ r: PlaitsResources, trigger: Bool, _ frequency: Float, _ prosodyAmount: Float, _ speed: Float,
                _ address: Float, _ formantShift: Float, _ gainTarget: Float,
                _ excitation: UnsafeMutablePointer<Float>, _ output: UnsafeMutablePointer<Float>, _ size: Int) {
        let rateRatio = r.semitonesToRatio((formantShift - 0.5) * 36)
        let rate = rateRatio / 6

        // Все записи нормированы к средней f0 100 Гц.
        let pitchShift = frequency / (rateRatio * kLPCSpeechSynthDefaultF0 / kCorrectedSampleRate)
        let stretch: Float = formantShift < 0.4 ? (formantShift - 0.4) * -45
            : (formantShift > 0.6 ? (formantShift - 0.6) * -45 : 0)
        let timeStretch = r.semitonesToRatio(-speed * 24 + stretch)

        let numFrames = kLPCSpeechSynthNumVowels
        let frames = r.lpcPhonemes

        if trigger {
            // Псевдослучайная согласная на длительность кадра.
            let rnd = stmInt((address + 3 * formantShift + 7 * frequency) * 8)
            playbackFrame = rnd % kLPCSpeechSynthNumConsonants
            playbackFrame += kLPCSpeechSynthNumVowels
            lastPlaybackFrame = playbackFrame + 1
            remainingFrameSamples = 0
        }

        if playbackFrame == -1 && remainingFrameSamples == 0 {
            synth.playFrame(frames, r.lpcPhonemeCount, address * (Float(numFrames) - 1.0001), true)
        } else {
            if remainingFrameSamples == 0 {
                synth.playFrame(frames, r.lpcPhonemeCount, Float(playbackFrame), false)
                remainingFrameSamples = stmInt(kSampleRate / kLPCSpeechSynthFPS * timeStretch)
                playbackFrame += 1
                if playbackFrame >= lastPlaybackFrame {
                    // bank == −1 — всегда назад к выбору гласной.
                    playbackFrame = -1
                }
            }
            remainingFrameSamples -= min(size, remainingFrameSamples)
        }

        var gainModulation = ParameterInterpolator(gain, gainTarget, size)

        for i in 0..<size {
            var thisSample0 = nextSample0
            var thisSample1 = nextSample1
            nextSample0 = 0
            nextSample1 = 0

            clockPhase += rate
            if clockPhase >= 1 {
                clockPhase -= 1
                let resetTime = clockPhase / rate

                synth.render(r, prosodyAmount, pitchShift, newSample, newSample + 1, 1)

                let discontinuity0 = newSample[0] - sample0
                let discontinuity1 = newSample[1] - sample1
                thisSample0 += discontinuity0 * thisBlepSample(resetTime)
                nextSample0 += discontinuity0 * nextBlepSample(resetTime)
                thisSample1 += discontinuity1 * thisBlepSample(resetTime)
                nextSample1 += discontinuity1 * nextBlepSample(resetTime)
                sample0 = newSample[0]
                sample1 = newSample[1]
            }
            nextSample0 += sample0
            nextSample1 += sample1
            let g = gainModulation.next()
            excitation[i] = thisSample0 * g
            output[i] = thisSample1 * g
        }
        gain = gainModulation.value
    }
}
