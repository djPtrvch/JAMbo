// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/speech/lpc_speech_synth.h, .cc.

let kLPCOrder = 10
let kLPCSpeechSynthDefaultF0: Float = 100
private let kLutLpcExcitationPulseSize = 640

/// Кадр LPC (energy, period — u8; k0, k1 — масштаб 32768; k2…k9 — масштаб 128).
struct LPCFrame {
    var energy: Int = 0
    var period: Int = 0
    var k0: Int = 0, k1: Int = 0, k2: Int = 0, k3: Int = 0, k4: Int = 0
    var k5: Int = 0, k6: Int = 0, k7: Int = 0, k8: Int = 0, k9: Int = 0

    /// Кадр i таблицы фонем (12 значений Int16).
    init(_ table: UnsafePointer<Int16>, _ i: Int) {
        let p = table + i * 12
        energy = Int(p[0]); period = Int(p[1])
        k0 = Int(p[2]); k1 = Int(p[3]); k2 = Int(p[4]); k3 = Int(p[5]); k4 = Int(p[6])
        k5 = Int(p[7]); k6 = Int(p[8]); k7 = Int(p[9]); k8 = Int(p[10]); k9 = Int(p[11])
    }
}

/// Решётчатый фильтр LPC 10-го порядка с возбуждением импульсом (голос) или шумом.
final class LPCSpeechSynth {
    private var phase: Float = 0
    private(set) var frequency: Float = 0.0125
    private var noiseEnergy: Float = 0
    private var pulseEnergy: Float = 0
    private var nextSample: Float = 0
    private var excitationPulseSampleIndex = 0
    private let k: UnsafeMutablePointer<Float>
    private let s: UnsafeMutablePointer<Float>
    private let random: StmRandom

    init(random: StmRandom) {
        self.random = random
        k = plaitsAllocate(kLPCOrder)
        s = plaitsAllocate(kLPCOrder + 1)
    }

    deinit {
        k.deallocate()
        s.deallocate()
    }

    @inline(__always)
    func render(_ r: PlaitsResources, _ prosodyAmount: Float, _ pitchShift: Float,
                _ excitation: UnsafeMutablePointer<Float>, _ output: UnsafeMutablePointer<Float>, _ size: Int) {
        let baseF0 = kLPCSpeechSynthDefaultF0 / 8000
        let d = frequency - baseF0
        var f = (baseF0 + d * prosodyAmount) * pitchShift
        constrain(&f, 0, 0.5)

        let pulse = r.lutLpcExcitationPulse
        var next = nextSample
        for i in 0..<size {
            phase += f

            var thisSample = next
            next = 0

            if phase >= 1 {
                phase -= 1
                let resetTime = phase / f
                let resetSample = stmInt(32 * resetTime)

                var discontinuity: Float = 0
                if excitationPulseSampleIndex < kLutLpcExcitationPulseSize {
                    excitationPulseSampleIndex -= resetSample
                    discontinuity = Float(pulse[excitationPulseSampleIndex]) / 128 * pulseEnergy
                }

                thisSample += -discontinuity * thisBlepSample(resetTime)
                next += -discontinuity * nextBlepSample(resetTime)

                excitationPulseSampleIndex = resetSample
            }

            var e10: Float = random.getSample() > 0 ? noiseEnergy : -noiseEnergy
            if excitationPulseSampleIndex < kLutLpcExcitationPulseSize {
                next += Float(pulse[excitationPulseSampleIndex]) / 128 * pulseEnergy
                excitationPulseSampleIndex += 32
            }
            e10 += thisSample
            e10 *= 1.5

            let e9 = e10 - k[9] * s[9]
            let e8 = e9 - k[8] * s[8]
            let e7 = e8 - k[7] * s[7]
            let e6 = e7 - k[6] * s[6]
            let e5 = e6 - k[5] * s[5]
            let e4 = e5 - k[4] * s[4]
            let e3 = e4 - k[3] * s[3]
            let e2 = e3 - k[2] * s[2]
            let e1 = e2 - k[1] * s[1]
            var e0 = e1 - k[0] * s[0]

            constrain(&e0, -2, 2)

            s[9] = s[8] + k[8] * e8
            s[8] = s[7] + k[7] * e7
            s[7] = s[6] + k[6] * e6
            s[6] = s[5] + k[5] * e5
            s[5] = s[4] + k[4] * e4
            s[4] = s[3] + k[3] * e3
            s[3] = s[2] + k[2] * e2
            s[2] = s[1] + k[1] * e1
            s[1] = s[0] + k[0] * e0
            s[0] = e0

            excitation[i] = e10
            output[i] = e0
        }
        nextSample = next
    }

    /// PlayFrame(frames, frame, interpolate): кадры — таблица фонем (count штук).
    @inline(__always)
    func playFrame(_ frames: UnsafePointer<Int16>, _ count: Int, _ frame: Float, _ interpolate: Bool) {
        let frameIntegral = stmInt(frame)
        let frameFractional = interpolate ? frame - Float(frameIntegral) : 0
        // В оригинале за последним кадром читается следующий (за краем таблицы) с весом 0 — здесь тот же кадр.
        let second = min(frameIntegral + 1, count - 1)
        playFrame(LPCFrame(frames, frameIntegral), LPCFrame(frames, second), frameFractional)
    }

    @inline(__always) private func blend(_ a: Int, _ b: Int, _ scale: Float, _ t: Float) -> Float {
        let aF = Float(a) / scale
        let bF = Float(b) / scale
        return aF + (bF - aF) * t
    }

    @inline(__always) private func playFrame(_ f1: LPCFrame, _ f2: LPCFrame, _ t: Float) {
        let frequency1 = f1.period == 0 ? frequency : 1 / Float(f1.period)
        let frequency2 = f2.period == 0 ? frequency : 1 / Float(f2.period)
        frequency = frequency1 + (frequency2 - frequency1) * t

        let energy1 = Float(f1.energy) / 256
        let energy2 = Float(f2.energy) / 256
        let noiseEnergy1: Float = f1.period == 0 ? energy1 : 0
        let noiseEnergy2: Float = f2.period == 0 ? energy2 : 0
        noiseEnergy = noiseEnergy1 + (noiseEnergy2 - noiseEnergy1) * t

        let pulseEnergy1: Float = f1.period != 0 ? energy1 : 0
        let pulseEnergy2: Float = f2.period != 0 ? energy2 : 0
        pulseEnergy = pulseEnergy1 + (pulseEnergy2 - pulseEnergy1) * t

        k[0] = blend(f1.k0, f2.k0, 32768, t)
        k[1] = blend(f1.k1, f2.k1, 32768, t)
        k[2] = blend(f1.k2, f2.k2, 128, t)
        k[3] = blend(f1.k3, f2.k3, 128, t)
        k[4] = blend(f1.k4, f2.k4, 128, t)
        k[5] = blend(f1.k5, f2.k5, 128, t)
        k[6] = blend(f1.k6, f2.k6, 128, t)
        k[7] = blend(f1.k7, f2.k7, 128, t)
        k[8] = blend(f1.k8, f2.k8, 128, t)
        k[9] = blend(f1.k9, f2.k9, 128, t)
    }
}
