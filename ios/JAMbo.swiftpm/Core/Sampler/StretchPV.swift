import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

// Таймстретч NORMAL (RATE в TSTR): фазовый вокодер — кадры по 2048 отсчётов через 512 (окно Ханна на анализе и
// синтезе, в сумме ×1,5). Кадр читается из сэмпла со скоростью высоты (нота и Pitch) вокруг указателя времени —
// высота не зависит от скорости. Фазы:
// - фазовая привязка (Laroche–Dolson): у пиков спектра фаза идёт по своей мгновенной частоте, бины вокруг пика
//   держат с ним прежнюю разность фаз — тональный звук без «металла» и биений;
// - атаки: доля бинов, выросших больше чем на 6 dB от прошлого кадра, ≥ 30 % — фазы кадра берутся из анализа
//   (удар не размазывается);
// - стерео: фазы считаются по середине (L + R), каналы поворачиваются на тот же угол — картина не плывёт;
// - скорость около 0 — частоты прежние (звук замирает);
// - начало ноты — первый кадр без окна, с весом недостающих ранних кадров: атака с первого отсчёта, без задержки;
// - атаки сэмпла (Onsets): куски между атаками тянутся отдельно — кадр не видит звука за границами своего куска
//   (удар не слышен раньше себя), на атаке голос начинается заново, как нота: удар — исходный, без размазывания.
// Указатель времени ведёт голос (Sampler.renderVoice); кадры смотрят вперёд на полкадра — сэмпл весь в памяти.
// Всё — в колбэке, без выделений памяти; БПФ — PvFFT (vDSP на iPad).

final class Vocoder {
    static let size = 2048
    static let hop = 512
    static let bins = 1025
    static let mask = 2047

    let slots: Int
    let fft: PvFFT
    /// Окно Ханна; вес первого кадра ноты (недостающие ранние кадры), уже делённый на 1,5.
    let win: UnsafeMutablePointer<Float>
    let firstW: UnsafeMutablePointer<Float>
    /// Нормировка выхода: 1 / (gain БПФ · 1,5).
    let norm: Float

    // Голоса: кольцо выхода (голос·size), позиция чтения, отсчётов до кадра, первый кадр уже есть.
    let ringL: UnsafeMutablePointer<Float>
    let ringR: UnsafeMutablePointer<Float>
    let ringAt: UnsafeMutablePointer<Int>
    let hopLeft: UnsafeMutablePointer<Int>
    let primed: UnsafeMutablePointer<UInt8>
    /// Прошлый кадр (голос·bins): фаза анализа и синтеза середины, амплитуда, мгновенная частота (рад/отсчёт);
    /// центр кадра в сэмпле; был ли кадр атакой; направление.
    let prevAna: UnsafeMutablePointer<Float>
    let prevSyn: UnsafeMutablePointer<Float>
    let prevMag: UnsafeMutablePointer<Float>
    let instF: UnsafeMutablePointer<Float>
    let prevC: UnsafeMutablePointer<Double>
    let prevHit: UnsafeMutablePointer<UInt8>
    let lastDir: UnsafeMutablePointer<Double>
    /// Кусок между атаками (в сэмпле), в пределах Start…End.
    let segLo: UnsafeMutablePointer<Double>
    let segHi: UnsafeMutablePointer<Double>

    // Рабочие буферы кадра (общие: голоса считаются по очереди).
    let fL: UnsafeMutablePointer<Float>
    let fR: UnsafeMutablePointer<Float>
    let reL: UnsafeMutablePointer<Float>
    let imL: UnsafeMutablePointer<Float>
    let reR: UnsafeMutablePointer<Float>
    let imR: UnsafeMutablePointer<Float>
    let reM: UnsafeMutablePointer<Float>
    let imM: UnsafeMutablePointer<Float>
    let mag: UnsafeMutablePointer<Float>
    let ph: UnsafeMutablePointer<Float>
    let syn: UnsafeMutablePointer<Float>
    let dc: UnsafeMutablePointer<Float>
    let ds: UnsafeMutablePointer<Float>
    let peaks: UnsafeMutablePointer<Int>
    /// Выход куска.
    let outL: UnsafeMutablePointer<Float>
    let outR: UnsafeMutablePointer<Float>

    init(slots n: Int) {
        slots = n
        let N = Vocoder.size
        let B = Vocoder.bins
        let H = Vocoder.hop
        fft = PvFFT(size: N)
        win = .allocate(capacity: N)
        var i = 0
        while i < N {
            win[i] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(N)))
            i += 1
        }
        firstW = .allocate(capacity: N)
        i = 0
        while i < N {
            var c: Float = 0
            var k = 0
            while i + k * H < N {
                let w: Float = win[i + k * H]
                c += w * w
                k += 1
            }
            firstW[i] = c / 1.5
            i += 1
        }
        norm = 1 / (fft.gain * 1.5)
        func buf(_ c: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: c)
            p.initialize(repeating: 0, count: c)
            return p
        }
        ringL = buf(n * N)
        ringR = buf(n * N)
        ringAt = .allocate(capacity: n)
        ringAt.initialize(repeating: 0, count: n)
        hopLeft = .allocate(capacity: n)
        hopLeft.initialize(repeating: 0, count: n)
        primed = .allocate(capacity: n)
        primed.initialize(repeating: 0, count: n)
        prevAna = buf(n * B)
        prevSyn = buf(n * B)
        prevMag = buf(n * B)
        instF = buf(n * B)
        prevC = .allocate(capacity: n)
        prevC.initialize(repeating: 0, count: n)
        prevHit = .allocate(capacity: n)
        prevHit.initialize(repeating: 0, count: n)
        lastDir = .allocate(capacity: n)
        lastDir.initialize(repeating: 1, count: n)
        segLo = .allocate(capacity: n)
        segLo.initialize(repeating: 0, count: n)
        segHi = .allocate(capacity: n)
        segHi.initialize(repeating: 0, count: n)
        fL = buf(N)
        fR = buf(N)
        reL = buf(B)
        imL = buf(B)
        reR = buf(B)
        imR = buf(B)
        reM = buf(B)
        imM = buf(B)
        mag = buf(B)
        ph = buf(B)
        syn = buf(B)
        dc = buf(B)
        ds = buf(B)
        peaks = .allocate(capacity: B)
        peaks.initialize(repeating: 0, count: B)
        outL = buf(Stretcher.maxChunk)
        outR = buf(Stretcher.maxChunk)
    }

    deinit {
        for p in [win, firstW, ringL, ringR, prevAna, prevSyn, prevMag, instF, fL, fR, reL, imL, reR, imR, reM, imM,
                  mag, ph, syn, dc, ds, outL, outR] {
            p.deallocate()
        }
        ringAt.deallocate()
        hopLeft.deallocate()
        primed.deallocate()
        prevC.deallocate()
        prevHit.deallocate()
        lastDir.deallocate()
        segLo.deallocate()
        segHi.deallocate()
        peaks.deallocate()
    }

    /// Новая нота голоса v: кольцо пустое, первый кадр — на первом отсчёте.
    func start(_ v: Int, dir: Double) {
        let N = Vocoder.size
        (ringL + v * N).update(repeating: 0, count: N)
        (ringR + v * N).update(repeating: 0, count: N)
        ringAt[v] = 0
        hopLeft[v] = 0
        primed[v] = 0
        prevHit[v] = 0
        lastDir[v] = dir < 0 ? -1 : 1
    }

    /// m отсчётов голоса v в outL/outR (как Stretcher.fill): первые skip — тишина; указатель времени от pos0 со
    /// скоростью speed, высота — ratio; читается только отрезок lo…hi; атаки — ons (nOns, по возрастанию).
    func fill(_ v: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ frames: Int, _ stereo: Bool,
              _ pos0: Double, _ speed: Double, _ ratio: Double, _ m: Int, _ skip: Int, _ lo: Double, _ hi: Double,
              _ ons: UnsafeMutablePointer<Double>?, _ nOns: Int) {
        let N = Vocoder.size
        let msk = Vocoder.mask
        if speed > 1e-9 { lastDir[v] = 1 } else if speed < -1e-9 { lastDir[v] = -1 }
        let step: Double = lastDir[v] * ratio
        var j = 0
        while j < skip && j < m {
            outL[j] = 0
            outR[j] = 0
            j += 1
        }
        let rl = ringL + v * N
        let rr = ringR + v * N
        var t: Double = pos0
        while j < m {
            // Новая нота или указатель вышел из своего куска (дошёл до атаки) — начать заново с этого места.
            if primed[v] == 0 || t < segLo[v] || t >= segHi[v] {
                segment(v, t, lo, hi, ons, nOns)
                first(v, l, r, frames, stereo, t, step, segLo[v], segHi[v])
                primed[v] = 1
                hopLeft[v] = Vocoder.hop
            }
            let a = ringAt[v]
            outL[j] = rl[a]
            outR[j] = stereo ? rr[a] : rl[a]
            rl[a] = 0
            rr[a] = 0
            ringAt[v] = (a + 1) & msk
            t += speed
            hopLeft[v] -= 1
            if hopLeft[v] <= 0 {
                frame(v, l, r, frames, stereo, t + speed * Double(N / 2), step, ratio, segLo[v], segHi[v])
                hopLeft[v] = Vocoder.hop
            }
            j += 1
        }
    }

    /// Кусок между атаками, в котором t (в пределах lo…hi).
    private func segment(_ v: Int, _ t: Double, _ lo: Double, _ hi: Double, _ ons: UnsafeMutablePointer<Double>?,
                         _ n: Int) {
        var a: Double = lo
        var b: Double = hi
        if let o = ons, n > 0 {
            // Первая атака правее t (двоичный поиск).
            var i = 0
            var k = n
            while i < k {
                let mid = (i + k) / 2
                if o[mid] <= t { i = mid + 1 } else { k = mid }
            }
            if i > 0 { a = Swift.max(lo, o[i - 1]) }
            if i < n { b = Swift.min(hi, o[i]) }
        }
        // Указатель за пределами Start…End (край голоса) — кусок вокруг него, чтобы не начинать заново каждый отсчёт.
        if t < a { a = t }
        if t >= b { b = t + 1 }
        segLo[v] = a
        segHi[v] = b
    }

    /// Окно кадра из сэмпла: отсчёты c + (i − size/2)·step (кубически), вне lo…hi — 0; raw — без окна.
    private func read(_ p: UnsafeMutablePointer<Float>, _ frames: Int, _ c: Double, _ step: Double, _ lo: Double,
                      _ hi: Double, _ out: UnsafeMutablePointer<Float>, raw: Bool) {
        let N = Vocoder.size
        let w = win
        let x0: Double = c - Double(N / 2) * step
        let x1: Double = x0 + Double(N - 1) * step
        // Весь кадр внутри куска и сэмпла — без проверок границ.
        if Swift.min(x0, x1) >= Swift.max(lo, 1) && Swift.max(x0, x1) < Swift.min(hi, Double(frames - 3)) {
            var x: Double = x0
            var i = 0
            while i < N {
                let k = Int(x)
                let f = Float(x - Double(k))
                let ym1: Float = p[k - 1], y0: Float = p[k], y1: Float = p[k + 1], y2: Float = p[k + 2]
                let c1: Float = 0.5 * (y1 - ym1)
                let c2: Float = ym1 - 2.5 * y0 + 2 * y1 - 0.5 * y2
                let c3: Float = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1)
                let y: Float = ((c3 * f + c2) * f + c1) * f + y0
                out[i] = raw ? y : y * w[i]
                x += step
                i += 1
            }
            return
        }
        var i = 0
        while i < N {
            let x: Double = x0 + Double(i) * step
            var y: Float = 0
            if x >= lo && x < hi && x >= 0 {
                let k = Int(x)
                let f = Float(x - Double(k))
                let ym1: Float = k >= 1 && k - 1 < frames ? p[k - 1] : 0
                let y0: Float = k < frames ? p[k] : 0
                let y1: Float = k + 1 < frames ? p[k + 1] : 0
                let y2: Float = k + 2 < frames ? p[k + 2] : 0
                let c1: Float = 0.5 * (y1 - ym1)
                let c2: Float = ym1 - 2.5 * y0 + 2 * y1 - 0.5 * y2
                let c3: Float = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1)
                y = ((c3 * f + c2) * f + c1) * f + y0
            }
            out[i] = raw ? y : y * w[i]
            i += 1
        }
    }

    /// Спектр середины (L + R или L) — амплитуды и фазы в mag, ph.
    private func analyze(_ stereo: Bool) {
        let B = Vocoder.bins
        var k = 0
        while k < B {
            let a: Float = stereo ? reL[k] + reR[k] : reL[k]
            let b: Float = stereo ? imL[k] + imR[k] : imL[k]
            reM[k] = a
            imM[k] = b
            k += 1
        }
        #if canImport(Accelerate)
        var n32 = Int32(B)
        vvatan2f(ph, imM, reM, &n32)
        var sp = DSPSplitComplex(realp: reM, imagp: imM)
        vDSP_zvabs(&sp, 1, mag, 1, vDSP_Length(B))
        #else
        k = 0
        while k < B {
            ph[k] = atan2(imM[k], reM[k])
            mag[k] = (reM[k] * reM[k] + imM[k] * imM[k]).squareRoot()
            k += 1
        }
        #endif
    }

    /// Первый кадр ноты: в кольцо — сэмпл без окна с весом firstW (атака с первого отсчёта), в состояние — его анализ.
    private func first(_ v: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ frames: Int,
                       _ stereo: Bool, _ t0: Double, _ step: Double, _ lo: Double, _ hi: Double) {
        let N = Vocoder.size
        let B = Vocoder.bins
        let msk = Vocoder.mask
        let c0: Double = t0 + Double(N / 2) * step
        read(l, frames, c0, step, lo, hi, fL, raw: true)
        if stereo { read(r, frames, c0, step, lo, hi, fR, raw: true) }
        let rl = ringL + v * N
        let rr = ringR + v * N
        let a = ringAt[v]
        var i = 0
        while i < N {
            let q = (a + i) & msk
            rl[q] += fL[i] * firstW[i]
            if stereo { rr[q] += fR[i] * firstW[i] }
            fL[i] *= win[i]
            if stereo { fR[i] *= win[i] }
            i += 1
        }
        fft.forward(fL, reL, imL)
        if stereo { fft.forward(fR, reR, imR) }
        analyze(stereo)
        let b = v * B
        let w0: Float = Float(2 * Double.pi / Double(N))
        var k = 0
        while k < B {
            prevAna[b + k] = ph[k]
            prevSyn[b + k] = ph[k]
            prevMag[b + k] = mag[k]
            instF[b + k] = w0 * Float(k)
            k += 1
        }
        prevC[v] = c0
        prevHit[v] = 1
    }

    /// Кадр с центром c (в сэмпле): анализ, фазы, синтез в кольцо с текущей позиции.
    private func frame(_ v: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ frames: Int,
                       _ stereo: Bool, _ c: Double, _ step: Double, _ ratio: Double, _ lo: Double, _ hi: Double) {
        let N = Vocoder.size
        let B = Vocoder.bins
        let H = Float(Vocoder.hop)
        let msk = Vocoder.mask
        read(l, frames, c, step, lo, hi, fL, raw: false)
        if stereo { read(r, frames, c, step, lo, hi, fR, raw: false) }
        fft.forward(fL, reL, imL)
        if stereo { fft.forward(fR, reR, imR) }
        analyze(stereo)
        let b = v * B
        let pa = prevAna + b, psy = prevSyn + b, pm = prevMag + b, fi = instF + b
        // Шаг анализа в отсчётах прочитанного кадра (со скоростью высоты).
        let ha: Float = Float(Swift.abs(c - prevC[v]) / Swift.max(1e-6, ratio))
        let w0: Float = Float(2 * Double.pi / Double(N))
        let twoPi: Float = 6.2831855
        let inv2Pi: Float = 0.15915494
        // Порог тишины и атака.
        var peak: Float = 0
        var k = 0
        while k < B {
            if mag[k] > peak { peak = mag[k] }
            k += 1
        }
        let floor: Float = peak * 1e-3 + 1e-9
        // Атака (доля бинов, выросших больше чем на 6 dB) и пики (больше двух соседей с каждой стороны) — одним проходом.
        var rise = 0
        var live = 0
        var np = 0
        k = 2
        while k < B - 2 {
            let x = mag[k]
            if x > floor {
                if k >= 8 {
                    live += 1
                    if x > 2 * pm[k] { rise += 1 }
                }
                if x > mag[k - 1] && x > mag[k - 2] && x >= mag[k + 1] && x >= mag[k + 2] {
                    peaks[np] = k
                    np += 1
                }
            }
            k += 1
        }
        let hit: Bool = live > 16 && Float(rise) >= 0.3 * Float(live)
        let reset: Bool = hit && prevHit[v] == 0
        prevHit[v] = hit ? 1 : 0
        // Мгновенная частота бина (разность фаз к −π…π — через целое, без вызовов); при скорости около 0 — прежняя.
        let iha: Float = ha > 1 ? 1 / ha : 0
        if ha > 1 && !reset {
            if np == 0 {
                k = 0
                while k < B {
                    let om: Float = w0 * Float(k)
                    var d: Float = ph[k] - pa[k] - om * ha
                    let q: Float = d * inv2Pi
                    d -= twoPi * Float(Int(q >= 0 ? q + 0.5 : q - 0.5))
                    fi[k] = om + d * iha
                    k += 1
                }
            } else {
                var p = 0
                while p < np {
                    let q0 = peaks[p]
                    let om: Float = w0 * Float(q0)
                    var d: Float = ph[q0] - pa[q0] - om * ha
                    let q: Float = d * inv2Pi
                    d -= twoPi * Float(Int(q >= 0 ? q + 0.5 : q - 0.5))
                    fi[q0] = om + d * iha
                    p += 1
                }
            }
        }
        // Фаза синтеза: атака — фазы анализа; иначе у пика — по его частоте, бины вокруг держат прежнюю разность
        // с пиком (фазовая привязка). Сразу — к −π…π, угол поворота каналов и состояние.
        var p = 0
        var q0: Int = np > 0 ? peaks[0] : 0
        var bound: Int = np > 1 ? (q0 + peaks[1]) / 2 : B
        var base: Float = np > 0 ? psy[q0] + fi[q0] * H - ph[q0] : 0
        k = 0
        while k < B {
            var sv: Float
            if reset {
                sv = ph[k]
            } else if np == 0 {
                sv = psy[k] + fi[k] * H
            } else {
                if k > bound {
                    p += 1
                    q0 = peaks[p]
                    bound = p + 1 < np ? (q0 + peaks[p + 1]) / 2 : B
                    base = psy[q0] + fi[q0] * H - ph[q0]
                }
                sv = base + ph[k]
            }
            let q: Float = sv * inv2Pi
            sv -= twoPi * Float(Int(q >= 0 ? q + 0.5 : q - 0.5))
            psy[k] = sv
            ds[k] = sv - ph[k]
            k += 1
        }
        pa.update(from: ph, count: B)
        pm.update(from: mag, count: B)
        #if canImport(Accelerate)
        var n32 = Int32(B)
        vvsincosf(syn, dc, ds, &n32)
        #else
        k = 0
        while k < B {
            let a = ds[k]
            syn[k] = sin(a)
            dc[k] = cos(a)
            k += 1
        }
        #endif
        k = 0
        while k < B {
            let cs = dc[k], sn = syn[k]
            let a = reL[k], bb = imL[k]
            reL[k] = a * cs - bb * sn
            imL[k] = a * sn + bb * cs
            if stereo {
                let e = reR[k], f = imR[k]
                reR[k] = e * cs - f * sn
                imR[k] = e * sn + f * cs
            }
            k += 1
        }
        fft.inverse(reL, imL, fL)
        if stereo { fft.inverse(reR, imR, fR) }
        let rl = ringL + v * N
        let rr = ringR + v * N
        let a0 = ringAt[v]
        let g = norm
        var i = 0
        while i < N {
            let q = (a0 + i) & msk
            let w: Float = win[i] * g
            rl[q] += fL[i] * w
            if stereo { rr[q] += fR[i] * w }
            i += 1
        }
        prevC[v] = c
    }
}
