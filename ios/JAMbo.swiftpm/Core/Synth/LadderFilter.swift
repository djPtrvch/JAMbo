import Foundation

/// LADDER (9.11, решение пользователя): лестничный фильтр 24 dB в духе Moog — только у SUB (FilterType.ladder).
/// Четыре звена TPT (обратная связь без задержки), насыщение tanh на входе вместе с обратной связью. GRIT SUB в этом
/// режиме — перегруз входа (0 → +24 dB, как Multidrive Subsequent 37; tanh движка тогда выключен); выход нормирован:
/// пик прежний, громкость с GRIT растёт умеренно (~+5 dB на пиле). Resonance 0…100 % — обратная связь k 0…3,9
/// (до самовозбуждения), низ подтянут на (1 + k/2). Частота — ручка Filter (на ней −12 dB, спад 24 dB/окт).
/// Колбэк: состояние создано заранее; кусок голоса — один вызов, цикл по отсчётам — внутри файла.
public final class LadderFilter {
    /// Состояние звеньев: 4 на слот.
    let st: UnsafeMutablePointer<Double>
    let slots: Int

    public init(slots: Int) {
        self.slots = slots
        st = UnsafeMutablePointer<Double>.allocate(capacity: slots * 4)
        st.initialize(repeating: 0, count: slots * 4)
    }

    deinit { st.deallocate() }

    @inline(__always)
    public func reset(_ v: Int) {
        let b: Int = v * 4
        st[b] = 0
        st[b + 1] = 0
        st[b + 2] = 0
        st[b + 3] = 0
    }

    /// Доля звена TPT для частоты hz.
    @inline(__always)
    static func gain(_ hz: Double, _ sr: Double) -> Double {
        let f: Double = Swift.min(hz, sr * 0.45)
        let g: Double = tan(Double.pi * f / sr)
        return g / (1 + g)
    }

    /// Кусок голоса v на месте: buf ← сухой + (лестница − сухой)·доля; доля fq → fq + dfq·m, частота — от hz0 к hz1
    /// по отсчётам; qDb — Q голоса (dB, 0,7…18,7 = Resonance 0…100 %), grit — 0…1.
    public func run(_ v: Int, _ buf: UnsafeMutablePointer<Float>, _ m: Int, hz0: Double, hz1: Double, qDb: Double,
                    grit: Double, sr: Double, fq: Float, dfq: Float) {
        let reso: Double = Swift.min(1, Swift.max(0, (qDb - 0.7) / 18))
        let k: Double = 3.9 * reso
        let gd: Double = pow(10, 1.2 * Swift.min(1, Swift.max(0, grit)))
        let norm: Double = tanh(0.58) / tanh(0.58 * gd) * pow(gd, -0.2) * (1 + 0.5 * k)
        var gc: Double = LadderFilter.gain(hz0, sr)
        let g1: Double = LadderFilter.gain(hz1, sr)
        let dG: Double = (g1 - gc) / Double(Swift.max(1, m))
        let b: Int = v * 4
        var s1: Double = st[b], s2: Double = st[b + 1], s3: Double = st[b + 2], s4: Double = st[b + 3]
        var w: Double = Double(fq)
        let dw: Double = Double(dfq)
        var j: Int = 0
        while j < m {
            gc += dG
            let g: Double = gc
            let be: Double = 1 - g
            let g2: Double = g * g
            let g3: Double = g2 * g
            let g4: Double = g3 * g
            let dry: Double = Double(buf[j])
            let xin: Double = dry * gd
            // Выход четвёртого звена при линейной обратной связи — по нему вход с насыщением.
            let sum: Double = g3 * be * s1 + g2 * be * s2 + g * be * s3 + be * s4
            let y4: Double = (g4 * xin + sum) / (1 + k * g4)
            var u: Double = tanh(xin - k * y4)
            var vv: Double = (u - s1) * g
            u = vv + s1
            s1 = u + vv
            vv = (u - s2) * g
            u = vv + s2
            s2 = u + vv
            vv = (u - s3) * g
            u = vv + s3
            s3 = u + vv
            vv = (u - s4) * g
            u = vv + s4
            s4 = u + vv
            w += dw
            buf[j] = Float(dry + (u * norm - dry) * w)
            j += 1
        }
        // Денормалы на затухании — в ноль.
        if Swift.abs(s1) < 1e-20 { s1 = 0 }
        if Swift.abs(s2) < 1e-20 { s2 = 0 }
        if Swift.abs(s3) < 1e-20 { s3 = 0 }
        if Swift.abs(s4) < 1e-20 { s4 = 0 }
        st[b] = s1
        st[b + 1] = s2
        st[b + 2] = s3
        st[b + 3] = s4
    }
}
