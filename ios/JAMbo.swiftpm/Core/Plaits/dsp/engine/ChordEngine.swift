// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/chord_engine.h, .cc.

let kChordNumHarmonics = 3
private let kRegistrationTableSize = 8

private let chordFadePoint: [Float] = [0.55, 0.47, 0.49, 0.51, 0.53]

/// Регистры деления частоты (по 6 весов): Square, Saw, Saw + saw, Full saw, Full saw + square hybrid,
/// Saw + high square harmo, Square + high square harmo, Saw+square + high harmo.
private let chordRegistrations: [Float] = [
    0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
    1.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.5, 0.0, 0.5, 0.0, 0.0, 0.0,
    0.33, 0.0, 0.33, 0.0, 0.33, 0.0,
    0.33, 0.0, 0.0, 0.33, 0.0, 0.33,
    0.5, 0.0, 0.0, 0.0, 0.0, 0.5,
    0.0, 0.5, 0.0, 0.0, 0.0, 0.5,
    0.0, 0.1, 0.1, 0.0, 0.2, 0.6,
]

/// Волны таблицы (банк, ряд, столбец) в wav_integrated_waves.
private let chordWaves: [(Int, Int, Int)] = [
    (2, 6, 1), (2, 6, 6), (2, 6, 4), (0, 6, 0), (0, 6, 1), (0, 6, 2), (0, 6, 7), (2, 4, 7),
    (2, 4, 6), (2, 4, 5), (2, 4, 4), (2, 4, 3), (2, 4, 2), (2, 4, 1), (2, 4, 0),
]

/// Движок 6 (CHORDS): аккорд (HARMONICS) из 5 голосов; MORPH — от органного деления частоты к волнам,
/// TIMBRE — обращение. AUX — основной тон аккорда.
final class ChordEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private let chords = ChordBank()
    private var morphLp: Float = 0
    private var timbreLp: Float = 0

    // Таблицы и рабочие буферы — указатели (колбэк не читает Swift-массивы).
    private let fadePoint: UnsafeMutablePointer<Float>
    private let registrations: UnsafeMutablePointer<Float>
    private let wavetable: UnsafeMutablePointer<UnsafePointer<Float>>
    private let harmonics: UnsafeMutablePointer<Float>
    private let noteAmplitudes: UnsafeMutablePointer<Float>
    private let ratios: UnsafeMutablePointer<Float>
    private let divideDown: UnsafeMutablePointer<StringSynthOscillator>
    private let wavetableVoices: UnsafeMutablePointer<WavetableOscillator>

    init(resources: PlaitsResources) {
        self.resources = resources
        fadePoint = plaitsAllocate(kChordNumVoices)
        for i in 0..<kChordNumVoices { fadePoint[i] = chordFadePoint[i] }
        registrations = plaitsAllocate(kRegistrationTableSize * kChordNumHarmonics * 2)
        for i in 0..<chordRegistrations.count { registrations[i] = chordRegistrations[i] }
        wavetable = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: chordWaves.count)
        for (i, w) in chordWaves.enumerated() {
            wavetable[i] = resources.wavIntegratedWavesF + (w.0 * 64 + w.1 * 8 + w.2) * 132
        }
        harmonics = plaitsAllocate(kChordNumHarmonics * 2 + 2)
        noteAmplitudes = plaitsAllocate(kChordNumVoices)
        ratios = plaitsAllocate(kChordNumVoices)
        divideDown = UnsafeMutablePointer<StringSynthOscillator>.allocate(capacity: kChordNumVoices)
        divideDown.initialize(repeating: StringSynthOscillator(), count: kChordNumVoices)
        wavetableVoices = UnsafeMutablePointer<WavetableOscillator>.allocate(capacity: kChordNumVoices)
        wavetableVoices.initialize(repeating: WavetableOscillator(wavetableSize: 128, numWaves: 15),
                                   count: kChordNumVoices)
    }

    deinit {
        fadePoint.deallocate()
        registrations.deallocate()
        wavetable.deallocate()
        harmonics.deallocate()
        noteAmplitudes.deallocate()
        ratios.deallocate()
        divideDown.deinitialize(count: kChordNumVoices)
        divideDown.deallocate()
        wavetableVoices.deinitialize(count: kChordNumVoices)
        wavetableVoices.deallocate()
    }

    func reset() {
        chords.reset(resources)
    }

    @inline(__always) private func computeRegistration(_ registrationIn: Float, _ amplitudes: UnsafeMutablePointer<Float>) {
        let registration = registrationIn * (Float(kRegistrationTableSize) - 1.001)
        let integral = stmInt(registration)
        let fractional = registration - Float(integral)
        let n = kChordNumHarmonics * 2
        for i in 0..<n {
            let a = registrations[integral * n + i]
            let b = registrations[(integral + 1) * n + i]
            amplitudes[i] = a + (b - a) * fractional
        }
    }

    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        onePole(&morphLp, parameters.morph, 0.1)
        onePole(&timbreLp, parameters.timbre, 0.1)

        chords.setChord(parameters.harmonics)

        let registration = max(1 - morphLp * 2.15, 0)
        computeRegistration(registration, harmonics)
        harmonics[kChordNumHarmonics * 2] = 0

        let auxNoteMask = chords.computeChordInversion(timbreLp, ratios, noteAmplitudes)

        out.update(repeating: 0, count: size)
        aux.update(repeating: 0, count: size)

        let f0 = resources.noteToFrequency(parameters.note) * 0.998
        let waveform = max((morphLp - 0.535) * 2.15, 0)

        for note in 0..<kChordNumVoices {
            var wavetableAmount = 50 * (morphLp - fadePoint[note])
            constrain(&wavetableAmount, 0, 1)

            var divideDownAmount = 1 - wavetableAmount
            let destination = (1 << note) & auxNoteMask != 0 ? aux : out

            let noteF0 = f0 * ratios[note]
            var divideDownGain = 4 - noteF0 * 32
            constrain(&divideDownGain, 0, 1)
            divideDownAmount *= divideDownGain

            if wavetableAmount != 0 {
                wavetableVoices[note].render(noteF0 * 1.004, noteAmplitudes[note] * wavetableAmount, waveform,
                                             wavetable, destination, size)
            }

            if divideDownAmount != 0 {
                divideDown[note].render(noteF0, harmonics, noteAmplitudes[note] * divideDownAmount,
                                        destination, size)
            }
        }

        for i in 0..<size {
            out[i] += aux[i]
            aux[i] *= 3
        }
    }
}
