import Foundation

// Reverb — перенос public/reverb-worklet.js 1:1: гибрид пластины и зала, стерео вход и выход.
// Цепь: вход → LOW CUT (HPF 2-го порядка) → HIGH CUT (LPF 14 кГц) → пред-задержка (4 + 0,22 × SIZE мс + predelay) →
// входная диффузия (4 all-pass на канал, Даттерро) → FDN из 8 линий (L — в линии 0, 2, 4, 6; R — в 1, 3, 5, 7;
// матрица Хаусхолдера; в линии — затухание и НЧ-демпфирование по Жо; длины качают LFO 0,1–0,9 Гц) → выход;
// ранние отражения — 12 отводов на канал после пред-задержки. TONE — затухание ВЧ (на 8 кГц DECAY × r) и полка
// 6 кГц ±4 dB. Параметры — k-rate: size (0–100), decay (с), tone (−100…100), lowcut (Гц), predelay (мс);
// DECAY, TONE, LOW CUT, пред-задержка сглаживаются за 50 мс, SIZE — длины скользят за 150 мс.
// Расчёт — Double, как JS; буферы — Float (Float32Array). Горячий цикл — по правилам отладочной сборки.

public final class FxReverb {
    // Константы (REVERB_CONST).
    static let diffusion: Double = 0.7
    static let modulation: Double = 0.3
    static let modDepthMax: Double = 20
    static let modRates: [Double] = [0.1, 0.21, 0.33, 0.44, 0.56, 0.67, 0.79, 0.9]
    static let early: Double = 0.4
    static let highCutHz: Double = 14000
    static let returnDb: Double = 0
    static let fdnLengths: [Double] = [1123, 1361, 1597, 1823, 2063, 2297, 2539, 2803]
    static let diffLensL: [Double] = [229, 173, 611, 447]
    static let diffLensR: [Double] = [241, 181, 593, 461]
    static let diffCoefs: [Double] = [0.75, 0.75, 0.625, 0.625]
    static let erTimesL: [Double] = [3.1, 5.3, 7.9, 10.7, 13.3, 16.9, 19.7, 23.3, 27.1, 31.3, 35.9, 41.0]
    static let erTimesR: [Double] = [3.7, 4.9, 8.6, 11.3, 14.1, 15.8, 20.6, 24.2, 26.3, 32.8, 34.7, 43.1]
    static let preBaseMs: Double = 4
    static let prePerSize: Double = 0.22
    static let scaleMin: Double = 0.35
    static let scaleRange: Double = 1.65
    static let toneLo: Double = 0.12
    static let toneMid: Double = 0.5
    static let toneHi: Double = 1
    static let dampHz: Double = 8000
    static let shelfHz: Double = 6000
    static let shelfDb: Double = 4
    static let smoothMs: Double = 50
    static let sizeGlideMs: Double = 150
    static let lateGain: Double = 0.35
    static let tiny: Double = 1e-18
    static let maxPreMs: Double = 240
    static let n: Int = 8

    let sr: Double
    var started = false
    var size: Double = 50
    var decay: Double = 2
    var tone: Double = 0
    var lowcut: Double = 20
    var preMs: Double = .nan
    var scale: Double
    // Биквады: коэффициенты [b0, b1, b2, a1, a2] и состояния [x1, x2, y1, y2] × 2 канала.
    let kHp = UnsafeMutablePointer<Double>.allocate(capacity: 5)
    let zHp = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let kLp = UnsafeMutablePointer<Double>.allocate(capacity: 5)
    let zLp = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let kSh = UnsafeMutablePointer<Double>.allocate(capacity: 5)
    let zSh = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    var coefSig: (Double, Double) = (.nan, .nan)
    // Пред-задержка и буфер ранних отражений.
    let preLen: Int
    let preL: UnsafeMutablePointer<Float>
    let preR: UnsafeMutablePointer<Float>
    var preW: Int = 0
    let erLen: Int
    let erL: UnsafeMutablePointer<Float>
    let erR: UnsafeMutablePointer<Float>
    var erW: Int = 0
    let erGain = UnsafeMutablePointer<Double>.allocate(capacity: 12)
    let erTL = UnsafeMutablePointer<Double>.allocate(capacity: 12)
    let erTR = UnsafeMutablePointer<Double>.allocate(capacity: 12)
    // Входная диффузия: 8 all-pass (L 0–3, R 4–7) в одном буфере.
    let apBuf: UnsafeMutablePointer<Float>
    let apOff = UnsafeMutablePointer<Int>.allocate(capacity: 8)
    let apMask = UnsafeMutablePointer<Int>.allocate(capacity: 8)
    let apLen = UnsafeMutablePointer<Int>.allocate(capacity: 8)
    let apW = UnsafeMutablePointer<Int>.allocate(capacity: 8)
    let apTotal: Int
    let apG = UnsafeMutablePointer<Double>.allocate(capacity: 4)
    // FDN: 8 линий подряд.
    let lineSize: Int
    let mask: Int
    let lines: UnsafeMutablePointer<Float>
    var w: Int = 0
    let base = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let gain = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let damp = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let lp = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let rd = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let v = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    // LFO линий: вращающийся вектор (sin, cos) и шаг поворота.
    let ms = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let mc = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let mr = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let mi = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    let modDepth: Double
    let ret: Double

    /// seed — генератор фаз LFO линий (как Math.random веба).
    public init(sampleRate: Double, seed: UInt32) {
        sr = sampleRate
        let k: Double = sampleRate / 48000
        scale = FxReverb.scaleMin + FxReverb.scaleRange * 0.5
        for p in [zHp, zLp, zSh] { p.initialize(repeating: 0, count: 8) }
        for p in [kHp, kSh] { p.initialize(repeating: 0, count: 5) }
        kLp.initialize(repeating: 0, count: 5)
        FxReverb.biquad(kLp, lp: true, FxReverb.highCutHz, sampleRate)
        preLen = FxReverb.pow2(Int((FxReverb.maxPreMs / 1000 * sampleRate).rounded(.up)) + 8)
        preL = UnsafeMutablePointer<Float>.allocate(capacity: preLen)
        preR = UnsafeMutablePointer<Float>.allocate(capacity: preLen)
        preL.initialize(repeating: 0, count: preLen)
        preR.initialize(repeating: 0, count: preLen)
        erLen = FxReverb.pow2(Int((0.1 * sampleRate).rounded(.up)) + 8)
        erL = UnsafeMutablePointer<Float>.allocate(capacity: erLen)
        erR = UnsafeMutablePointer<Float>.allocate(capacity: erLen)
        erL.initialize(repeating: 0, count: erLen)
        erR.initialize(repeating: 0, count: erLen)
        // Отводы: знаки чередуются, усиления спадают; сумма модулей — 1 (Float32Array в вебе).
        var g = [Double](repeating: 0, count: 12)
        var sum: Double = 0
        for i in 0..<12 {
            g[i] = pow(0.85, Double(i)) * (i % 2 == 1 ? -1 : 1)
            sum += abs(g[i])
        }
        for i in 0..<12 {
            erGain[i] = Double(Float(g[i] / sum))
            erTL[i] = FxReverb.erTimesL[i]
            erTR[i] = FxReverb.erTimesR[i]
        }
        // All-pass: длина l·k, буфер — степень двойки больше длины.
        var off = 0
        for i in 0..<8 {
            let l: Double = i < 4 ? FxReverb.diffLensL[i] : FxReverb.diffLensR[i - 4]
            let len = Int((l * k).rounded())
            let size = FxReverb.pow2(len + 1)
            apOff[i] = off
            apMask[i] = size - 1
            apLen[i] = len
            apW[i] = 0
            off += size
        }
        apTotal = off
        apBuf = UnsafeMutablePointer<Float>.allocate(capacity: off)
        apBuf.initialize(repeating: 0, count: off)
        for i in 0..<4 {
            apG[i] = Double(Float(Swift.min(0.95, (FxReverb.diffCoefs[i] * FxReverb.diffusion) / 0.7)))
        }
        // FDN: линии с запасом на SIZE 100 % и модуляцию.
        let maxLen: Double = 2803 * (FxReverb.scaleMin + FxReverb.scaleRange) * k + FxReverb.modDepthMax * k + 16
        lineSize = FxReverb.pow2(Int(maxLen.rounded(.up)))
        mask = lineSize - 1
        lines = UnsafeMutablePointer<Float>.allocate(capacity: lineSize * 8)
        lines.initialize(repeating: 0, count: lineSize * 8)
        var rng = FxRandom(seed)
        for i in 0..<8 {
            base[i] = FxReverb.fdnLengths[i] * k
            gain[i] = 0
            damp[i] = 0
            lp[i] = 0
            rd[i] = 0
            v[i] = 0
            let ph: Double = rng.next() * 2 * Double.pi
            ms[i] = sin(ph)
            mc[i] = cos(ph)
            let wl: Double = 2 * Double.pi * FxReverb.modRates[i] / sampleRate
            mr[i] = cos(wl)
            mi[i] = sin(wl)
        }
        modDepth = FxReverb.modulation * FxReverb.modDepthMax * k
        ret = pow(10, FxReverb.returnDb / 20)
    }

    deinit {
        for p in [kHp, zHp, kLp, zLp, kSh, zSh, erGain, erTL, erTR, apG, base, gain, damp, lp, rd, v, ms, mc, mr, mi] {
            p.deallocate()
        }
        for p in [preL, preR, erL, erR, apBuf, lines] { p.deallocate() }
        for p in [apOff, apMask, apLen, apW] { p.deallocate() }
    }

    static func pow2(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    /// Биквад RBJ (Q = 1/√2): LP или HP.
    static func biquad(_ out: UnsafeMutablePointer<Double>, lp: Bool, _ f: Double, _ sr: Double) {
        let w: Double = 2 * Double.pi * Swift.min(f, sr * 0.45) / sr
        let cw: Double = cos(w)
        let al: Double = sin(w) / (2 * 0.7071067811865476)
        let a0: Double = 1 + al
        let b0: Double = lp ? (1 - cw) / 2 : (1 + cw) / 2
        let b1: Double = lp ? 1 - cw : -(1 + cw)
        out[0] = b0 / a0; out[1] = b1 / a0; out[2] = b0 / a0; out[3] = (-2 * cw) / a0; out[4] = (1 - al) / a0
    }

    /// Полка (high shelf, S = 1).
    static func shelf(_ out: UnsafeMutablePointer<Double>, _ f: Double, _ sr: Double, _ gainDb: Double) {
        let w: Double = 2 * Double.pi * Swift.min(f, sr * 0.45) / sr
        let cw: Double = cos(w)
        let sw: Double = sin(w)
        let A: Double = pow(10, gainDb / 40)
        let al: Double = (sw / 2) * 1.4142135623730951
        let s: Double = 2 * sqrt(A) * al
        let b0: Double = A * ((A + 1) + (A - 1) * cw + s)
        let b1: Double = -2 * A * ((A - 1) + (A + 1) * cw)
        let b2: Double = A * ((A + 1) + (A - 1) * cw - s)
        let a0: Double = (A + 1) - (A - 1) * cw + s
        let a1: Double = 2 * ((A - 1) - (A + 1) * cw)
        let a2: Double = (A + 1) - (A - 1) * cw - s
        out[0] = b0 / a0; out[1] = b1 / a0; out[2] = b2 / a0; out[3] = a1 / a0; out[4] = a2 / a0
    }

    func scaleOf(_ size: Double) -> Double { return FxReverb.scaleMin + FxReverb.scaleRange * (size / 100) }

    /// r по TONE: −100 → 0.12, 0 → 0.5, +100 → 1 (по логарифму).
    func toneR(_ t: Double) -> Double {
        let u: Double = Swift.max(-1, Swift.min(1, t / 100))
        let lo: Double = log(FxReverb.toneLo), mid: Double = log(FxReverb.toneMid), hi: Double = log(FxReverb.toneHi)
        return u < 0 ? exp(mid + (mid - lo) * u) : exp(mid + (hi - mid) * u)
    }

    /// Усиления затухания и демпфирование линий по DECAY, TONE и длинам (формула Жо).
    func updateLoop() {
        let r: Double = toneR(tone)
        let c: Double = cos(2 * Double.pi * FxReverb.dampHz / sr)
        for i in 0..<8 {
            let L: Double = base[i] * scale
            let g: Double = pow(10, (-3 * L) / (sr * decay))
            let gHf: Double = pow(10, (-3 * L) / (sr * decay * r))
            gain[i] = Swift.min(0.9995, g)
            let m: Double = Swift.min(1, gHf / g)
            let k2: Double = pow(m, 2)
            if k2 >= 0.999999 {
                damp[i] = 0
                continue
            }
            let p: Double = 1 - k2 * c
            let q: Double = 1 - k2
            damp[i] = Swift.max(0, Swift.min(0.999, (p - sqrt(Swift.max(0, p * p - q * q))) / q))
        }
    }

    /// Коэффициенты LOW CUT и полки TONE — при изменении (как строка-подпись веба: округление до 0,1).
    func updateFilters() {
        let sig: (Double, Double) = (FxReverb.jsRound(lowcut * 10), FxReverb.jsRound(tone * 10))
        if sig == coefSig { return }
        coefSig = sig
        FxReverb.biquad(kHp, lp: false, lowcut, sr)
        FxReverb.shelf(kSh, FxReverb.shelfHz, sr, (FxReverb.shelfDb * tone) / 100)
    }

    /// Math.round: половина — вверх.
    static func jsRound(_ x: Double) -> Double { return (x + 0.5).rounded(.down) }

    public func reset() {
        preL.update(repeating: 0, count: preLen)
        preR.update(repeating: 0, count: preLen)
        erL.update(repeating: 0, count: erLen)
        erR.update(repeating: 0, count: erLen)
        lines.update(repeating: 0, count: lineSize * 8)
        apBuf.update(repeating: 0, count: apTotal)
        for p in [zHp, zLp, zSh] { p.update(repeating: 0, count: 8) }
        lp.update(repeating: 0, count: 8)
    }

    /// Блок n отсчётов: вход (nil — тишина) → outL/outR (перезаписывает). Параметры — как AudioParam (Float).
    public func process(inL: UnsafePointer<Float>?, inR: UnsafePointer<Float>?, outL: UnsafeMutablePointer<Float>,
                        outR: UnsafeMutablePointer<Float>, frames n: Int, size sIn: Float, decay dIn: Float,
                        tone tIn: Float, lowcut lIn: Float, predelay pIn: Float) {
        let sr: Double = self.sr
        let tSize = Double(sIn), tDecay = Double(dIn), tTone = Double(tIn), tLow = Double(lIn), tPre = Double(pIn)
        if !started {
            started = true
            size = tSize; decay = tDecay; tone = tTone; lowcut = tLow
            scale = scaleOf(tSize)
        }
        let a: Double = 1 - exp((-3 * Double(n)) / ((FxReverb.smoothMs / 1000) * sr))
        decay += (tDecay - decay) * a
        tone += (tTone - tone) * a
        lowcut = exp(log(lowcut) + (log(tLow) - log(lowcut)) * a)
        let preT: Double = FxReverb.preBaseMs + FxReverb.prePerSize * tSize + tPre
        let pre0: Double = preMs.isNaN ? preT : preMs
        let pre1: Double = pre0 + (preT - pre0) * a
        preMs = pre1
        let scale0: Double = scale
        let gs: Double = 1 - exp((-3 * Double(n)) / ((FxReverb.sizeGlideMs / 1000) * sr))
        let scale1: Double = scale0 + (scaleOf(tSize) - scale0) * gs
        scale = scale1
        updateFilters()
        updateLoop()

        let lines = self.lines, mask = self.mask, lineSize = self.lineSize
        let base = self.base, gain = self.gain, damp = self.damp, lp = self.lp, rd = self.rd, v = self.v
        let ms = self.ms, mc = self.mc, mr = self.mr, mi = self.mi, depth = self.modDepth
        let preL = self.preL, preR = self.preR, preLen = self.preLen, preMask = preLen - 1
        let erL = self.erL, erR = self.erR, erLen = self.erLen, erMask = erLen - 1
        let kHp = self.kHp, zHp = self.zHp, kLp = self.kLp, zLp = self.zLp, kSh = self.kSh, zSh = self.zSh
        let erG = self.erGain, erTL = self.erTL, erTR = self.erTR
        let apBuf = self.apBuf, apOff = self.apOff, apMask = self.apMask, apLen = self.apLen, apW = self.apW
        let apG = self.apG
        let lateGain: Double = FxReverb.lateGain, early: Double = FxReverb.early, ret: Double = self.ret
        let tiny: Double = FxReverb.tiny
        let nD: Double = Double(n)
        var w: Int = self.w, pw: Int = preW, ew: Int = erW
        var bad = false

        var s = 0
        while s < n {
            let f: Double = Double(s + 1) / nD
            let scale: Double = scale0 + (scale1 - scale0) * f
            // Вход: LOW CUT → HIGH CUT (биквады, прямая форма I; L — состояния 0…3, R — 4…7).
            var xl: Double = 0
            var xr: Double = 0
            if let p = inL { xl = Double(p[s]) }
            if let p = inR { xr = Double(p[s]) }
            var o = 0
            while o < 8 {
                let x: Double = o == 0 ? xl : xr
                var y: Double = kHp[0] * x + kHp[1] * zHp[o] + kHp[2] * zHp[o + 1] - kHp[3] * zHp[o + 2] - kHp[4] * zHp[o + 3]
                zHp[o + 1] = zHp[o]; zHp[o] = x; zHp[o + 3] = zHp[o + 2]; zHp[o + 2] = y
                let x2: Double = y
                y = kLp[0] * x2 + kLp[1] * zLp[o] + kLp[2] * zLp[o + 1] - kLp[3] * zLp[o + 2] - kLp[4] * zLp[o + 3]
                zLp[o + 1] = zLp[o]; zLp[o] = x2; zLp[o + 3] = zLp[o + 2]; zLp[o + 2] = y
                if o == 0 { xl = y } else { xr = y }
                o += 4
            }
            // Пред-задержка (дробное чтение, линейно).
            preL[pw] = Float(xl)
            preR[pw] = Float(xr)
            let pd: Double = Swift.max(1, (pre1 / 1000) * sr)
            let pp: Double = Double(pw) - pd + Double(preLen * 2)
            let pfl: Double = pp.rounded(.down)
            let pi = Int(pfl)
            let pf: Double = pp - pfl
            let pl0 = Double(preL[pi & preMask]), pr0 = Double(preR[pi & preMask])
            let dl: Double = pl0 + (Double(preL[(pi + 1) & preMask]) - pl0) * pf
            let dr: Double = pr0 + (Double(preR[(pi + 1) & preMask]) - pr0) * pf
            pw = (pw + 1) & preMask
            // Ранние отражения: отводы после пред-задержки, времена × масштаб SIZE.
            erL[ew] = Float(dl)
            erR[ew] = Float(dr)
            var el: Double = 0
            var er: Double = 0
            let ems: Double = (sr / 1000) * scale
            var t = 0
            while t < 12 {
                let ql: Double = Double(ew) - erTL[t] * ems + Double(erLen * 2)
                let qfl: Double = ql.rounded(.down)
                let qi = Int(qfl)
                let a0 = Double(erL[qi & erMask])
                el += erG[t] * (a0 + (Double(erL[(qi + 1) & erMask]) - a0) * (ql - qfl))
                let qr: Double = Double(ew) - erTR[t] * ems + Double(erLen * 2)
                let rfl: Double = qr.rounded(.down)
                let ri = Int(rfl)
                let b0 = Double(erR[ri & erMask])
                er += erG[t] * (b0 + (Double(erR[(ri + 1) & erMask]) - b0) * (qr - rfl))
                t += 1
            }
            ew = (ew + 1) & erMask
            // Входная диффузия: 4 all-pass на канал (L — 0…3, R — 4…7).
            var ul: Double = dl
            var ur: Double = dr
            var kk = 0
            while kk < 4 {
                let g: Double = apG[kk]
                var j = kk
                var b = apBuf + apOff[j]
                var ow = apW[j]
                var ov = Double(b[(ow - apLen[j]) & apMask[j]])
                var x: Double = ul + g * ov
                ul = ov - g * x
                b[ow] = Float(x)
                apW[j] = (ow + 1) & apMask[j]
                j = kk + 4
                b = apBuf + apOff[j]
                ow = apW[j]
                ov = Double(b[(ow - apLen[j]) & apMask[j]])
                x = ur + g * ov
                ur = ov - g * x
                b[ow] = Float(x)
                apW[j] = (ow + 1) & apMask[j]
                kk += 1
            }
            // FDN: чтение с модуляцией (кубический Эрмит), демпфирование, затухание.
            var sum: Double = 0
            var i = 0
            while i < 8 {
                let sn: Double = ms[i] * mr[i] + mc[i] * mi[i]
                mc[i] = mc[i] * mr[i] - ms[i] * mi[i]
                ms[i] = sn
                let d: Double = base[i] * scale + depth * sn
                let pos: Double = Double(w) - d + Double(lineSize * 2)
                let fl: Double = pos.rounded(.down)
                let ip = Int(fl)
                let fr: Double = pos - fl
                let L = lines + i * lineSize
                let y0 = Double(L[(ip - 1) & mask]), y1 = Double(L[ip & mask])
                let y2 = Double(L[(ip + 1) & mask]), y3 = Double(L[(ip + 2) & mask])
                let c1: Double = 0.5 * (y2 - y0)
                let c2: Double = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
                let c3: Double = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
                let val: Double = ((c3 * fr + c2) * fr + c1) * fr + y1
                rd[i] = val
                lp[i] = val + damp[i] * (lp[i] - val)
                v[i] = lp[i] * gain[i]
                sum += v[i]
                i += 1
            }
            // Хаусхолдер: y = x − (2/8)·Σx; вход: L — в чётные линии, R — в нечётные.
            let h: Double = sum * 0.25
            let inLv: Double = ul * 0.5
            let inRv: Double = ur * 0.5
            i = 0
            while i < 8 {
                lines[i * lineSize + w] = Float(v[i] - h + ((i & 1) == 1 ? inRv : inLv) + tiny)
                i += 1
            }
            w = (w + 1) & mask
            // Выход: хвост (знаки чередуются) + ранние отражения → полка TONE → возврат.
            var yl: Double = (rd[0] - rd[2] + rd[4] - rd[6]) * lateGain + el * early
            var yr: Double = (rd[1] - rd[3] + rd[5] - rd[7]) * lateGain + er * early
            var y: Double = kSh[0] * yl + kSh[1] * zSh[0] + kSh[2] * zSh[1] - kSh[3] * zSh[2] - kSh[4] * zSh[3]
            zSh[1] = zSh[0]; zSh[0] = yl; zSh[3] = zSh[2]; zSh[2] = y
            yl = y
            y = kSh[0] * yr + kSh[1] * zSh[4] + kSh[2] * zSh[5] - kSh[3] * zSh[6] - kSh[4] * zSh[7]
            zSh[5] = zSh[4]; zSh[4] = yr; zSh[7] = zSh[6]; zSh[6] = y
            yr = y
            outL[s] = Float(yl * ret)
            outR[s] = Float(yr * ret)
            if !(yl == yl && yr == yr) || abs(yl) > 1e6 { bad = true }
            s += 1
        }
        self.w = w
        preW = pw
        erW = ew
        // NaN или разнос — сброс состояния (тишина вместо шума).
        if bad {
            reset()
            outL.update(repeating: 0, count: n)
            outR.update(repeating: 0, count: n)
        }
    }
}
