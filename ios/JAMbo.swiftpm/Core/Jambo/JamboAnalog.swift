import Foundation

// ANALOG (весь движок; S12 + модуляция B осциллятором A (AnalogMod, решение пользователя 8.11): SYNC — B жёстко синхронизирован с A
// (высота B 0 → +24 полутона по AMOUNT, скачок сброса сглажен PolyBLEP), FM — A модулирует фазу B (индекс 0 → 1 период
// по AMOUNT², PolyBLEP с мгновенным шагом фазы), RING — B плавно переходит в A·B. AMOUNT — ручка 1.3 (s3), расстройки
// нет; MIX — A ↔ B, как без модуляции. Смена режима — кроссфейд прежнего и нового за 5 мс (mMix). A и свободный B —
// те же, что в JamboVoice.analog (треугольник — интеграл квадрата), их состояние ведётся всегда: выключение модуляции
// продолжает волну без разрыва. Помощники — копии из JamboVoice.swift (в отладочной сборке встраивание — только внутри
// файла).

@_transparent private func mFloor(_ x: Double) -> Double {
    let f = Double(Int(x))
    return f > x ? f - 1 : f
}

@_transparent private func mSin(_ table: UnsafePointer<Double>, _ ph: Double) -> Double {
    var x = ph - mFloor(ph)
    x *= 4096
    let i = Int(x)
    let a = table[i], b = table[i + 1]
    return a + (b - a) * (x - Double(i))
}

@_transparent private func mBlep(_ t0: Double, _ dt: Double) -> Double {
    if t0 < dt {
        let t = t0 / dt
        return t + t - t * t - 1
    }
    if t0 > 1 - dt {
        let t = (t0 - 1) / dt
        return t * t + t + t + 1
    }
    return 0
}

@_transparent private func mTriAt(_ ph: Double) -> Double { 1 - 4 * abs(ph < 0.75 ? ph - 0.25 : ph - 1.25) }

/// Отсчёт формы k в редких местах (кроссфейды, ведомый SYNC, FM, скачки сброса) — вызовом, а не копией кода в каждом
/// месте (объём сборки): how 0 — свободный осциллятор (треугольник — интеграл tri), 1 — без сглаживания,
/// 2 — PolyBLEP по шагу dt (треугольник — по фазе).
@inline(never) private func mWave(_ sine: UnsafePointer<Double>, _ k: Int, _ a: Double, _ dt: Double, _ tri: Double,
                                  _ how: Int) -> Double {
    if k == 0 { return mSin(sine, a) }
    if k == 1 { return how == 0 ? tri : mTriAt(a) }
    if how == 1 { return k == 2 ? 1 - 2 * a : (a < 0.5 ? 1 : -1) }
    if k == 2 { return 1 - 2 * a + mBlep(a, dt) }
    return (a < 0.5 ? 1 : -1) + mBlep(a, dt) - mBlep(a < 0.5 ? a + 0.5 : a - 0.5, dt)
}

/// Форма свободного осциллятора (как jShapeAt: треугольник — интеграл tri) — горячий путь, встраивается.
@_transparent private func mFree(_ sine: UnsafePointer<Double>, _ k: Int, _ a: Double, _ dt: Double,
                                 _ tri: Double) -> Double {
    if k == 0 { return mSin(sine, a) }
    if k == 1 { return tri }
    if k == 2 { return 1 - 2 * a + mBlep(a, dt) }
    return (a < 0.5 ? 1 : -1) + mBlep(a, dt) - mBlep(a < 0.5 ? a + 0.5 : a - 0.5, dt)
}

@_transparent private func mHalf(_ x: UnsafeMutablePointer<Double>, _ k: UnsafeMutablePointer<Double>, _ kc: Double) -> Double {
    var a: Double = k[0] * (x[-1] + x[1])
    a += k[1] * (x[-3] + x[3])
    a += k[2] * (x[-5] + x[5])
    a += k[3] * (x[-7] + x[7])
    a += k[4] * (x[-9] + x[9])
    a += k[5] * (x[-11] + x[11])
    a += k[6] * (x[-13] + x[13])
    a += k[7] * (x[-15] + x[15])
    a += k[8] * (x[-17] + x[17])
    a += k[9] * (x[-19] + x[19])
    a += k[10] * (x[-21] + x[21])
    a += k[11] * (x[-23] + x[23])
    a += k[12] * (x[-25] + x[25])
    a += k[13] * (x[-27] + x[27])
    a += k[14] * (x[-29] + x[29])
    a += k[15] * (x[-31] + x[31])
    return a + kc * x[0]
}

@_transparent private func mFlush(_ x: Double) -> Double { (x > 1e-20 || x < -1e-20) ? x : 0 }

extension JamboVoice {
    /// Кусок ANALOG (без модуляции — как прежде: DETUNE, MIX; с модуляцией и в кроссфейде режимов — SYNC, FM, RING):
    /// ×2 передискретизация и полуполосный фильтр. Один путь на все режимы (объём сборки).
    func analog(_ out: UnsafeMutablePointer<Float>, _ n: Int, _ ratio: Double) {
        let sr2: Double = sr * 2
        let sine = UnsafePointer(tables.sineD)
        let f0: Double = 440 * pow(2, (note - 69) / 12) * ratio
        let fB: Double = (aOct ? 0.5 : 1) * f0
        let amt: Double = Swift.min(1, Swift.max(0, s3))
        // DETUNE (1.3, без модуляции): A вверх, B вниз, в сумме 0…60 центов по кривой x².
        let det: Double = mCur == 0 ? Jambo.analogDetune / 2 * s3 * s3 : 0
        let dt1: Double = Swift.min(0.45, f0 * pow(2, det / 1200) / sr2)
        let dt2: Double = Swift.min(0.45, fB * pow(2, -det / 1200) / sr2)
        // SYNC: B выше A на 0…24 полутона (AnalogMod.syncSt), FM: индекс по AMOUNT².
        let dt3: Double = Swift.min(0.45, fB * pow(2, amt * 2) / sr2)
        let fmIdx: Double = Jambo.analogFmIndex * amt * amt
        let ia = Jambo.waveIndex(t1)
        if ia != wCur {
            wPrev = wCur
            wCur = ia
            wMix = 0
        }
        let ib = Jambo.waveIndex(t2)
        if ib != bCur {
            bPrev = bCur
            bCur = ib
            bMix = 0
        }
        let ca = wCur, pa = wPrev, cb = bCur, pb = bPrev
        let gA = Double(tables.shapeGain[ca]), gAp = Double(tables.shapeGain[pa])
        let gB = Double(tables.shapeGain[cb]), gBp = Double(tables.shapeGain[pb])
        let xfStep: Double = 1 / (Jambo.analogWaveXf * sr2)
        var mixA = wMix, mixB = bMix
        let ang: Double = s4 * Double.pi / 2
        let ka: Double = cos(ang), kb: Double = sin(ang)
        let wa: Double = Jambo.analogOut * ka / (ka + kb), wb: Double = Jambo.analogOut * kb / (ka + kb)
        let cm: Int = mCur, pm: Int = mPrev
        var mx: Double = mMix
        let needS: Bool = cm == 1 || (mx < 1 && pm == 1)
        let needF: Bool = cm == 2 || (mx < 1 && pm == 2)
        let leak: Double = 1 - 20 / sr2
        var o1 = a1, o2 = a2, tr1 = tri1, tr2 = tri2, s = o3, pf = pB, after = sAfter, hp = hbPos
        let buf = hb, len = Jambo.hbLen
        let hk = tables.hbHK, kC = tables.hbCK, mid = Jambo.hbLen / 2
        var i = 0
        while i < n {
            var j = 0
            while j < 2 {
                let b1 = o1 < 0.75 ? o1 + 0.25 : o1 - 0.75, b2 = o2 < 0.75 ? o2 + 0.25 : o2 - 0.75
                tr1 = tr1 * leak + 4 * dt1 * ((b1 < 0.5 ? 1 : -1) + mBlep(b1, dt1) - mBlep(b1 < 0.5 ? b1 + 0.5 : b1 - 0.5, dt1))
                tr2 = tr2 * leak + 4 * dt2 * ((b2 < 0.5 ? 1 : -1) + mBlep(b2, dt2) - mBlep(b2 < 0.5 ? b2 + 0.5 : b2 - 0.5, dt2))
                // Смена формы — кроссфейд 5 мс (доля растёт до смешивания, как прежде).
                var xa: Double = gA * mFree(sine, ca, o1, dt1, tr1)
                if mixA < 1 {
                    mixA = Swift.min(1, mixA + xfStep)
                    let old: Double = gAp * mWave(sine, pa, o1, dt1, tr1, 0)
                    xa = old + (xa - old) * mixA
                }
                var xb: Double = gB * mFree(sine, cb, o2, dt2, tr2)
                if mixB < 1 {
                    mixB = Swift.min(1, mixB + xfStep)
                    let old: Double = gBp * mWave(sine, pb, o2, dt2, tr2, 0)
                    xb = old + (xb - old) * mixB
                }
                var vS = 0.0, vF = 0.0
                // SYNC: ведомый B — форма без сглаживания; все его скачки (свои и сброс) — поправкой PolyBLEP ниже.
                let kS: Double = mixB
                if needS {
                    vS = gB * mWave(sine, cb, s, dt3, 0, 1)
                    if kS < 1 {
                        let old: Double = gBp * mWave(sine, pb, s, dt3, 0, 1)
                        vS = old + (vS - old) * kS
                    }
                }
                if needF {
                    var p: Double = o2 + fmIdx * xa
                    p -= mFloor(p)
                    var d: Double = p - pf
                    if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
                    let dte: Double = Swift.min(0.45, Swift.max(1e-5, abs(d)))
                    vF = gB * mWave(sine, cb, p, dte, 0, 2)
                    if kS < 1 {
                        let old: Double = gBp * mWave(sine, pb, p, dte, 0, 2)
                        vF = old + (vF - old) * kS
                    }
                    pf = p
                } else {
                    pf = o2
                }
                let vR: Double = xb + (xa * xb - xb) * amt
                var bOut: Double = cm == 0 ? xb : (cm == 1 ? vS : (cm == 2 ? vF : vR))
                var wS: Double = cm == 1 ? 1 : 0
                if mx < 1 {
                    mx = Swift.min(1, mx + xfStep)
                    let old: Double = pm == 0 ? xb : (pm == 1 ? vS : (pm == 2 ? vF : vR))
                    bOut = old + (bOut - old) * mx
                    wS = (cm == 1 ? mx : 0) + (pm == 1 ? 1 - mx : 0)
                }
                var y: Double = wa * xa + wb * bOut
                if after != 0 {
                    y += after
                    after = 0
                }
                o1 += dt1
                let wrap: Bool = o1 >= 1
                if wrap { o1 -= 1 }
                o2 += dt2
                if o2 >= 1 { o2 -= 1 }
                if needS {
                    // События до следующего отсчёта (τ — доля отсчёта от этого): свои скачки ведомого (пила и квадрат
                    // в фазе 0, квадрат — в 0.5) до сброса и сам сброс (A прошёл период). Скачок h в τ: этому
                    // отсчёту + h/2·(1 − τ)², следующему − h/2·τ².
                    let tr: Double = wrap ? 1 - o1 / dt1 : 2
                    let g: Double = wS * wb
                    var corr = 0.0, nextC = 0.0
                    if cb >= 2 || (kS < 1 && pb >= 2) {
                        // Скачок формы в фазе: пила и квадрат +2 в 0, квадрат −2 в 0.5 (смесь форм — по kS).
                        let jc0: Double = cb >= 2 ? 2 * gB : 0, jp0: Double = pb >= 2 ? 2 * gBp : 0
                        let jc5: Double = cb == 3 ? -2 * gB : 0, jp5: Double = pb == 3 ? -2 * gBp : 0
                        let j0: Double = (jp0 + (jc0 - jp0) * kS) * g, j5: Double = (jp5 + (jc5 - jp5) * kS) * g
                        let tw: Double = (1 - s) / dt3
                        if tw <= 1 && tw < tr {
                            corr += j0 / 2 * (1 - tw) * (1 - tw)
                            nextC -= j0 / 2 * tw * tw
                        }
                        if s < 0.5 {
                            let th: Double = (0.5 - s) / dt3
                            if th <= 1 && th < tr {
                                corr += j5 / 2 * (1 - th) * (1 - th)
                                nextC -= j5 / 2 * th * th
                            }
                        }
                    }
                    var sn: Double = s + dt3
                    if sn >= 1 { sn -= 1 }
                    if wrap {
                        // Сброс в τ = tr: фаза ведомого в этот миг → 0, затем ещё (1 − tr)·dt3.
                        var at: Double = s + dt3 * tr
                        if at >= 1 { at -= 1 }
                        var old: Double = gB * mWave(sine, cb, at, 0, 0, 1)
                        var new: Double = gB * mWave(sine, cb, 0, 0, 0, 1)
                        if kS < 1 {
                            let po: Double = gBp * mWave(sine, pb, at, 0, 0, 1)
                            let pn: Double = gBp * mWave(sine, pb, 0, 0, 0, 1)
                            old = po + (old - po) * kS
                            new = pn + (new - pn) * kS
                        }
                        let h: Double = (new - old) * g
                        corr += h / 2 * (1 - tr) * (1 - tr)
                        nextC -= h / 2 * tr * tr
                        sn = (1 - tr) * dt3
                    }
                    y += corr
                    after = nextC
                    s = sn
                } else {
                    s = o2
                }
                let yf = Double(Float(y))
                buf[hp] = yf
                buf[hp + len] = yf
                hp = hp + 1 == len ? 0 : hp + 1
                j += 1
            }
            out[i] = Float(mHalf(buf + hp + mid, hk, kC))
            i += 1
        }
        wMix = mixA
        bMix = mixB
        mMix = mx
        if mx >= 1 { mPrev = cm }
        a1 = o1
        a2 = o2
        o3 = s
        pB = pf
        sAfter = after
        tri1 = mFlush(tr1)
        tri2 = mFlush(tr2)
        hbPos = hp
        t += Double(n)
    }
}
