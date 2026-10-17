// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/harmonic_oscillator.h.

/// Пачка гармоник (рекурсия Чебышёва) от first-й; амплитуды сглаживаются за блок.
/// Шаблон num_harmonics — число гармоник при создании; буферы выделяются в init (не в колбэке).
final class HarmonicOscillator {
    let numHarmonics: Int
    private var phase: Float = 0
    private var frequency: Float = 0
    private let amplitude: UnsafeMutablePointer<Float>
    // ParameterInterpolator am[num_harmonics]: текущее значение и шаг каждой гармоники.
    private let amValue: UnsafeMutablePointer<Float>
    private let amIncrement: UnsafeMutablePointer<Float>

    init(numHarmonics: Int) {
        self.numHarmonics = numHarmonics
        amplitude = plaitsAllocate(numHarmonics)
        amValue = plaitsAllocate(numHarmonics)
        amIncrement = plaitsAllocate(numHarmonics)
    }

    deinit {
        amplitude.deallocate()
        amValue.deallocate()
        amIncrement.deallocate()
    }

    /// Render<first_harmonic_index>: при first = 1 out перезаписывается, иначе — прибавляется.
    @inline(__always)
    func render(_ r: PlaitsResources, first firstHarmonicIndex: Int, _ frequencyIn: Float,
                _ amplitudes: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequencyTarget = frequencyIn
        if frequencyTarget >= 0.5 { frequencyTarget = 0.5 }

        var fm = ParameterInterpolator(frequency, frequencyTarget, size)

        for i in 0..<numHarmonics {
            var f = frequencyTarget * Float(firstHarmonicIndex + i)
            if f >= 0.5 { f = 0.5 }
            amValue[i] = amplitude[i]
            amIncrement[i] = (amplitudes[i] * (1 - f * 2) - amplitude[i]) / Float(size)
        }

        // Циклы — while, фаза — локально: в отладочной сборке (Playgrounds) итератор for-in по гармоникам на каждом
        // отсчёте и обращения к свойству класса дороже арифметики.
        let n = numHarmonics
        let amV = amValue, amI = amIncrement
        var phase = self.phase
        var s = 0
        while s < size {
            defer { s += 1 }
            phase += fm.next()
            if phase >= 1 { phase -= 1 }
            let twoX = 2 * r.sineNoWrap(phase)
            var previous: Float
            var current: Float
            if firstHarmonicIndex == 1 {
                previous = 1
                current = twoX * 0.5
            } else {
                let k = Float(firstHarmonicIndex)
                previous = r.sine(phase * (k - 1) + 0.25)
                current = r.sine(phase * k)
            }

            var sum: Float = 0
            var i = 0
            while i < n {
                amV[i] += amI[i]
                sum += amV[i] * current
                let temp = current
                current = twoX * current - previous
                previous = temp
                i += 1
            }
            if firstHarmonicIndex == 1 {
                out[s] = sum
            } else {
                out[s] += sum
            }
        }

        self.phase = phase
        frequency = fm.value
        for i in 0..<numHarmonics { amplitude[i] = amValue[i] }
    }
}
