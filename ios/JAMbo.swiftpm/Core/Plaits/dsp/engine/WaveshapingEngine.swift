// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/waveshaping_engine.h, .cc.

/// Tame: насколько можно открыть вейвшейпер, чтобы обертоны порядка order не ушли за Найквиста.
@inline(__always) private func wsTame(_ f0In: Float, _ harmonics: Float, _ order: Float) -> Float {
    let f0 = f0In * harmonics
    let maxF = 0.5 / order
    var maxAmount = 1 - (f0 - maxF) / (0.5 - maxF)
    constrain(&maxAmount, 0, 1)
    return maxAmount * maxAmount * maxAmount
}

/// Движок 1 (WAVESHAPE). OUT — склон (MORPH) через вейвшейпер (HARMONICS) и складыватель (TIMBRE);
/// AUX — синус ↔ второй складыватель.
final class WaveshapingEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private var slope = Oscillator()
    private var triangle = Oscillator()
    private var previousShape: Float = 0
    private var previousWavefolderGain: Float = 0
    private var previousOvertoneGain: Float = 0

    init(resources: PlaitsResources) {
        self.resources = resources
    }

    func reset() {}

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let root = parameters.note

        let f0 = r.noteToFrequency(root)
        let pw = parameters.morph * 0.45 + 0.5

        // Исходный сигнал — склон с ограниченной полосой.
        slope.render(.slope, f0, pw, out, size)
        triangle.render(.slope, f0, 0.5, aux, size)

        // Оценка богатства спектра: диапазон вейвшейпера сужается.
        let slopeK = 3 + abs(parameters.morph - 0.5) * 5
        let shapeAmount = abs(parameters.harmonics - 0.5) * 2
        let shapeAmountAttenuation = wsTame(f0, slopeK, 16)
        let wavefolderGain = parameters.timbre
        let wavefolderGainAttenuation = wsTame(f0, slopeK * (3 + shapeAmount * shapeAmountAttenuation * 5), 12)

        // Вейвшейпер и складыватель.
        var shapeModulation = ParameterInterpolator(
            previousShape, 0.5 + (parameters.harmonics - 0.5) * shapeAmountAttenuation, size)
        var wfGainModulation = ParameterInterpolator(
            previousWavefolderGain, 0.03 + 0.46 * wavefolderGain * wavefolderGainAttenuation, size)
        let overtoneGain = parameters.timbre * (2 - parameters.timbre)
        var overtoneGainModulation = ParameterInterpolator(
            previousOvertoneGain, overtoneGain * (2 - overtoneGain), size)

        let fold1 = r.lutFold + 1
        let fold2 = r.lutFold2 + 1
        for i in 0..<size {
            let shape = shapeModulation.next() * 3.9999
            let shapeIntegral = stmInt(shape)
            let shapeFractional = shape - Float(shapeIntegral)

            let shape1 = r.lookupTableI16[shapeIntegral]
            let shape2 = r.lookupTableI16[shapeIntegral + 1]

            let wsIndex = 127 * out[i] + 128
            var wsIntegral = stmInt(wsIndex)
            let wsFractional = wsIndex - Float(wsIntegral)
            wsIntegral &= 255

            let x0 = Float(shape1[wsIntegral]) / 32768
            let x1 = Float(shape1[wsIntegral + 1]) / 32768
            let x = x0 + (x1 - x0) * wsFractional

            let y0 = Float(shape2[wsIntegral]) / 32768
            let y1 = Float(shape2[wsIntegral + 1]) / 32768
            let y = y0 + (y1 - y0) * wsFractional

            let mix = x + (y - x) * shapeFractional
            let index = mix * wfGainModulation.next() + 0.5
            let fold = stmInterpolateHermite(fold1, index, 512)
            let foldTwo = -stmInterpolateHermite(fold2, index, 512)

            let sine = r.sine(aux[i] * 0.25 + 0.5)
            out[i] = fold
            aux[i] = sine + (foldTwo - sine) * overtoneGainModulation.next()
        }
        previousShape = shapeModulation.value
        previousWavefolderGain = wfGainModulation.value
        previousOvertoneGain = overtoneGainModulation.value
    }
}
