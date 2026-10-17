// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/speech_engine.h, .cc — без банков слов (Words): HARMONICS в JAMbo — не выше 1/3
// (Formant 0, Phoneme 1/6, LPC 1/3), ветка слов (group > 2) не перенесена.

/// Движок 7 (SPEECH): HARMONICS 0…1/3 — переход Formant (NaiveSpeechSynth) → Phoneme (SAM) → LPC (фонемы);
/// MORPH — фонема/гласная, TIMBRE — регистр/сдвиг формант. OUT — речь, AUX — возбуждение.
final class SpeechEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private var naiveSpeechSynth = NaiveSpeechSynth()
    private var samSpeechSynth = SAMSpeechSynth()
    private let lpcSpeechSynthController: LPCSpeechSynthController
    private let tempBuffer0: UnsafeMutablePointer<Float>
    private let tempBuffer1: UnsafeMutablePointer<Float>

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        lpcSpeechSynthController = LPCSpeechSynthController(random: random)
        tempBuffer0 = plaitsAllocate(kMaxBlockSize)
        tempBuffer1 = plaitsAllocate(kMaxBlockSize)
    }

    deinit {
        tempBuffer0.deallocate()
        tempBuffer1.deallocate()
    }

    func reset() {}

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0 = r.noteToFrequency(parameters.note)

        // Слов нет: выше LPC (group 2) не идём.
        let group = min(parameters.harmonics * 6, 2)

        // Переход между тремя моделями: naive, SAM, LPC.
        alreadyEnveloped = false

        var blend = group
        if group <= 1 {
            naiveSpeechSynth.render(r, parameters.trigger == triggerRisingEdge, f0, parameters.morph,
                                    parameters.timbre, aux, out, size)
        } else {
            lpcSpeechSynthController.render(r, trigger: parameters.trigger & triggerRisingEdge != 0, f0, 0, 0,
                                            parameters.morph, parameters.timbre, 1, aux, out, size)
            blend = 2 - blend
        }

        samSpeechSynth.render(r, parameters.trigger == triggerRisingEdge, f0, parameters.morph, parameters.timbre,
                              tempBuffer0, tempBuffer1, size)

        blend *= blend * (3 - 2 * blend)
        blend *= blend * (3 - 2 * blend)
        for i in 0..<size {
            aux[i] += (tempBuffer0[i] - aux[i]) * blend
            out[i] += (tempBuffer1[i] - out[i]) * blend
        }
    }
}
