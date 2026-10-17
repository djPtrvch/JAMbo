// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/engine/wavetable_engine.h, .cc.

private let kNumBanks = 4
private let kNumWavesPerBank = 64
private let kNumWaves = 192
private let kTableSize = 128
private let kTableSizeF: Float = 128

@inline(__always) private func wtClamp(_ xIn: Float, _ amount: Float) -> Float {
    var x = xIn - 0.5
    x *= amount
    constrain(&x, -0.5, 0.5)
    x += 0.5
    return x
}

/// Движок 5 (WAVETABLE): 4 банка 8×8 волн; X — TIMBRE, Y — MORPH, банк — HARMONICS (половина — с квантованием
/// координат). Банк 4 — волны 0–191 вперемешку (w·101 mod 192), своих волн нет. AUX — OUT, огрублённый до 5 бит.
final class WavetableEngine: PlaitsEngine {
    var postProcessing = PostProcessingSettings()

    private let resources: PlaitsResources
    private var phase: Float = 0
    private var xPreLp: Float = 0
    private var yPreLp: Float = 0
    private var zPreLp: Float = 0
    private var xLp: Float = 0
    private var yLp: Float = 0
    private var zLp: Float = 0
    private var previousX: Float = 0
    private var previousY: Float = 0
    private var previousZ: Float = 0
    private var previousF0: Float
    /// (банк, X, Y) → смещение волны в wav_integrated_waves. В оригинале буфер на 64 указателя, а пишется 256
    /// (выход за край буфера); здесь — 256.
    private let waveMap: UnsafeMutablePointer<Int>
    private var diffOut = Differentiator()

    init(resources: PlaitsResources) {
        self.resources = resources
        previousF0 = resources.a0
        waveMap = UnsafeMutablePointer<Int>.allocate(capacity: kNumBanks * kNumWavesPerBank)
        waveMap.initialize(repeating: 0, count: kNumBanks * kNumWavesPerBank)
        loadUserData()
    }

    deinit { waveMap.deallocate() }

    func reset() {}

    /// LoadUserData(nullptr): своих волн нет.
    func loadUserData() {
        for bank in 0..<kNumBanks {
            for wave in 0..<kNumWavesPerBank {
                let i = bank * kNumWavesPerBank + wave
                var w = i
                if bank == kNumBanks - 1 {
                    w = w * 101 % kNumWaves
                }
                waveMap[i] = w * (kTableSize + 4)
            }
        }
    }


    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool) {
        let f0Target = resources.noteToFrequency(parameters.note)

        onePole(&xPreLp, parameters.timbre * 6.9999, 0.2)
        onePole(&yPreLp, parameters.morph * 6.9999, 0.2)
        onePole(&zPreLp, parameters.harmonics * 6.9999, 0.05)

        let x = xPreLp
        let y = yPreLp
        let z = zPreLp

        let quantization = min(max(z - 3, 0), 1)
        let lpCoefficient = min(max(2 * f0Target * (4 - 3 * quantization), 0.01), 0.1)

        let xIntegral = stmInt(x)
        var xFractional = x - Float(xIntegral)
        let yIntegral = stmInt(y)
        var yFractional = y - Float(yIntegral)
        let zIntegral = stmInt(z)
        var zFractional = z - Float(zIntegral)

        xFractional += quantization * (wtClamp(xFractional, 16) - xFractional)
        yFractional += quantization * (wtClamp(yFractional, 16) - yFractional)
        zFractional += quantization * (wtClamp(zFractional, 16) - zFractional)

        var xModulation = ParameterInterpolator(previousX, Float(xIntegral) + xFractional, size)
        var yModulation = ParameterInterpolator(previousY, Float(yIntegral) + yFractional, size)
        var zModulation = ParameterInterpolator(previousZ, Float(zIntegral) + zFractional, size)
        var f0Modulation = ParameterInterpolator(previousF0, f0Target, size)

        // Состояние — в локальных переменных, чтение волн — без вызова метода (в отладочной сборке, Playgrounds,
        // вызовы и обращения к свойствам класса на каждом отсчёте дороже арифметики).
        let waves = resources.wavIntegratedWavesF
        let map = waveMap
        var xLp = self.xLp, yLp = self.yLp, zLp = self.zLp, phase = self.phase
        var diffOut = self.diffOut
        @_transparent func readWave(_ x: Int, _ y: Int, _ z: Int, _ phaseIntegral: Int, _ phaseFractional: Float) -> Float {
            interpolateWaveHermite(waves + map[x + y * 8 + z * kNumWavesPerBank], phaseIntegral, phaseFractional)
        }
        var i = 0
        while i < size {
            defer { i += 1 }
            let f0 = f0Modulation.next()

            let gain = (1 / (f0 * 131072)) * (0.95 - f0)
            let cutoff = min(kTableSizeF * f0, 1)

            onePole(&xLp, xModulation.next(), lpCoefficient)
            onePole(&yLp, yModulation.next(), lpCoefficient)
            onePole(&zLp, zModulation.next(), lpCoefficient)

            let xi = stmInt(xLp)
            let xf = xLp - Float(xi)
            let yi = stmInt(yLp)
            let yf = yLp - Float(yi)
            let zi = stmInt(zLp)
            let zf = zLp - Float(zi)

            phase += f0
            if phase >= 1 { phase -= 1 }

            let p = phase * kTableSizeF
            let pIntegral = stmInt(p)
            let pFractional = p - Float(pIntegral)

            let x0 = xi, x1 = xi + 1
            let y0 = yi, y1 = yi + 1
            var z0 = zi, z1 = zi + 1
            if z0 >= 4 { z0 = 7 - z0 }
            if z1 >= 4 { z1 = 7 - z1 }

            let x0y0z0 = readWave(x0, y0, z0, pIntegral, pFractional)
            let x1y0z0 = readWave(x1, y0, z0, pIntegral, pFractional)
            let xy0z0 = x0y0z0 + (x1y0z0 - x0y0z0) * xf

            let x0y1z0 = readWave(x0, y1, z0, pIntegral, pFractional)
            let x1y1z0 = readWave(x1, y1, z0, pIntegral, pFractional)
            let xy1z0 = x0y1z0 + (x1y1z0 - x0y1z0) * xf

            let xyz0 = xy0z0 + (xy1z0 - xy0z0) * yf

            let x0y0z1 = readWave(x0, y0, z1, pIntegral, pFractional)
            let x1y0z1 = readWave(x1, y0, z1, pIntegral, pFractional)
            let xy0z1 = x0y0z1 + (x1y0z1 - x0y0z1) * xf

            let x0y1z1 = readWave(x0, y1, z1, pIntegral, pFractional)
            let x1y1z1 = readWave(x1, y1, z1, pIntegral, pFractional)
            let xy1z1 = x0y1z1 + (x1y1z1 - x0y1z1) * xf

            let xyz1 = xy0z1 + (xy1z1 - xy0z1) * yf

            var mix = xyz0 + (xyz1 - xyz0) * zf
            mix = diffOut.process(cutoff, mix) * gain
            out[i] = mix
            aux[i] = Float(stmInt(mix * 32)) / 32
        }
        self.xLp = xLp
        self.yLp = yLp
        self.zLp = zLp
        self.phase = phase
        self.diffOut = diffOut
        previousX = xModulation.value
        previousY = yModulation.value
        previousZ = zModulation.value
        previousF0 = f0Modulation.value
    }
}
