import Foundation

// Полоса MID или SIDE в EqUnit (S7a) — как в EqChain веба: между кодированием L/R → M/S и обратно. Вход · 0,5
// (GainNode), M = l + r, S = l − r; фильтруется только свой канал, другой проходит как есть; обратно L = M + S,
// R = M − S — всё в Float, как узлы Web Audio. Фильтр полосы — моно-узел: автоматизация продвигается один раз на
// квант 128 отсчётов (у стерео-узла — каждым каналом), поэтому сглаживание идёт обычным ходом. Состояние фильтра —
// место L полосы (канал 0).
// Особенность Chromium (замерено): в первом кванте новой цепочки фильтр полосы SIDE получает тишину (у MID и STEREO
// так не бывает) — бока в этом кванте обнуляются до фильтра.

extension EqUnit {
    func runMsBand(_ c: Int, _ i: Int, _ n: Int, _ old: Bool) {
        let stages = nst[i]
        let side = msm[i] == 2
        let k = i - c * EqUnit.bands
        let cp = co + i * 5
        let laneStride = 2 * EqUnit.bands * EqUnit.bandState
        let s0 = st + (c * EqUnit.bands + k) * EqUnit.bandState
        let mf = EqUnit.maxFrames
        // L/R → M/S.
        var lane = 0
        while lane < lanes {
            if let (l, r) = signal(lane, old) {
                let m = midBuf + lane * mf
                let sd = sideBuf + lane * mf
                var j = 0
                while j < n {
                    let hl: Float = l[j] * 0.5
                    let hr: Float = r[j] * 0.5
                    m[j] = hl + hr
                    sd[j] = hl + (-hr)
                    j += 1
                }
            }
            lane += 1
        }
        if side && !old && fadePos == 0 {
            let q = Swift.min(EqUnit.quantum, n)
            lane = 0
            while lane < lanes {
                if live[lane] != 0 { (sideBuf + lane * mf).update(repeating: 0, count: q) }
                lane += 1
            }
        }
        var a = 0
        while a < n {
            let w0 = Swift.min(EqUnit.quantum, n - a)
            if moving[i] == 0 {
                lane = 0
                while lane < lanes {
                    if live[lane] != 0 {
                        let x = (side ? sideBuf : midBuf) + lane * mf + a
                        let z = s0 + lane * laneStride
                        var s = 0
                        while s < stages {
                            EqUnit.biquad(x, w0, cp, z + s * 8)
                            s += 1
                        }
                    }
                    lane += 1
                }
                a += w0
                continue
            }
            // Моно-узел: один отрезок траектории на квант.
            let e0 = el[i]
            el[i] += EqUnit.quantum
            fresh[i] = 0
            let dl = ramp
            coeffsAt(i, Double(e0), cp)
            var j = 0
            while j < w0 {
                let w = Swift.min(EqUnit.sub, w0 - j)
                coeffsAt(i, Double(e0 + j + w), dl)
                let inv: Double = 1 / Double(w)
                var t = 0
                while t < 5 {
                    dl[t] = (dl[t] - cp[t]) * inv
                    t += 1
                }
                lane = 0
                while lane < lanes {
                    if live[lane] != 0 {
                        let x = (side ? sideBuf : midBuf) + lane * mf + a + j
                        let z = s0 + lane * laneStride
                        var s = 0
                        while s < stages {
                            EqUnit.biquadRamp(x, w, cp, dl, z + s * 8)
                            s += 1
                        }
                    }
                    lane += 1
                }
                t = 0
                while t < 5 {
                    cp[t] += dl[t] * Double(w)
                    t += 1
                }
                j += w
            }
            if Double(el[i]) * decay < -16.2 {
                moving[i] = 0
                EqCoeffs.coeffs(kind[i], tf[i], tg[i], tq[i], sr, cp)
            }
            a += w0
        }
        // M/S → L/R.
        lane = 0
        while lane < lanes {
            if let (l, r) = signal(lane, old) {
                let m = midBuf + lane * mf
                let sd = sideBuf + lane * mf
                var j = 0
                while j < n {
                    l[j] = m[j] + sd[j]
                    r[j] = m[j] + (-sd[j])
                    j += 1
                }
            }
            lane += 1
        }
    }
}
