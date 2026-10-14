import Foundation

// Определение высоты сэмпла при загрузке (YIN по нескольким окнам, как audio/pitch.ts веба) — только для индикации:
// сэмпл всегда звучит в исходной высоте на C3. Шумные и ударные звуки без ясной высоты — nil.

public enum PitchDetect {
    static let minHz: Double = 40
    static let maxHz: Double = 1500
    static let window = 2048
    static let threshold: Float = 0.15

    /// MIDI-нота сэмпла или nil.
    public static func root(_ s: SampleData) -> Int? {
        // Моно с прореживанием до ~24 кГц.
        let step = 2
        let rate: Double = AudioCore.sampleRate / Double(step)
        let n = s.frames / step
        if n < window * 2 { return nil }
        var data = [Float](repeating: 0, count: n)
        let k: Float = s.channels == 2 ? 0.5 : 1
        for i in 0..<n {
            data[i] = s.channels == 2 ? (s.left[i * step] + s.right[i * step]) * k : s.left[i * step]
        }
        var peakAt = 0
        var peak: Float = 0
        let scan = Swift.min(n, Int(rate * 0.3))
        for i in 0..<scan where abs(data[i]) > peak {
            peak = abs(data[i])
            peakAt = i
        }
        if peak < 1e-4 { return nil }
        let from = Swift.min(peakAt + Int(rate * 0.02), n - window * 2)
        let to = Swift.min(n - window * 2, from + Int(rate * 1.5))
        var notes: [Int] = []
        for w in 0..<8 {
            let start = from + (to - from) * w / 8
            var e: Float = 0
            for i in 0..<window { e = Swift.max(e, abs(data[start + i])) }
            if e < peak * 0.05 { continue }
            if let hz = yin(data, start, rate) {
                notes.append(Int((69 + 12 * log2(hz / 440)).rounded()))
            }
        }
        if notes.count < 3 { return nil }
        var count: [Int: Int] = [:]
        for v in notes { count[v, default: 0] += 1 }
        // Самая частая нота (при равенстве — первая встреченная, как сортировка веба); нет согласия — высоты нет.
        var best = notes[0]
        var votes = 0
        for v in notes where count[v]! > votes {
            best = v
            votes = count[v]!
        }
        let need = (notes.count + 1) / 2
        return votes >= need ? Swift.min(108, Swift.max(12, best)) : nil
    }

    static func yin(_ x: [Float], _ start: Int, _ rate: Double) -> Double? {
        let minTau = Int(rate / maxHz)
        let maxTau = Swift.min(Int(rate / minHz), window - 1)
        var d = [Float](repeating: 0, count: maxTau + 2)
        for tau in 1...maxTau {
            var s: Float = 0
            for i in 0..<(window - maxTau) {
                let diff = x[start + i] - x[start + i + tau]
                s += diff * diff
            }
            d[tau] = s
        }
        var sum: Float = 0
        for tau in 1...maxTau {
            sum += d[tau]
            let cmnd: Float = sum > 0 ? d[tau] * Float(tau) / sum : 1
            if tau >= minTau && cmnd < threshold {
                var t = tau
                while t + 1 <= maxTau && d[t + 1] < d[t] { t += 1 }
                let a = d[t - 1]
                let b = d[t]
                let c = t + 1 <= maxTau ? d[t + 1] : d[t]
                let den = 2 * (a - 2 * b + c)
                let shift: Float = den != 0 ? (a - c) / den : 0
                return rate / (Double(t) + (shift.isFinite ? Double(shift) : 0))
            }
        }
        return nil
    }
}
