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
// Нагрузка: циклы кадра — векторные (PvVec: vDSP на iPad); кадры голосов разнесены по блокам колбэка — кадр голоса
// считается заранее, на lead отсчётов раньше срока (кольцо — с запасом), lead выбирается на начале куска так, чтобы
// кадры голосов реже попадали в один блок (пики нагрузки не складываются).
// Всё — в колбэке, без выделений памяти; БПФ — PvFFT (vDSP на iPad).

final class Vocoder {
    static let size = 2048
    static let hop = 512
    static let bins = 1025
    /// Кольцо выхода голоса: кадр (size) и запас на ранний расчёт (lead < hop).
    static let ring = 4096
    static let ringMask = 4095

    let slots: Int
    let fft: PvFFT
    /// Окно Ханна; оно же с нормировкой выхода; вес первого кадра ноты (недостающие ранние кадры), уже делённый на 1,5.
    let win: UnsafeMutablePointer<Float>
    let winG: UnsafeMutablePointer<Float>
    let firstW: UnsafeMutablePointer<Float>
    /// Частота бина (рад/отсчёт).
    let omg: UnsafeMutablePointer<Float>
    /// Нормировка выхода: 1 / (gain БПФ · 1,5).
    let norm: Float
    /// Длина блока колбэка (ставит Sampler.render) — для разнесения кадров.
    var block: Int = 256
    /// Посчитано кадров (для тестов и замеров).
    private(set) var framesDone: Int = 0

    // Голоса: кольцо выхода (голос·ring), позиция чтения, отсчётов до расчёта кадра, первый кадр уже есть.
    let ringL: UnsafeMutablePointer<Float>
    let ringR: UnsafeMutablePointer<Float>
    let ringAt: UnsafeMutablePointer<Int>
    let hopLeft: UnsafeMutablePointer<Int>
    let primed: UnsafeMutablePointer<UInt8>
    /// Ранний расчёт: на сколько отсчётов раньше срока, кадр отложен до срока (граница куска), отсчёт расчёта.
    let lead: UnsafeMutablePointer<Int>
    let late: UnsafeMutablePointer<UInt8>
    let nextAt: UnsafeMutablePointer<Int64>
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
    /// Чтение кадра из сэмпла (векторно); его ki, kf — рабочие буферы pvWrap.
    let cub: PvCubic
    /// Выход куска.
    let outL: UnsafeMutablePointer<Float>
    let outR: UnsafeMutablePointer<Float>

    init(slots n: Int) {
        slots = n
        let N = Vocoder.size
        let B = Vocoder.bins
        let H = Vocoder.hop
        let R = Vocoder.ring
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
        winG = .allocate(capacity: N)
        i = 0
        while i < N {
            winG[i] = win[i] * norm
            i += 1
        }
        omg = .allocate(capacity: B)
        i = 0
        while i < B {
            omg[i] = Float(2 * Double.pi / Double(N)) * Float(i)
            i += 1
        }
        func buf(_ c: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: c)
            p.initialize(repeating: 0, count: c)
            return p
        }
        ringL = buf(n * R)
        ringR = buf(n * R)
        ringAt = .allocate(capacity: n)
        ringAt.initialize(repeating: 0, count: n)
        hopLeft = .allocate(capacity: n)
        hopLeft.initialize(repeating: 0, count: n)
        primed = .allocate(capacity: n)
        primed.initialize(repeating: 0, count: n)
        lead = .allocate(capacity: n)
        lead.initialize(repeating: 0, count: n)
        late = .allocate(capacity: n)
        late.initialize(repeating: 0, count: n)
        nextAt = .allocate(capacity: n)
        nextAt.initialize(repeating: Int64.min, count: n)
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
        cub = PvCubic(cap: N)
        outL = buf(Stretcher.maxChunk)
        outR = buf(Stretcher.maxChunk)
    }

    deinit {
        for p in [win, winG, firstW, omg, ringL, ringR, prevAna, prevSyn, prevMag, instF, fL, fR, reL, imL, reR, imR,
                  reM, imM, mag, ph, syn, dc, ds, outL, outR] {
            p.deallocate()
        }
        ringAt.deallocate()
        hopLeft.deallocate()
        primed.deallocate()
        lead.deallocate()
        late.deallocate()
        nextAt.deallocate()
        prevC.deallocate()
        prevHit.deallocate()
        lastDir.deallocate()
        segLo.deallocate()
        segHi.deallocate()
        peaks.deallocate()
    }

    /// Новая нота голоса v: кольцо пустое, первый кадр — на первом отсчёте.
    func start(_ v: Int, dir: Double) {
        let R = Vocoder.ring
        (ringL + v * R).update(repeating: 0, count: R)
        (ringR + v * R).update(repeating: 0, count: R)
        ringAt[v] = 0
        hopLeft[v] = 0
        primed[v] = 0
        prevHit[v] = 0
        late[v] = 0
        nextAt[v] = Int64.min
        lastDir[v] = dir < 0 ? -1 : 1
    }

    /// m отсчётов голоса v в outL/outR (как Stretcher.fill): первые skip — тишина; указатель времени от pos0 со
    /// скоростью speed, высота — ratio; читается только отрезок lo…hi; атаки — ons (nOns, по возрастанию);
    /// now — отсчёт колбэка первого из m (для разнесения кадров голосов по блокам).
    func fill(_ v: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ frames: Int, _ stereo: Bool,
              _ pos0: Double, _ speed: Double, _ ratio: Double, _ m: Int, _ skip: Int, _ lo: Double, _ hi: Double,
              _ ons: UnsafeMutablePointer<Double>?, _ nOns: Int, _ now: Int64) {
        let R = Vocoder.ring
        let msk = Vocoder.ringMask
        let H = Vocoder.hop
        let half = Vocoder.size / 2
        if speed > 1e-9 { lastDir[v] = 1 } else if speed < -1e-9 { lastDir[v] = -1 }
        let step: Double = lastDir[v] * ratio
        var j = 0
        while j < skip && j < m {
            outL[j] = 0
            outR[j] = 0
            j += 1
        }
        let rl = ringL + v * R
        let rr = ringR + v * R
        var t: Double = pos0
        while j < m {
            // Новая нота или указатель вышел из своего куска (дошёл до атаки) — начать заново с этого места.
            if primed[v] == 0 || t < segLo[v] || t >= segHi[v] {
                segment(v, t, lo, hi, ons, nOns)
                first(v, l, r, frames, stereo, t, step, segLo[v], segHi[v])
                primed[v] = 1
                late[v] = 0
                lead[v] = pickLead(v, now + Int64(j))
                hopLeft[v] = H - lead[v]
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
                // Кадр — на d отсчётов раньше срока (центр — по нынешней скорости). Срок за границей куска — считать
                // в срок: там, скорее всего, начнётся новый кусок, и лишний кадр старого куска не нужен.
                let d: Int = late[v] != 0 ? 0 : lead[v]
                let due: Double = t + speed * Double(d)
                if d > 0 && (due < segLo[v] || due >= segHi[v]) {
                    late[v] = 1
                    hopLeft[v] = d
                } else {
                    frame(v, l, r, frames, stereo, due + speed * Double(half), step, ratio, segLo[v], segHi[v], d)
                    hopLeft[v] = late[v] != 0 ? H - lead[v] : H
                    late[v] = 0
                }
            }
            j += 1
        }
        nextAt[v] = now + Int64(m + hopLeft[v] - 1)
    }

    /// Ранний расчёт кадров голоса v, начинающего кусок на отсчёте s: из lead = 0, block, 2·block… (< hop) — тот,
    /// при котором кадр попадает в блок, где считается меньше кадров других голосов (кадры идут через hop).
    private func pickLead(_ v: Int, _ s: Int64) -> Int {
        let H = Vocoder.hop
        let blk: Int = Swift.max(1, block)
        let groups: Int = H / blk
        if groups < 2 { return 0 }
        let b64 = Int64(blk)
        let g64 = Int64(groups)
        var best = 0
        var bestN = Int.max
        var c = 0
        while c < groups {
            let d: Int = c * blk
            let at: Int64 = s + Int64(H - d - 1)
            let g: Int64 = ((at / b64) % g64 + g64) % g64
            var cnt = 0
            var u = 0
            while u < slots {
                let x: Int64 = nextAt[u]
                if u != v && x >= s && ((x / b64) % g64 + g64) % g64 == g { cnt += 1 }
                u += 1
            }
            if cnt < bestN {
                bestN = cnt
                best = d
            }
            c += 1
        }
        return best
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
        let x0: Double = c - Double(N / 2) * step
        // Весь кадр внутри куска и сэмпла — векторно (PvCubic).
        if cub.read(p, frames, x0, step, N, lo, hi, out) {
            if !raw { pvMul(out, win, out, N) }
            return
        }
        let w = win
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
        if stereo {
            pvAdd(reL, reR, reM, B)
            pvAdd(imL, imR, imM, B)
        } else {
            reM.update(from: reL, count: B)
            imM.update(from: imL, count: B)
        }
        #if canImport(Accelerate)
        var n32 = Int32(B)
        vvatan2f(ph, imM, reM, &n32)
        var sp = DSPSplitComplex(realp: reM, imagp: imM)
        vDSP_zvabs(&sp, 1, mag, 1, vDSP_Length(B))
        #else
        var k = 0
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
        let R = Vocoder.ring
        let c0: Double = t0 + Double(N / 2) * step
        read(l, frames, c0, step, lo, hi, fL, raw: true)
        if stereo { read(r, frames, c0, step, lo, hi, fR, raw: true) }
        let a = ringAt[v]
        pvRingMa(ringL + v * R, R, a, fL, firstW, N)
        pvMul(fL, win, fL, N)
        if stereo {
            pvRingMa(ringR + v * R, R, a, fR, firstW, N)
            pvMul(fR, win, fR, N)
        }
        fft.forward(fL, reL, imL)
        if stereo { fft.forward(fR, reR, imR) }
        analyze(stereo)
        let b = v * B
        (prevAna + b).update(from: ph, count: B)
        (prevSyn + b).update(from: ph, count: B)
        (prevMag + b).update(from: mag, count: B)
        (instF + b).update(from: omg, count: B)
        prevC[v] = c0
        prevHit[v] = 1
    }

    /// Кадр с центром c (в сэмпле): анализ, фазы, синтез в кольцо через d отсчётов от текущей позиции.
    private func frame(_ v: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ frames: Int,
                       _ stereo: Bool, _ c: Double, _ step: Double, _ ratio: Double, _ lo: Double, _ hi: Double,
                       _ d: Int) {
        let N = Vocoder.size
        let B = Vocoder.bins
        let H = Float(Vocoder.hop)
        let R = Vocoder.ring
        read(l, frames, c, step, lo, hi, fL, raw: false)
        if stereo { read(r, frames, c, step, lo, hi, fR, raw: false) }
        fft.forward(fL, reL, imL)
        if stereo { fft.forward(fR, reR, imR) }
        analyze(stereo)
        let b = v * B
        let pa = prevAna + b, psy = prevSyn + b, pm = prevMag + b, fi = instF + b
        // Шаг анализа в отсчётах прочитанного кадра (со скоростью высоты).
        let ha: Float = Float(Swift.abs(c - prevC[v]) / Swift.max(1e-6, ratio))
        let twoPi: Float = 6.2831855
        let inv2Pi: Float = 0.15915494
        // Порог тишины и атака.
        let floor: Float = pvMax(mag, B) * 1e-3 + 1e-9
        // Атака (доля бинов, выросших больше чем на 6 dB) и пики (больше двух соседей с каждой стороны) — одним проходом.
        var rise = 0
        var live = 0
        var np = 0
        var k = 2
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
        // Мгновенная частота бина: разность фаз за вычетом хода бина, к −π…π; при скорости около 0 — прежняя.
        let iha: Float = ha > 1 ? 1 / ha : 0
        if ha > 1 && !reset {
            if np == 0 {
                pvSub(ph, pa, dc, B)
                pvSma(omg, -ha, dc, dc, B)
                pvWrap(dc, cub.ki, cub.kf, B)
                pvSma(dc, iha, omg, fi, B)
            } else {
                var p = 0
                while p < np {
                    let q0 = peaks[p]
                    let om: Float = omg[q0]
                    var dd: Float = ph[q0] - pa[q0] - om * ha
                    let q: Float = dd * inv2Pi
                    dd -= twoPi * Float(Int(q >= 0 ? q + 0.5 : q - 0.5))
                    fi[q0] = om + dd * iha
                    p += 1
                }
            }
        }
        // Фаза синтеза: атака — фазы анализа; без пиков — по частоте бина; иначе у пика — по его частоте, бины его
        // области (до середины между пиками) держат прежнюю разность с пиком (фазовая привязка). Затем — к −π…π.
        if reset {
            psy.update(from: ph, count: B)
        } else if np == 0 {
            pvSma(fi, H, psy, psy, B)
        } else {
            var s0 = 0
            var p = 0
            while p < np {
                let q0 = peaks[p]
                let end: Int = p + 1 < np ? (q0 + peaks[p + 1]) / 2 + 1 : B
                let base: Float = psy[q0] + fi[q0] * H - ph[q0]
                pvSAdd(ph + s0, base, psy + s0, end - s0)
                s0 = end
                p += 1
            }
        }
        pvWrap(psy, cub.ki, cub.kf, B)
        pvSub(psy, ph, ds, B)
        pa.update(from: ph, count: B)
        pm.update(from: mag, count: B)
        // Поворот каналов на угол ds.
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
        pvRotate(reL, imL, dc, syn, B)
        if stereo { pvRotate(reR, imR, dc, syn, B) }
        fft.inverse(reL, imL, fL)
        if stereo { fft.inverse(reR, imR, fR) }
        let a0 = ringAt[v] + d
        pvRingMa(ringL + v * R, R, a0, fL, winG, N)
        if stereo { pvRingMa(ringR + v * R, R, a0, fR, winG, N) }
        prevC[v] = c
        framesDone += 1
    }
}
