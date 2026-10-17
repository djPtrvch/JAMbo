// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/chords/chord_bank.h, .cc (без JON_CHORDS — как в сборке веба).

let kChordNumNotes = 4
let kChordNumVoices = 5
let kChordNumChords = 11

/// Аккорды, полутоны: OCT, 5, sus4, m, m7, m9, m11, 69, M9, M7, M.
private let chordBankChords: [Float] = [
    0.00, 0.01, 11.99, 12.00,
    0.00, 7.00, 7.01, 12.00,
    0.00, 5.00, 7.00, 12.00,
    0.00, 3.00, 7.00, 12.00,
    0.00, 3.00, 7.00, 10.00,
    0.00, 3.00, 10.00, 14.00,
    0.00, 3.00, 10.00, 17.00,
    0.00, 2.00, 9.00, 16.00,
    0.00, 4.00, 11.00, 14.00,
    0.00, 4.00, 7.00, 11.00,
    0.00, 4.00, 7.00, 12.00,
]

/// Банк аккордов: выбор с гистерезисом и обращения. Sort, sorted_ratio и num_notes оригинала движку CHORDS
/// не нужны (их читают движки engine2) — не перенесены.
final class ChordBank {
    private var chordIndexQuantizer = HysteresisQuantizer2()
    private let ratios: UnsafeMutablePointer<Float>
    /// Копия chordBankChords: reset() может идти из колбэка (смена движка), а глобальный массив
    /// инициализируется лениво при первом обращении.
    private let semitones: UnsafeMutablePointer<Float>

    init() {
        ratios = plaitsAllocate(kChordNumChords * kChordNumNotes)
        semitones = plaitsAllocate(kChordNumChords * kChordNumNotes)
        for i in 0..<(kChordNumChords * kChordNumNotes) { semitones[i] = chordBankChords[i] }
        chordIndexQuantizer.initialize(kChordNumChords, 0.075, symmetric: false)
    }

    deinit {
        ratios.deallocate()
        semitones.deallocate()
    }

    /// Reset: отношения частот нот аккордов (SemitonesToRatio).
    func reset(_ r: PlaitsResources) {
        for i in 0..<(kChordNumChords * kChordNumNotes) {
            ratios[i] = r.semitonesToRatio(semitones[i])
        }
    }

    @inline(__always) func setChord(_ parameter: Float) {
        _ = chordIndexQuantizer.process(parameter * 1.02)
    }

    var chordIndex: Int { chordIndexQuantizer.quantizedValue }

    /// Обращение (0…1): отношения и громкости 5 голосов; маска — голоса, которые идут в AUX (основной тон).
    @inline(__always)
    func computeChordInversion(_ inversionIn: Float, _ outRatios: UnsafeMutablePointer<Float>,
                               _ amplitudes: UnsafeMutablePointer<Float>) -> Int {
        let baseRatio = ratios + chordIndex * kChordNumNotes
        let inversion = inversionIn * Float(kChordNumNotes * kChordNumVoices)
        let inversionIntegral = stmInt(inversion)
        let inversionFractional = inversion - Float(inversionIntegral)

        let numRotations = inversionIntegral / kChordNumNotes
        let rotatedNote = inversionIntegral % kChordNumNotes

        let kBaseGain: Float = 0.25

        var mask = 0
        for i in 0..<kChordNumNotes {
            let transposition = 0.25 * Float(1 << ((kChordNumNotes - 1 + inversionIntegral - i) / kChordNumNotes))
            let targetVoice = (i - numRotations + kChordNumVoices) % kChordNumVoices
            let previousVoice = (targetVoice - 1 + kChordNumVoices) % kChordNumVoices

            if i == rotatedNote {
                outRatios[targetVoice] = baseRatio[i] * transposition
                outRatios[previousVoice] = outRatios[targetVoice] * 2
                amplitudes[previousVoice] = kBaseGain * inversionFractional
                amplitudes[targetVoice] = kBaseGain * (1 - inversionFractional)
            } else if i < rotatedNote {
                outRatios[previousVoice] = baseRatio[i] * transposition
                amplitudes[previousVoice] = kBaseGain
            } else {
                outRatios[targetVoice] = baseRatio[i] * transposition
                amplitudes[targetVoice] = kBaseGain
            }

            if i == 0 {
                if i >= rotatedNote { mask |= 1 << targetVoice }
                if i <= rotatedNote { mask |= 1 << previousVoice }
            }
        }
        return mask
    }
}
