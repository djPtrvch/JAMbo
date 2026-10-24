import Foundation

/// Таблица показа встроенной таблицы WTABLE (только окно синта, звук не меняется): 256 кадров по 256 отсчётов
/// (до 127 гармоник), каждый кадр — к пику 1.0, как в звуке. У звуковой таблицы 64 кадра: между ними форма
/// смешивается, и крутой фронт (PWM) на иконке прыгает; здесь кадров больше — POSITION двигает форму плавно
/// (решение пользователя).
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
                re[n] = sp.re[f][n]
                im[n] = sp.im[f][n]
                re[size - n] = sp.re[f][n]
                im[size - n] = -sp.im[f][n]
            }
            WtTable.fft(&re, &im, inverse: true)
            var pk: Double = 0
            for k in 0..<size { pk = Swift.max(pk, abs(re[k])) }
            let g: Double = pk > 0 ? 1 / pk : 1
            for k in 0..<size { out[f * size + k] = Float(re[k] * g) }
        }
        return WtDisplay(data: out)
    }
}
