import Foundation

/// Таблица показа встроенной таблицы WTABLE (только окно синта, звук не меняется): 256 кадров по 256 отсчётов
/// (до 127 гармоник), каждый кадр — к пику 1.0, как в звуке. У звуковой таблицы 64 кадра: между ними форма
/// смешивается, и крутой фронт (PWM) на иконке прыгает; здесь кадров больше — POSITION двигает форму плавно
/// (решение пользователя). Гармоники — с окном Ланцоша (σ-фактор): без «звона» Гиббса у фронта, иначе его пик
/// попадает между точками рисования, и верх волны дёргается при смене POSITION.
public final class WtDisplay: @unchecked Sendable {
    public static let frames = 256
    public static let size = 256
    public let data: [Float]

    init(data: [Float]) {
        self.data = data
    }

    public static func builtin(_ name: String) -> WtDisplay {
        let fr: Int = WtDisplay.frames
        let size: Int = WtDisplay.size
        let lim: Int = size / 2 - 1
        let sp = WtTable.builtinSpectra(name, frames: fr, limit: lim)
        var out = [Float](repeating: 0, count: fr * size)
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for f in 0..<fr {
            for k in 0..<size {
                re[k] = 0
                im[k] = 0
            }
            for n in 1...lim {
                let x: Double = Double.pi * Double(n) / Double(lim + 1)
                let sigma: Double = sin(x) / x
                re[n] = sp.re[f][n] * sigma
                im[n] = sp.im[f][n] * sigma
                re[size - n] = re[n]
                im[size - n] = -im[n]
            }
            WtTable.fft(&re, &im, inverse: true)
            var pk: Double = 0
            for k in 0..<size { pk = Swift.max(pk, abs(re[k])) }
            let g: Double = pk > 0 ? 1 / pk : 1
            for k in 0..<size { out[f * size + k] = Float(re[k] * g) }
        }
        return WtDisplay(data: out)
    }

    /// Своя таблица — прямо из отсчётов WAV, без FFT (быстро даже в отладочной сборке): 256 кадров × 256 точек, между
    /// кадрами и отсчётами — линейно; без постоянной составляющей кадра; вся таблица к пику 1.0 (как звуковая).
    public static func user(_ samples: [Float], frameSize: Int) -> WtDisplay {
        let fr: Int = WtDisplay.frames
        let size: Int = WtDisplay.size
        let src: Int = Swift.max(1, Swift.min(WtWav.maxFrames, samples.count / frameSize))
        let n: Int = samples.count
        func at(_ f: Int, _ j: Int) -> Double {
            let k: Int = f * frameSize + j
            return k < n ? Double(samples[k]) : 0
        }
        var out = [Float](repeating: 0, count: fr * size)
        var row = [Double](repeating: 0, count: size)
        var peak: Double = 0
        for f in 0..<fr {
            let fpos: Double = src > 1 ? Double(f) / Double(fr - 1) * Double(src - 1) : 0
            let fa: Int = Swift.min(src - 1, Int(fpos.rounded(.down)))
            let fb: Int = Swift.min(src - 1, fa + 1)
            let ff: Double = fpos - Double(fa)
            var mean: Double = 0
            for k in 0..<size {
                let x: Double = Double(k) / Double(size) * Double(frameSize)
                let j: Int = Swift.min(frameSize - 1, Int(x.rounded(.down)))
                let j1: Int = (j + 1) % frameSize
                let fj: Double = x - Double(j)
                let va: Double = at(fa, j) + (at(fa, j1) - at(fa, j)) * fj
                let vb: Double = at(fb, j) + (at(fb, j1) - at(fb, j)) * fj
                row[k] = va + (vb - va) * ff
                mean += row[k]
            }
            mean /= Double(size)
            for k in 0..<size {
                let v: Double = row[k] - mean
                peak = Swift.max(peak, abs(v))
                out[f * size + k] = Float(v)
            }
        }
        if peak > 0 {
            let g: Float = Float(1 / peak)
            for k in 0..<out.count { out[k] *= g }
        }
        return WtDisplay(data: out)
    }
}
