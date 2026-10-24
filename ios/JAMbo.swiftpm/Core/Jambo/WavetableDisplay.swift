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
}
