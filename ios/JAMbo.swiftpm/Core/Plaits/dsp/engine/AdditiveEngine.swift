// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/additive_engine.h, .cc.

let kHarmonicBatchSize = 12
let kNumHarmonics = 36
let kNumHarmonicOscillators = 3

/// Движок 4 (ADDITIVE). OUT — 24 гармоники подряд, AUX — 8 «органных» (1, 2, 3, 4, 6, 8, 10, 12);
/// центр спектра — TIMBRE, крутизна — MORPH, «горбы» — HARMONICS.
final class AdditiveEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let harmonicOscillator0 = HarmonicOscillator(numHarmonics: kHarmonicBatchSize)
    private let harmonicOscillator1 = HarmonicOscillator(numHarmonics: kHarmonicBatchSize)
    private let harmonicOscillator2 = HarmonicOscillator(numHarmonics: kHarmonicBatchSize)
    private let amplitudes: UnsafeMutablePointer<Float>

    init(resources: PlaitsResources) {
        self.resources = resources
        amplitudes = plaitsAllocate(kNumHarmonics)
    }

    deinit { amplitudes.deallocate() }

    func reset() {
        amplitudes.update(repeating: 0, count: kNumHarmonics)
    }

    /// Индекс гармоники: integer_harmonics — i, organ_harmonics — 0, 1, 2, 3, 5, 7, 9, 11.
    @inline(__always) private func organHarmonic(_ i: Int) -> Int {
        i < 4 ? i : 2 * i - 3
    }

    private func updateAmplitudes(_ centroid: Float, _ slope: Float, _ bumps: Float,
                                  _ amps: UnsafeMutablePointer<Float>, organ: Bool, _ numHarmonics: Int) {
        let r = resources
        let n = Float(numHarmonics) - 1
        let margin = (1 / slope - 1) / (1 + bumps)
        let center = centroid * (n + margin) - 0.5 * margin

        var sum: Float = 0.001

        for i in 0..<numHarmonics {
            let order = abs(Float(i) - center) * slope
            var gain = 1 - order
            gain += abs(gain)
            gain *= gain

            let b = 0.25 + order * bumps
            let bumpFactor = 1 + r.sine(b)

            gain *= bumpFactor
            gain *= gain
            gain *= gain

            let j = organ ? organHarmonic(i) : i

            // Не настоящий ФНЧ из-за нормировки, но в оригинале эта строка «абсолютно необходима».
            onePole(&amps[j], gain, 0.001)
            sum += amps[j]
        }

        sum = 1 / sum

        for i in 0..<numHarmonics {
            amps[organ ? organHarmonic(i) : i] *= sum
        }
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let f0 = r.noteToFrequency(parameters.note)

        let centroid = parameters.timbre
        let rawBumps = parameters.harmonics
        let rawSlope = (1 - 0.6 * rawBumps) * parameters.morph
        let slope = 0.01 + 1.99 * rawSlope * rawSlope * rawSlope
        let bumps = 16 * rawBumps * rawBumps
        updateAmplitudes(centroid, slope, bumps, amplitudes, organ: false, 24)
        harmonicOscillator0.render(r, first: 1, f0, amplitudes, out, size)
        harmonicOscillator1.render(r, first: 13, f0, amplitudes + 12, out, size)

        updateAmplitudes(centroid, slope, bumps, amplitudes + 24, organ: true, 8)
        harmonicOscillator2.render(r, first: 1, f0, amplitudes + 24, aux, size)
    }
}
