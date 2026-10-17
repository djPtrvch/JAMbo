// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/resources.h и stmlib/dsp/units.cc: таблицы — из Resources/plaits (выгружены ios/tools/plaits/export_tables.sh).
import Foundation

/// Указатели на таблицы (живут всё время работы приложения). Структура копируется в движки — без ARC в колбэке.
public struct PlaitsResources {
    let lutSine: UnsafePointer<Float>
    let lutFmFrequencyQuantizer: UnsafePointer<Float>
    let lutFold: UnsafePointer<Float>
    let lutFold2: UnsafePointer<Float>
    let lutStiffness: UnsafePointer<Float>
    let lutSvfShift: UnsafePointer<Float>
    let lut4xDownsamplerFir: UnsafePointer<Float>
    let lutPitchRatioHigh: UnsafePointer<Float>
    let lutPitchRatioLow: UnsafePointer<Float>
    /// lookup_table_i16_table: inverse tan, inverse sin, linear, bump, double bump, double bump.
    let lookupTableI16: UnsafePointer<UnsafePointer<Int16>>
    let wavIntegratedWaves: UnsafePointer<Int16>
    let lutLpcExcitationPulse: UnsafePointer<Int8>
    /// Фонемы LPC: 12 значений на кадр (energy, period, k0…k9).
    let lpcPhonemes: UnsafePointer<Int16>
    let lpcPhonemeCount: Int
    /// a0 для NoteToFrequency: в приложении — plaitsA0 (48 кГц, без сдвига ноты); тесты ставят a0 веба
    /// (по kCorrectedSampleRate) и сдвигают ноту, чтобы сверять с эталонами почти бит в бит.
    var a0: Float = plaitsA0

    /// Таблицы из папки dir; nil — нет какого-то файла или длина не та.
    public static func load(dir: URL) -> PlaitsResources? {
        func load<T>(_ name: String, _ count: Int, _ type: T.Type) -> UnsafePointer<T>? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  data.count == count * MemoryLayout<T>.stride else { return nil }
            // Запас по краям: Plaits читает соседний отсчёт за краем (index + 1, Эрмит — index − 1 … + 2).
            let pad = 16
            let raw = UnsafeMutableRawPointer.allocate(byteCount: (count + 2 * pad) * MemoryLayout<T>.stride, alignment: 16)
            raw.initializeMemory(as: UInt8.self, repeating: 0, count: (count + 2 * pad) * MemoryLayout<T>.stride)
            let base = raw + pad * MemoryLayout<T>.stride
            data.withUnsafeBytes { base.copyMemory(from: $0.baseAddress!, byteCount: data.count) }
            return UnsafePointer(base.assumingMemoryBound(to: T.self))
        }
        guard let sine = load("lut_sine.f32", 641, Float.self),
              let fmq = load("lut_fm_frequency_quantizer.f32", 130, Float.self),
              let fold = load("lut_fold.f32", 516, Float.self),
              let fold2 = load("lut_fold_2.f32", 516, Float.self),
              let stiffness = load("lut_stiffness.f32", 65, Float.self),
              let svf = load("lut_svf_shift.f32", 257, Float.self),
              let fir = load("lut_4x_downsampler_fir.f32", 4, Float.self),
              let high = load("lut_pitch_ratio_high.f32", 257, Float.self),
              let low = load("lut_pitch_ratio_low.f32", 257, Float.self),
              let tan = load("lut_ws_inverse_tan.i16", 257, Int16.self),
              let sin = load("lut_ws_inverse_sin.i16", 257, Int16.self),
              let lin = load("lut_ws_linear.i16", 257, Int16.self),
              let bump = load("lut_ws_bump.i16", 257, Int16.self),
              let dbump = load("lut_ws_double_bump.i16", 257, Int16.self),
              let waves = load("wav_integrated_waves.i16", 25344, Int16.self),
              let pulse = load("lut_lpc_excitation_pulse.i8", 640, Int8.self),
              let phonemes = load("lpc_phonemes.i16", 15 * 12, Int16.self) else { return nil }
        let table = UnsafeMutablePointer<UnsafePointer<Int16>>.allocate(capacity: 6)
        for (k, p) in [tan, sin, lin, bump, dbump, dbump].enumerated() { table[k] = p }
        return PlaitsResources(lutSine: sine, lutFmFrequencyQuantizer: fmq, lutFold: fold, lutFold2: fold2,
                               lutStiffness: stiffness, lutSvfShift: svf, lut4xDownsamplerFir: fir,
                               lutPitchRatioHigh: high, lutPitchRatioLow: low, lookupTableI16: UnsafePointer(table),
                               wavIntegratedWaves: waves, lutLpcExcitationPulse: pulse, lpcPhonemes: phonemes,
                               lpcPhonemeCount: 15)
    }

    // MARK: stmlib/dsp/units.h

    @inline(__always) func semitonesToRatio(_ semitones: Float) -> Float {
        let pitch = semitones + 128
        let i = stmInt(pitch)
        let f = pitch - Float(i)
        return lutPitchRatioHigh[i] * lutPitchRatioLow[stmInt(f * 256)]
    }

    // MARK: plaits/dsp/oscillator/sine_oscillator.h (функции)

    @inline(__always) func sine(_ phase: Float) -> Float { stmInterpolateWrap(lutSine, phase, 512) }

    @inline(__always) func sineNoWrap(_ phase: Float) -> Float { stmInterpolate(lutSine, phase, 512) }

    @inline(__always) func sinePM(_ phase: UInt32, _ pm: Float) -> Float {
        let scale: Float = 4294967296.0 / 64
        let p = phase &+ (stmU32((pm + 32) * scale) &* 64)
        let i = Int(p >> 23)
        let f = Float(p << 9) / 4294967296.0
        let a = lutSine[i], b = lutSine[i + 1]
        return a + (b - a) * f
    }

    @inline(__always) func sineRaw(_ phase: UInt32) -> Float { lutSine[Int(phase >> 23)] }

    // MARK: plaits/dsp/engine/engine.h

    /// NoteToFrequency: MIDI-нота → частота в долях частоты дискретизации.
    @inline(__always) func noteToFrequency(_ midiNote: Float) -> Float {
        var note = midiNote - 9
        constrain(&note, -128, 127)
        return a0 * 0.25 * semitonesToRatio(note)
    }
}
