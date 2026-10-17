// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/bass_drum_engine.h, .cc, snare_drum_engine.h, .cc, hi_hat_engine.h, .cc.

/// Движок 13 (KICK, Analog bass drum): OUT — бочка 808 с перегрузом, AUX — синтетическая (909-подобная).
/// HARMONICS — атака и перегруз, TIMBRE — яркость, MORPH — затухание.
final class BassDrumEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let random: StmRandom
    private var analogBassDrum = AnalogBassDrum()
    private var syntheticBassDrum = SyntheticBassDrum()
    private var overdrive = Overdrive()

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        analogBassDrum.initialize()
        syntheticBassDrum.initialize()
        overdrive.initialize()
    }

    func reset() {}

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0 = r.noteToFrequency(parameters.note)

        let attackFmAmount = min(parameters.harmonics * 4, 1)
        let selfFmAmount = max(min(parameters.harmonics * 4 - 1, 1), 0)
        let drive = max(parameters.harmonics * 2 - 1, 0) * max(1 - 16 * f0, 0)

        let sustain = (parameters.trigger & triggerUnpatched) != 0
        let trigger = (parameters.trigger & triggerRisingEdge) != 0

        analogBassDrum.render(r, sustain, trigger, parameters.accent, f0, parameters.timbre, parameters.morph,
                              attackFmAmount, selfFmAmount, out, size)

        overdrive.process(0.5 + 0.5 * drive, out, size)

        syntheticBassDrum.render(r, random, sustain, trigger, parameters.accent, f0, parameters.timbre,
                                 parameters.morph,
                                 sustain ? parameters.harmonics : 0.4 - 0.25 * parameters.morph * parameters.morph,
                                 min(parameters.harmonics * 2, 1), max(parameters.harmonics * 2 - 1, 0), aux, size)
    }
}

/// Движок 14 (SNARE, Analog snare): OUT — малый 808, AUX — синтетический (909-подобный).
/// HARMONICS — шум ↔ корпус, TIMBRE — баланс мод, MORPH — затухание.
final class SnareDrumEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let random: StmRandom
    private let analogSnareDrum = AnalogSnareDrum()
    private var syntheticSnareDrum = SyntheticSnareDrum()

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        analogSnareDrum.initialize()
        syntheticSnareDrum.initialize()
    }

    func reset() {}

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0 = r.noteToFrequency(parameters.note)
        let sustain = (parameters.trigger & triggerUnpatched) != 0
        let trigger = (parameters.trigger & triggerRisingEdge) != 0

        analogSnareDrum.render(r, random, sustain, trigger, parameters.accent, f0, parameters.timbre,
                               parameters.morph, parameters.harmonics, out, size)
        syntheticSnareDrum.render(r, random, sustain, trigger, parameters.accent, f0, parameters.timbre,
                                  parameters.morph, parameters.harmonics, aux, size)
    }
}

/// Движок 15 (HI-HAT, Analog hi-hat): OUT — 808 (квадраты), AUX — кольцевая модуляция (606).
/// HARMONICS — металл ↔ шум, TIMBRE — срез ФВЧ, MORPH — затухание.
final class HiHatEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let random: StmRandom
    private let hiHat1 = HiHat(ringMod: false)
    private let hiHat2 = HiHat(ringMod: true)
    private let tempBuffer: UnsafeMutablePointer<Float>

    init(resources: PlaitsResources, random: StmRandom) {
        self.resources = resources
        self.random = random
        tempBuffer = plaitsAllocate(kMaxBlockSize * 2)
    }

    deinit { tempBuffer.deallocate() }

    func reset() {}

    /// NoteToFrequency с порядком умножения, как в plaits.wasm (-ffast-math): (a0/4 · high) · low.
    /// Обычный a0/4 · (high · low) отличается в последнем бите — такт шума и квадраты сдвигаются на отсчёт.
    @inline(__always) private func hiHatNoteToFrequency(_ r: PlaitsResources, _ midiNote: Float) -> Float {
        var note = midiNote - 9
        constrain(&note, -128, 127)
        let pitch = note + 128
        let i = stmInt(pitch)
        let f = pitch - Float(i)
        return (r.a0 * 0.25 * r.lutPitchRatioHigh[i]) * r.lutPitchRatioLow[stmInt(f * 256)]
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0 = hiHatNoteToFrequency(r, parameters.note)
        let sustain = (parameters.trigger & triggerUnpatched) != 0
        let trigger = (parameters.trigger & triggerRisingEdge) != 0

        hiHat1.render(r, random, sustain, trigger, parameters.accent, f0, parameters.timbre, parameters.morph,
                      parameters.harmonics, tempBuffer, tempBuffer + size, out, size)
        hiHat2.render(r, random, sustain, trigger, parameters.accent, f0, parameters.timbre, parameters.morph,
                      parameters.harmonics, tempBuffer, tempBuffer + size, aux, size)
    }
}
