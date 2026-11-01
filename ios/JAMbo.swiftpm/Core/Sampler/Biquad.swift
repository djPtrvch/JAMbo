import Foundation

/// Фильтр голоса как BiquadFilterNode веба (формулы спецификации Web Audio): lowpass и highpass с Q в dB.
/// Ручка Filter: влево — LP (20 кГц → 30 Гц), вправо — HP (20 Гц → 10 кГц), в центре — LP на 20 кГц
/// (как в вебе: фильтр остаётся в цепочке). Resonance: Q = 0.7 + reso/100·18 (dB).
public struct Biquad {
    public var b0: Float = 1
    public var b1: Float = 0
    public var b2: Float = 0
    public var a1: Float = 0
    public var a2: Float = 0

    public init() {}

    /// type: −1 LP, 1 HP; hz — частота среза; qDb — Q в dB.
    public mutating func set(type: Int, hz: Double, qDb: Double, sampleRate: Double) {
        let f: Double = Swift.min(hz, sampleRate * 0.5 * 0.999)
        let w0: Double = 2 * Double.pi * f / sampleRate
        let c: Double = cos(w0)
        let alpha: Double = sin(w0) / (2 * pow(10, qDb / 20))
        let a0: Double = 1 + alpha
        if type > 0 {
            b0 = Float((1 + c) / 2 / a0)
            b1 = Float(-(1 + c) / a0)
        } else {
            b0 = Float((1 - c) / 2 / a0)
            b1 = Float((1 - c) / a0)
        }
        b2 = b0
        a1 = Float(-2 * c / a0)
        a2 = Float((1 - alpha) / a0)
    }

    /// Ручка Filter и Resonance → тип, частота, Q (dB).
    public static func knob(_ v: Double, reso: Double) -> (type: Int, hz: Double, q: Double) {
        let f = Fmt.filterFreq(v)
        let q: Double = 0.7 + reso / 100 * 18
        if f.type == 0 { return (-1, 20000, q) }
        return (f.type, f.hz, q)
    }

    /// Фильтр звучащего голоса на кусок (k — доля сглаживания): частота плавно идёт к цели. true — скачок: смена
    /// HP ↔ LP (выкл. — LP 20 кГц) или частота дальше, чем в 4 раза; проезд частоты через низы даёт всплеск, поэтому
    /// голос за fadeTime переводит выход на сухой сигнал, ставит фильтр сразу на цель и возвращает выход на фильтр.
    @inline(__always)
    public static func glide(_ type: inout Int, _ hz: inout Double, _ tt: Int, _ th: Double, _ k: Double) -> Bool {
        if tt != type { return true }
        let r: Double = th / Swift.max(1, hz)
        if r > 4 || r < 0.25 { return true }
        hz += (th - hz) * k
        return false
    }

    /// Переход выхода фильтра на сухой сигнал и обратно при скачке (секунды на каждый).
    public static let fadeTime: Double = 0.02

    /// Уход с HP на сухой сигнал (HP → выкл. или LP): возвращается низ хвоста (бочка — 50 Hz) — за 20 мс он
    /// поднимается толчком («тук» на видео 2.11), поэтому медленнее.
    public static let fadeHpTime: Double = 0.08

    /// Доля фильтра в выходе по ходу перехода g (0…1) — S-кривая: у линейной на краях излом, на громком низком хвосте
    /// (бочка после HP → выкл.) он слышен щелчком.
    @inline(__always)
    public static func mix(_ g: Float) -> Float { g * g * (3 - 2 * g) }
}
