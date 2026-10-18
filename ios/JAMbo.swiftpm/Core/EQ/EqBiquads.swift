import Foundation

// Ступени биквада EqUnit (Direct Form I, как Biquad::Process в Blink/WebKit): с постоянными коэффициентами,
// с линейно меняющимися и с коэффициентами на каждый отсчёт (динамическая полоса).

extension EqUnit {
    /// Одна ступень (Direct Form I, как Biquad::Process): x — Float, y и состояние — Double, выход — Float.
    @inline(__always)
    static func biquad(_ x: UnsafeMutablePointer<Float>, _ n: Int, _ c: UnsafeMutablePointer<Double>,
                       _ z: UnsafeMutablePointer<Double>) {
        let b0 = c[0], b1 = c[1], b2 = c[2], a1 = c[3], a2 = c[4]
        var x1 = z[0], x2 = z[1], y1 = z[2], y2 = z[3]
        var i = 0
        while i < n {
            let xi = Double(x[i])
            let y: Double = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x[i] = Float(y)
            x2 = x1
            x1 = xi
            y2 = y1
            y1 = y
            i += 1
        }
        z[0] = x1
        z[1] = x2
        z[2] = y1
        z[3] = y2
    }

    /// Ступень с коэффициентами, которые меняются линейно: в отсчёте k — c + dc·k.
    @inline(__always)
    static func biquadRamp(_ x: UnsafeMutablePointer<Float>, _ n: Int, _ c: UnsafeMutablePointer<Double>,
                           _ dc: UnsafeMutablePointer<Double>, _ z: UnsafeMutablePointer<Double>) {
        var b0 = c[0], b1 = c[1], b2 = c[2], a1 = c[3], a2 = c[4]
        let d0 = dc[0], d1 = dc[1], d2 = dc[2], d3 = dc[3], d4 = dc[4]
        var x1 = z[0], x2 = z[1], y1 = z[2], y2 = z[3]
        var i = 0
        while i < n {
            let xi = Double(x[i])
            let y: Double = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x[i] = Float(y)
            x2 = x1
            x1 = xi
            y2 = y1
            y1 = y
            b0 += d0
            b1 += d1
            b2 += d2
            a1 += d3
            a2 += d4
            i += 1
        }
        z[0] = x1
        z[1] = x2
        z[2] = y1
        z[3] = y2
    }

    /// Ступень с коэффициентами на каждый отсчёт: в отсчёте k — c[5k…5k+4].
    @inline(__always)
    static func biquadVar(_ x: UnsafeMutablePointer<Float>, _ n: Int, _ c: UnsafeMutablePointer<Double>,
                          _ z: UnsafeMutablePointer<Double>) {
        var x1 = z[0], x2 = z[1], y1 = z[2], y2 = z[3]
        var i = 0
        var o = 0
        while i < n {
            let xi = Double(x[i])
            let y: Double = c[o] * xi + c[o + 1] * x1 + c[o + 2] * x2 - c[o + 3] * y1 - c[o + 4] * y2
            x[i] = Float(y)
            x2 = x1
            x1 = xi
            y2 = y1
            y1 = y
            i += 1
            o += 5
        }
        z[0] = x1
        z[1] = x2
        z[2] = y1
        z[3] = y2
    }
}
