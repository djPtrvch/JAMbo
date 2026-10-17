// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/fm_engine.h, .cc.

/// Движок 2 (FM): два синусных оператора с обратной связью (MORPH), отношение частот — HARMONICS
/// (квантованное), индекс — TIMBRE; передискретизация 4×. AUX — суб-октава, модулированная несущей.
final class FMEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private var carrierPhase: UInt32 = 0
    private var modulatorPhase: UInt32 = 0
    private var subPhase: UInt32 = 0
    private var previousCarrierFrequency: Float
    private var previousModulatorFrequency: Float
    private var previousAmount: Float = 0
    private var previousFeedback: Float = 0
    private var previousSample: Float = 0
    // В Init оригинала не задаются; память wasm и BufferAllocator — нули.
    private var subFir: Float = 0
    private var carrierFir: Float = 0

    init(resources: PlaitsResources) {
        self.resources = resources
        previousCarrierFrequency = resources.a0
        previousModulatorFrequency = resources.a0
    }

    func reset() {}

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        // Передискретизация 4×.
        let note = parameters.note - 24

        let ratio = stmInterpolate(r.lutFmFrequencyQuantizer, parameters.harmonics, 128)

        let modulatorNote = note + ratio
        var targetModulatorFrequency = r.noteToFrequency(modulatorNote)
        constrain(&targetModulatorFrequency, 0, 0.5)

        // Меньший индекс FM на высоких нотах — против наложения спектров.
        var hfTaming = 1 - (modulatorNote - 72) * 0.025
        constrain(&hfTaming, 0, 1)
        hfTaming *= hfTaming

        var carrierFrequency = ParameterInterpolator(previousCarrierFrequency, r.noteToFrequency(note), size)
        var modulatorFrequency = ParameterInterpolator(previousModulatorFrequency, targetModulatorFrequency, size)
        var amountModulation = ParameterInterpolator(
            previousAmount, 2 * parameters.timbre * parameters.timbre * hfTaming, size)
        var feedbackModulation = ParameterInterpolator(previousFeedback, 2 * parameters.morph - 1, size)

        var carrierDownsampler = Downsampler(carrierFir, r.lut4xDownsamplerFir)
        var subDownsampler = Downsampler(subFir, r.lut4xDownsamplerFir)

        let maxUInt32: Float = 4294967296.0
        for i in 0..<size {
            let amount = amountModulation.next()
            let feedback = feedbackModulation.next()
            let phaseFeedback: Float = feedback < 0 ? 0.5 * feedback * feedback : 0
            let carrierIncrement = stmU32(maxUInt32 * carrierFrequency.next())
            let modFrequency = modulatorFrequency.next()

            for j in 0..<kOversampling {
                modulatorPhase &+= stmU32(maxUInt32 * modFrequency * (1 + previousSample * phaseFeedback))
                carrierPhase &+= carrierIncrement
                subPhase &+= carrierIncrement >> 1
                let modulatorFb: Float = feedback > 0 ? 0.25 * feedback * feedback : 0
                let modulator = r.sinePM(modulatorPhase, modulatorFb * previousSample)
                let carrier = r.sinePM(carrierPhase, amount * modulator)
                let sub = r.sinePM(subPhase, amount * carrier * 0.25)
                onePole(&previousSample, carrier, 0.05)
                carrierDownsampler.accumulate(j, carrier)
                subDownsampler.accumulate(j, sub)
            }

            out[i] = carrierDownsampler.read()
            aux[i] = subDownsampler.read()
        }
        previousCarrierFrequency = carrierFrequency.value
        previousModulatorFrequency = modulatorFrequency.value
        previousAmount = amountModulation.value
        previousFeedback = feedbackModulation.value
        carrierFir = carrierDownsampler.head
        subFir = subDownsampler.head
    }
}
