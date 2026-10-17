// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/virtual_analog_engine.h, .cc (VA_VARIANT 2 — как в сборке оригинала).

/// Интервалы расстройки второго генератора (HARMONICS), полутоны.
private let vaIntervals: (Float, Float, Float, Float, Float) = (0, 7.01, 12.01, 19.01, 24.01)

@inline(__always) private func vaInterval(_ i: Int) -> Float {
    switch i {
    case 0: return vaIntervals.0
    case 1: return vaIntervals.1
    case 2: return vaIntervals.2
    case 3: return vaIntervals.3
    default: return vaIntervals.4
    }
}

@inline(__always) private func vaSquash(_ x: Float) -> Float { x * x * (3 - 2 * x) }

/// Движок 0 (VA). OUT — квадрат с ШИМ (TIMBRE) + пила с вырезом/треугольник (MORPH), второй расстроен
/// HARMONICS; AUX — два VariableShape с самосинхронизацией (TIMBRE).
final class VirtualAnalogEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private var primary = VariableShapeOscillator()
    private var auxiliary = VariableShapeOscillator()
    private var sync = VariableShapeOscillator()
    private var variableSaw = VariableSawOscillator()

    private var auxiliaryAmount: Float = 0
    private var xmodAmount: Float = 0
    private let tempBuffer: UnsafeMutablePointer<Float>

    init(resources: PlaitsResources) {
        self.resources = resources
        auxiliary.setMasterPhase(0.25)
        tempBuffer = plaitsAllocate(kMaxBlockSize)
    }

    deinit { tempBuffer.deallocate() }

    func reset() {}

    @inline(__always) private func computeDetuning(_ detuneIn: Float) -> Float {
        var detune = 2.05 * detuneIn - 1.025
        constrain(&detune, -1, 1)

        let sign: Float = detune < 0 ? -1 : 1
        detune = detune * sign * 3.9999
        let integral = stmInt(detune)
        let fractional = detune - Float(integral)

        let a = vaInterval(integral)
        let b = vaInterval(integral + 1)
        return (a + (b - a) * vaSquash(vaSquash(fractional))) * sign
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let r = resources
        let syncAmount = parameters.timbre * parameters.timbre
        let auxiliaryDetune = computeDetuning(parameters.harmonics)
        let primaryF = r.noteToFrequency(parameters.note)
        let auxiliaryF = r.noteToFrequency(parameters.note + auxiliaryDetune)
        let primarySyncF = r.noteToFrequency(parameters.note + syncAmount * 48)
        let auxiliarySyncF = r.noteToFrequency(parameters.note + auxiliaryDetune + syncAmount * 48)

        var shape = parameters.morph * 1.5
        constrain(&shape, 0, 1)

        var pw = 0.5 + (parameters.morph - 0.66) * 1.46
        constrain(&pw, 0.5, 0.995)

        // «Монстр-синхронизация» — в AUX.
        primary.render(primaryF, primarySyncF, pw, shape, out, size)
        auxiliary.render(auxiliaryF, auxiliarySyncF, pw, shape, aux, size)
        for i in 0..<size {
            aux[i] = (aux[i] - out[i]) * 0.5
        }

        // Двойной varishape — в OUT.
        var squarePw = 1.3 * parameters.timbre - 0.15
        constrain(&squarePw, 0.005, 0.5)

        let squareSyncRatio: Float = parameters.timbre < 0.5
            ? 0
            : (parameters.timbre - 0.5) * (parameters.timbre - 0.5) * 4 * 48

        let squareGain = min(parameters.timbre * 8, 1)

        var sawPw: Float = parameters.morph < 0.5
            ? parameters.morph + 0.5
            : 1 - (parameters.morph - 0.5) * 2
        sawPw *= 1.1
        constrain(&sawPw, 0.005, 1)

        var sawShape = 10 - 21 * parameters.morph
        constrain(&sawShape, 0, 1)

        var sawGain = 8 * (1 - parameters.morph)
        constrain(&sawGain, 0.02, 1)

        let squareSyncF = r.noteToFrequency(parameters.note + squareSyncRatio)

        sync.render(primaryF, squareSyncF, squarePw, 1, tempBuffer, size)
        variableSaw.render(auxiliaryF, sawPw, sawShape, out, size)

        let norm = 1 / max(squareGain, sawGain)

        var squareGainModulation = ParameterInterpolator(auxiliaryAmount, squareGain * 0.3 * norm, size)
        var sawGainModulation = ParameterInterpolator(xmodAmount, sawGain * 0.5 * norm, size)

        for i in 0..<size {
            out[i] = out[i] * sawGainModulation.next() + squareGainModulation.next() * tempBuffer[i]
        }
        auxiliaryAmount = squareGainModulation.value
        xmodAmount = sawGainModulation.value
    }
}
