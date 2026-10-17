// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/string_engine.h, .cc, modal_engine.h, .cc.

let kNumStrings = 3

/// Движок 11 (STRING, Inharmonic string): 3 струны по кругу (новая нота — следующая струна, прежние дозвучивают).
/// HARMONICS — нелинейность, TIMBRE — яркость, MORPH — затухание. AUX — возбуждение.
final class StringEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let voice0: StringVoice, voice1: StringVoice, voice2: StringVoice
    private let f0 = plaitsAllocate(kNumStrings)
    private var f0Delay = DelayLine(16)
    private var activeString = kNumStrings - 1
    private let tempBuffer: UnsafeMutablePointer<Float>
    private let resources: PlaitsResources

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        tempBuffer = plaitsAllocate(kMaxBlockSize)
        voice0 = StringVoice(resources: resources, random: random)
        voice1 = StringVoice(resources: resources, random: random)
        voice2 = StringVoice(resources: resources, random: random)
        for i in 0..<kNumStrings { f0[i] = 0.01 }
        activeString = kNumStrings - 1
        f0Delay.reset()
    }

    deinit {
        f0.deallocate()
        f0Delay.deallocate()
        tempBuffer.deallocate()
    }

    func reset() {
        f0Delay.reset()
        voice0.reset()
        voice1.reset()
        voice2.reset()
    }

    @inline(__always) private func stringVoice(_ i: Int) -> StringVoice {
        i == 0 ? voice0 : (i == 1 ? voice1 : voice2)
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let rising = (parameters.trigger & triggerRisingEdge) != 0
        let unpatched = (parameters.trigger & triggerUnpatched) != 0
        if rising {
            // Частота прежней струны — с небольшой задержкой (нота могла смениться чуть позже триггера).
            f0[activeString] = f0Delay.read(14)
            activeString = (activeString + 1) % kNumStrings
        }

        let note = resources.noteToFrequency(parameters.note)
        f0[activeString] = note
        f0Delay.write(note)

        for i in 0..<size {
            out[i] = 0
            aux[i] = 0
        }

        for i in 0..<kNumStrings {
            stringVoice(i).render(unpatched && i == activeString, rising && i == activeString, parameters.accent,
                                  f0[i], parameters.harmonics, parameters.timbre * parameters.timbre,
                                  parameters.morph, tempBuffer, out, aux, size)
        }
    }
}

/// Движок 12 (MODAL, Modal resonator): модальный резонатор (HARMONICS — материал, TIMBRE — яркость,
/// MORPH — затухание). AUX — возбуждение.
final class ModalEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let voice: ModalVoice
    private let tempBuffer: UnsafeMutablePointer<Float>
    private var harmonicsLp: Float = 0

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        voice = ModalVoice(resources: resources, random: random)
        tempBuffer = plaitsAllocate(kMaxBlockSize)
        harmonicsLp = 0
        reset()
    }

    deinit { tempBuffer.deallocate() }

    func reset() {
        voice.initialize()
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        for i in 0..<size {
            out[i] = 0
            aux[i] = 0
        }

        onePole(&harmonicsLp, parameters.harmonics, 0.01)

        voice.render((parameters.trigger & triggerUnpatched) != 0, (parameters.trigger & triggerRisingEdge) != 0,
                     parameters.accent, resources.noteToFrequency(parameters.note), harmonicsLp,
                     parameters.timbre, parameters.morph, tempBuffer, out, aux, size)
    }
}
