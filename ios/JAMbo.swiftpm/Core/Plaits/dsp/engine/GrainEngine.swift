// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/grain_engine.h, .cc (VOSIM в оригинале отключён).

/// Движок 3 (GRAIN). OUT — две гранулы (форманты TIMBRE и TIMBRE·HARMONICS), форма несущей — MORPH;
/// AUX — ZOscillator (форманта со сбросом).
final class GrainEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private var grainlet0 = GrainletOscillator()
    private var grainlet1 = GrainletOscillator()
    private var zOscillator = ZOscillator()
    private var dcBlocker0 = OnePole()
    private var dcBlocker1 = OnePole()

    init(resources: PlaitsResources) {
        self.resources = resources
        dcBlocker0.initialize()
        dcBlocker1.initialize()
    }

    func reset() {}

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let root = parameters.note
        let f0 = r.noteToFrequency(root)

        let f1 = r.noteToFrequency(24 + 84 * parameters.timbre)
        let ratio = r.semitonesToRatio(-24 + 48 * parameters.harmonics)
        let carrierBleed: Float = parameters.harmonics < 0.5 ? 1 - 2 * parameters.harmonics : 0
        let carrierBleedFixed = carrierBleed * (2 - carrierBleed)
        let carrierShape = 0.33 + (parameters.morph - 0.33) * max(1 - f0 * 24, 0)

        grainlet0.render(r, f0, f1, carrierShape, carrierBleedFixed, out, size)
        grainlet1.render(r, f0, f1 * ratio, carrierShape, carrierBleedFixed, aux, size)
        dcBlocker0.setF(0.3 * f0, .dirty)
        for i in 0..<size {
            out[i] = dcBlocker0.process(out[i] + aux[i], .highPass)
        }

        let cutoff = r.noteToFrequency(root + 96 * parameters.timbre)
        zOscillator.render(r, f0, cutoff, parameters.morph, parameters.harmonics, aux, size)

        dcBlocker1.setF(0.3 * f0, .dirty)
        for i in 0..<size {
            aux[i] = dcBlocker1.process(aux[i], .highPass)
        }
    }
}
