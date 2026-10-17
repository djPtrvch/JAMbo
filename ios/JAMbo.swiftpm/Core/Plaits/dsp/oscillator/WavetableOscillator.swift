// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/wavetable_oscillator.h: WavetableOscillator.

/// Генератор по набору интегрированных волн (переход между соседними — waveform). Параметры шаблона
/// wavetable_size, num_waves, approximate_scale, attenuate_high_frequencies — в init.
struct WavetableOscillator {
    let wavetableSize: Int
    let numWaves: Int
    let approximateScale: Bool
    let attenuateHighFrequencies: Bool

    private var phase: Float = 0
    private var frequency: Float = 0
    private var amplitude: Float = 0
    private var waveform: Float = 0
    private var lp: Float = 0
    private var differentiator = Differentiator()

    init(wavetableSize: Int, numWaves: Int, approximateScale: Bool = true, attenuateHighFrequencies: Bool = true) {
        self.wavetableSize = wavetableSize
        self.numWaves = numWaves
        self.approximateScale = approximateScale
        self.attenuateHighFrequencies = attenuateHighFrequencies
    }

    /// out — прибавляется.
    @inline(__always)
    mutating func render(_ frequencyIn: Float, _ amplitudeIn: Float, _ waveformIn: Float,
                         _ wavetable: UnsafePointer<UnsafePointer<Int16>>,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var frequencyTarget = frequencyIn
        constrain(&frequencyTarget, 0.0000001, kMaxFrequency)

        var amplitudeTarget = amplitudeIn
        if attenuateHighFrequencies { amplitudeTarget *= 1 - 2 * frequencyTarget }
        if approximateScale { amplitudeTarget *= 1 / (frequencyTarget * 131072) }

        var frequencyModulation = ParameterInterpolator(frequency, frequencyTarget, size)
        var amplitudeModulation = ParameterInterpolator(amplitude, amplitudeTarget, size)
        var waveformModulation = ParameterInterpolator(waveform, waveformIn * (Float(numWaves) - 1.0001), size)

        let tableSizeF = Float(wavetableSize)
        var lpState = lp
        var ph = phase
        for i in 0..<size {
            let f0 = frequencyModulation.next()
            let cutoff = min(tableSizeF * f0, 1)
            let scale: Float = approximateScale ? 1 : 1 / (f0 * 131072)

            ph += f0
            if ph >= 1 { ph -= 1 }

            let w = waveformModulation.next()
            let wIntegral = stmInt(w)
            let wFractional = w - Float(wIntegral)

            let p = ph * tableSizeF
            let pIntegral = stmInt(p)
            let pFractional = p - Float(pIntegral)

            let x0 = interpolateWave(wavetable[wIntegral], pIntegral, pFractional)
            let x1 = interpolateWave(wavetable[wIntegral + 1], pIntegral, pFractional)

            let s = differentiator.process(cutoff, (x0 + (x1 - x0) * wFractional) * scale)
            onePole(&lpState, s, cutoff)
            out[i] += amplitudeModulation.next() * lpState
        }
        lp = lpState
        phase = ph

        frequency = frequencyModulation.value
        amplitude = amplitudeModulation.value
        waveform = waveformModulation.value
    }
}
