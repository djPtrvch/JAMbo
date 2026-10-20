import Foundation

// Delay — перенос public/delay-worklet.js 1:1: ленточный стерео-дилей, шина отдаёт только эхо (wet).
// Две кольцевые линии L и R (чтение — кубический Эрмит). Время L = TIME, R = TIME · (1 + o); время каждой линии
// скользит к цели (однополюсно, 80 мс, не быстрее 0,75 отсчёта на отсчёт) — смена TIME даёт питч-нырок без щелчков.
// SPREAD: до 50 % разносит время правой линии (o), дальше — перекрёстная связь c до классического ping-pong.
// Выход линий: HP 60 Гц → FILTER (LP и HP — SVF TPT, у центра подмешиваются плавно) → tanh(k·x)/k → в выход и
// в обратную связь. Модуляция «лента»: wow (случайное блуждание 0,5 Гц) и flutter (7 Гц), у каждой линии свои фазы.
// Параметры — k-rate (на блок): time (с), feedback (0…1), filter (−1…1), spread (0…1); FEEDBACK, FILTER, SPREAD
// сглаживаются за 20 мс. Состояние и расчёт — Double, как JS; линии — Float (Float32Array).
// Горячий цикл — по правилам отладочной сборки (ios/CLAUDE.md): состояние в локальных переменных, без вызовов
// из других файлов на отсчёте.

public final class FxDelay {
    // Константы (DELAY_CONST).
    static let loopHpHz: Double = 60
    static let satK: Double = 1.2
    static let wowHz: Double = 0.5
    static let wowMs: Double = 0.2
    static let flutterHz: Double = 7
    static let flutterMs: Double = 0.03
    static let glideMs: Double = 80
    static let glideMax: Double = 0.75
    static let smoothMs: Double = 20
    static let lpMaxHz: Double = 20000
    static let lpMinHz: Double = 500
    static let hpMinHz: Double = 20
    static let hpMaxHz: Double = 1500
    static let filterOff: Double = 0.02
    static let spreadMax: Double = 0.5
    static let tiny: Double = 1e-18

    let sr: Double
    let maxTime: Double
    let len: Int
    let mask: Int
    let lineL: UnsafeMutablePointer<Float>
    let lineR: UnsafeMutablePointer<Float>
    var w: Int = 0
    var dL: Double = 0
    var dR: Double = 0
    var started = false
    var fb: Double = 0.4
    var filter: Double = 0
    var spread: Double = 0
    // HP 60 Гц: коэффициенты и состояния [x1, x2, y1, y2] L и R.
    var kHp: (Double, Double, Double, Double, Double) = (1, 0, 0, 0, 0)
    var zHp: (Double, Double, Double, Double, Double, Double, Double, Double) = (0, 0, 0, 0, 0, 0, 0, 0)
    // FILTER: SVF — коэффициенты [a1, a2, a3] LP и HP, состояния [ic1, ic2] L и R.
    var cLp: (Double, Double, Double) = (0, 0, 0)
    var cHp: (Double, Double, Double) = (0, 0, 0)
    var sLp: (Double, Double, Double, Double) = (0, 0, 0, 0)
    var sHp: (Double, Double, Double, Double) = (0, 0, 0, 0)
    var wLp: Double = 0
    var wHp: Double = 0
    var fSig: Double = .nan
    // Модуляция: wow (фаза, цели A → B) и flutter (поворот sin/cos) по линиям.
    var rng: FxRandom
    var wowPh: (Double, Double) = (0, 0)
    var wowA: (Double, Double) = (0, 0)
    var wowB: (Double, Double) = (0, 0)
    let flR: Double
    let flI: Double
    var flS: (Double, Double) = (0, 0)
    var flC: (Double, Double) = (0, 0)

    /// maxTime — наибольшее время, с (1 такт при 40 BPM — 6 с); seed — генератор модуляции (как Math.random веба).
    public init(sampleRate: Double, maxTime: Double = 6, seed: UInt32) {
        sr = sampleRate
        self.maxTime = maxTime
        let need = Int((maxTime * (1 + FxDelay.spreadMax) * sampleRate
                        + ((FxDelay.wowMs + FxDelay.flutterMs) / 1000) * sampleRate + 8).rounded(.up))
        var p = 1
        while p < need { p <<= 1 }
        len = p
        mask = p - 1
        lineL = UnsafeMutablePointer<Float>.allocate(capacity: p)
        lineR = UnsafeMutablePointer<Float>.allocate(capacity: p)
        lineL.initialize(repeating: 0, count: p)
        lineR.initialize(repeating: 0, count: p)
        kHp = FxDelay.biquadHp(FxDelay.loopHpHz, sampleRate)
        rng = FxRandom(seed)
        wowPh = (rng.next(), rng.next())
        wowA = (rng.next() * 2 - 1, rng.next() * 2 - 1)
        wowB = (rng.next() * 2 - 1, rng.next() * 2 - 1)
        let fw: Double = 2 * Double.pi * FxDelay.flutterHz / sampleRate
        flR = cos(fw)
        flI = sin(fw)
        let p0: Double = rng.next() * 2 * Double.pi
        let p1: Double = rng.next() * 2 * Double.pi
        flS = (sin(p0), sin(p1))
        flC = (cos(p0), cos(p1))
    }

    deinit {
        lineL.deallocate()
        lineR.deallocate()
    }

    /// Биквад HP (RBJ, Q = 1/√2): [b0, b1, b2, a1, a2].
    static func biquadHp(_ f: Double, _ sr: Double) -> (Double, Double, Double, Double, Double) {
        let w: Double = 2 * Double.pi * Swift.min(f, sr * 0.45) / sr
        let cw: Double = cos(w)
        let al: Double = sin(w) / (2 * 0.7071067811865476)
        let a0: Double = 1 + al
        let b0: Double = (1 + cw) / 2
        return (b0 / a0, -(1 + cw) / a0, b0 / a0, (-2 * cw) / a0, (1 - al) / a0)
    }

    /// SVF (TPT) на f, Q = 1/√2: [a1, a2, a3].
    static func svf(_ f: Double, _ sr: Double) -> (Double, Double, Double) {
        let g: Double = tan(Double.pi * Swift.min(f, sr * 0.49) / sr)
        let k: Double = 1.4142135623730951
        let a1: Double = 1 / (1 + g * (g + k))
        let a2: Double = g * a1
        return (a1, a2, g * a2)
    }

    /// Коэффициенты FILTER по f ∈ −1…1: LP — от 20 кГц вниз при f < 0, HP — от 20 Гц вверх при f > 0.
    func updateFilter(_ f: Double) {
        if f == fSig { return }
        fSig = f
        let lp: Double = f < 0 ? FxDelay.lpMaxHz * pow(FxDelay.lpMinHz / FxDelay.lpMaxHz, -f) : FxDelay.lpMaxHz
        let hp: Double = f > 0 ? FxDelay.hpMinHz * pow(FxDelay.hpMaxHz / FxDelay.hpMinHz, f) : FxDelay.hpMinHz
        cLp = FxDelay.svf(lp, sr)
        cHp = FxDelay.svf(hp, sr)
    }

    /// Покой (S14b, FxRack): линии и фильтры с нуля, ручки и время при пробуждении — сразу целевые (как новый Delay).
    func sleep() {
        reset()
        started = false
        dL = 0
        dR = 0
    }

    public func reset() {
        lineL.update(repeating: 0, count: len)
        lineR.update(repeating: 0, count: len)
        zHp = (0, 0, 0, 0, 0, 0, 0, 0)
        sLp = (0, 0, 0, 0)
        sHp = (0, 0, 0, 0)
    }

    /// Блок n отсчётов: вход (nil — тишина) → эхо в outL/outR (перезаписывает). Параметры — как AudioParam (Float).
    public func process(inL: UnsafePointer<Float>?, inR: UnsafePointer<Float>?, outL: UnsafeMutablePointer<Float>,
                        outR: UnsafeMutablePointer<Float>, frames n: Int, time: Float, feedback: Float, filter fIn: Float,
                        spread spIn: Float) {
        let sr: Double = self.sr
        let tTime: Double = Swift.min(maxTime, Swift.max(0.001, Double(time)))
        let tFb: Double = Swift.min(1, Swift.max(0, Double(feedback)))
        let tFilter: Double = Swift.min(1, Swift.max(-1, Double(fIn)))
        let tSpread: Double = Swift.min(1, Swift.max(0, Double(spIn)))
        if !started {
            started = true
            fb = tFb
            filter = tFilter
            spread = tSpread
        }
        let a: Double = 1 - exp((-3 * Double(n)) / ((FxDelay.smoothMs / 1000) * sr))
        let fb0: Double = fb
        let fb1: Double = fb0 + (tFb - fb0) * a
        fb = fb1
        filter += (tFilter - filter) * a
        if abs(filter - tFilter) < 1e-4 { filter = tFilter }
        let sp0: Double = spread
        let sp1: Double = sp0 + (tSpread - sp0) * a
        spread = sp1
        updateFilter(filter)
        let off: Double = FxDelay.filterOff
        let wLp0: Double = wLp
        let wLp1: Double = Swift.min(1, Swift.max(0, -filter / off))
        let wHp0: Double = wHp
        let wHp1: Double = Swift.min(1, Swift.max(0, filter / off))
        wLp = wLp1
        wHp = wHp1

        // SPREAD x: до 0.5 — разнос времени o = x, без перекрёстной связи; дальше c 0 → 1, o = 0.5·(1 − c).
        let c0: Double = sp0 > 0.5 ? (sp0 - 0.5) / 0.5 : 0
        let c1: Double = sp1 > 0.5 ? (sp1 - 0.5) / 0.5 : 0
        let o1: Double = sp1 > 0.5 ? 0.5 * (1 - c1) : sp1
        let targL: Double = tTime * sr
        let targR: Double = tTime * (1 + o1) * sr
        if dL == 0 {
            dL = targL
            dR = targR
        }
        let g: Double = 1 - exp(-1 / ((FxDelay.glideMs / 1000) * sr))
        let gm: Double = FxDelay.glideMax

        let lineL = self.lineL, lineR = self.lineR, mask = self.mask, len = self.len
        let (k0, k1, k2, k3, k4) = kHp
        var (hx1L, hx2L, hy1L, hy2L, hx1R, hx2R, hy1R, hy2R) = zHp
        let (la1, la2, la3) = cLp
        let (ha1, ha2, ha3) = cHp
        var (lp1L, lp2L, lp1R, lp2R) = sLp
        var (hp1L, hp2L, hp1R, hp2R) = sHp
        let k: Double = FxDelay.satK
        let tiny: Double = FxDelay.tiny
        let wowAmp: Double = (FxDelay.wowMs / 1000) * sr
        let flAmp: Double = (FxDelay.flutterMs / 1000) * sr
        let wowStep: Double = FxDelay.wowHz / sr
        var (wp0, wp1) = wowPh
        var (wa0, wa1) = wowA
        var (wb0, wb1) = wowB
        var (fs0, fs1) = flS
        var (fc0, fc1) = flC
        let flR = self.flR, flI = self.flI
        let maxD: Double = Double(len - 4)
        let sqrt2: Double = 1.4142135623730951
        let nD: Double = Double(n)
        var w: Int = self.w
        var dL: Double = self.dL
        var dR: Double = self.dR
        var bad = false

        var s = 0
        while s < n {
            let f: Double = Double(s + 1) / nD
            let fbS: Double = fb0 + (fb1 - fb0) * f
            let c: Double = c0 + (c1 - c0) * f
            var st: Double = (targL - dL) * g
            dL += st > gm ? gm : (st < -gm ? -gm : st)
            st = (targR - dR) * g
            dR += st > gm ? gm : (st < -gm ? -gm : st)
            // Модуляция линий: wow (случайное блуждание) + flutter (синус).
            var ph: Double = wp0 + wowStep
            if ph >= 1 {
                ph -= 1
                wa0 = wb0
                wb0 = rng.next() * 2 - 1
            }
            wp0 = ph
            var sn: Double = fs0 * flR + fc0 * flI
            fc0 = fc0 * flR - fs0 * flI
            fs0 = sn
            ph = wp1 + wowStep
            if ph >= 1 {
                ph -= 1
                wa1 = wb1
                wb1 = rng.next() * 2 - 1
            }
            wp1 = ph
            sn = fs1 * flR + fc1 * flI
            fc1 = fc1 * flR - fs1 * flI
            fs1 = sn
            let u0: Double = 0.5 - 0.5 * cos(Double.pi * wp0)
            let u1: Double = 0.5 - 0.5 * cos(Double.pi * wp1)
            let mod0: Double = (wa0 + (wb0 - wa0) * u0) * wowAmp + fs0 * flAmp
            let mod1: Double = (wa1 + (wb1 - wa1) * u1) * wowAmp + fs1 * flAmp
            // Чтение линий (кубический Эрмит).
            var yL: Double
            var yR: Double
            do {
                let d: Double = Swift.min(maxD, Swift.max(1, dL + mod0))
                let pos: Double = Double(w) - d + Double(len)
                // Позиция положительна: пол — через Int (rounded(.down) в отладочной сборке — медленный вызов; S14b).
                let ip = Int(pos)
                let fl: Double = Double(ip)
                let fr: Double = pos - fl
                let y0 = Double(lineL[(ip - 1) & mask]), y1 = Double(lineL[ip & mask])
                let y2 = Double(lineL[(ip + 1) & mask]), y3 = Double(lineL[(ip + 2) & mask])
                let h1: Double = 0.5 * (y2 - y0)
                let h2: Double = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
                let h3: Double = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
                yL = ((h3 * fr + h2) * fr + h1) * fr + y1
            }
            do {
                let d: Double = Swift.min(maxD, Swift.max(1, dR + mod1))
                let pos: Double = Double(w) - d + Double(len)
                // Позиция положительна: пол — через Int (rounded(.down) в отладочной сборке — медленный вызов; S14b).
                let ip = Int(pos)
                let fl: Double = Double(ip)
                let fr: Double = pos - fl
                let y0 = Double(lineR[(ip - 1) & mask]), y1 = Double(lineR[ip & mask])
                let y2 = Double(lineR[(ip + 1) & mask]), y3 = Double(lineR[(ip + 2) & mask])
                let h1: Double = 0.5 * (y2 - y0)
                let h2: Double = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
                let h3: Double = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
                yR = ((h3 * fr + h2) * fr + h1) * fr + y1
            }
            // Выход линий: HP 60 Гц (прямая форма I) → FILTER.
            var y: Double = k0 * yL + k1 * hx1L + k2 * hx2L - k3 * hy1L - k4 * hy2L
            hx2L = hx1L; hx1L = yL; hy2L = hy1L; hy1L = y
            yL = y
            y = k0 * yR + k1 * hx1R + k2 * hx2R - k3 * hy1R - k4 * hy2R
            hx2R = hx1R; hx1R = yR; hy2R = hy1R; hy1R = y
            yR = y
            do {
                let wl: Double = wLp0 + (wLp1 - wLp0) * f
                let wh: Double = wHp0 + (wHp1 - wHp0) * f
                // LP (SVF) L.
                var v3: Double = yL - lp2L
                var v1: Double = la1 * lp1L + la2 * v3
                var v2: Double = lp2L + la2 * lp1L + la3 * v3
                lp1L = 2 * v1 - lp1L; lp2L = 2 * v2 - lp2L
                yL += (v2 - yL) * wl
                // HP (SVF) L.
                v3 = yL - hp2L
                v1 = ha1 * hp1L + ha2 * v3
                v2 = hp2L + ha2 * hp1L + ha3 * v3
                hp1L = 2 * v1 - hp1L; hp2L = 2 * v2 - hp2L
                var v: Double = yL - sqrt2 * v1 - v2
                yL += (v - yL) * wh
                // LP R.
                v3 = yR - lp2R
                v1 = la1 * lp1R + la2 * v3
                v2 = lp2R + la2 * lp1R + la3 * v3
                lp1R = 2 * v1 - lp1R; lp2R = 2 * v2 - lp2R
                yR += (v2 - yR) * wl
                // HP R.
                v3 = yR - hp2R
                v1 = ha1 * hp1R + ha2 * v3
                v2 = hp2R + ha2 * hp1R + ha3 * v3
                hp1R = 2 * v1 - hp1R; hp2R = 2 * v2 - hp2R
                v = yR - sqrt2 * v1 - v2
                yR += (v - yR) * wh
            }
            // Обратная связь: мягкая сатурация, перекрёстная связь c.
            let sL: Double = tanh(k * yL) / k
            let sR: Double = tanh(k * yR) / k
            // Вход: при c → 1 эхо входит только в левую линию (моно-сумма).
            var xl: Double = 0
            var xr: Double = 0
            if let p = inL { xl = Double(p[s]) }
            if let p = inR { xr = Double(p[s]) }
            let m: Double = (xl + xr) * 0.5
            lineL[w] = Float((1 - c) * xl + c * m + fbS * ((1 - c) * sL + c * sR) + tiny)
            lineR[w] = Float((1 - c) * xr + fbS * ((1 - c) * sR + c * sL) + tiny)
            w = (w + 1) & mask
            outL[s] = Float(sL)
            outR[s] = Float(sR)
            if !(yL == yL && yR == yR) || yL > 1e6 || yL < -1e6 || yR > 1e6 || yR < -1e6 { bad = true }
            s += 1
        }
        self.w = w
        self.dL = dL
        self.dR = dR
        wowPh = (wp0, wp1)
        wowA = (wa0, wa1)
        wowB = (wb0, wb1)
        flS = (fs0, fs1)
        flC = (fc0, fc1)
        // Денормали в состояниях фильтров.
        @inline(__always) func dn(_ x: Double) -> Double { return abs(x) < 1e-20 ? 0 : x }
        zHp = (dn(hx1L), dn(hx2L), dn(hy1L), dn(hy2L), dn(hx1R), dn(hx2R), dn(hy1R), dn(hy2R))
        sLp = (dn(lp1L), dn(lp2L), dn(lp1R), dn(lp2R))
        sHp = (dn(hp1L), dn(hp2L), dn(hp1R), dn(hp2R))
        // NaN или разнос — сброс состояния (тишина вместо шума).
        if bad {
            reset()
            outL.update(repeating: 0, count: n)
            outR.update(repeating: 0, count: n)
        }
    }
}
