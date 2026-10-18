import Foundation

// Микшер дорожек (вынесен из Sampler.swift): громкость, mute/solo, Sidechain, посылы; пики дорожек для метров
// и сигнал показанной дорожки для LUFS (Levels); выходы дорожек (outL, outR) — источники динамических полос EQ,
// дорожки — в порядке SoundData.eqOrder.

extension Sampler {
    /// Микшер: шина дорожки → EQ → · (1 − amount·e) · громкость · гейт → выход; посылы · громкость · гейт
    /// (· (1 − amount·e), если посыл приглушается — SETTINGS → SIDECHAIN) → входы шин эффектов.
    func mix(_ d: SoundData, _ n: Int, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) {
        // Гейт mute/solo — за ~5 мс (постоянная 1,5 мс), громкость — за ~10 мс, глубина Sidechain и переключатели
        // посылов — за ~10 мс (постоянная 3,3 мс).
        let gk = Float(1 - exp(-1 / (0.0015 * sr)))
        let vk = Float(1 - exp(-1 / (0.01 * sr)))
        let dk = Float(1 - exp(-1 / (0.0033 * sr)))
        let rack = fx
        let eBuf: UnsafeMutablePointer<Float>? = rack?.e
        let source: Int = rack?.source ?? -1
        // Переключатели посылов — общие для дорожек (сглаживание на блок).
        var fl0: Float = 0, fl1: Float = 0, fl2: Float = 0
        if rack != nil {
            var k = 0
            while k < 3 {
                if flagCur[k] < 0 { flagCur[k] = d.scSend[k] }
                flagCur[k] += (d.scSend[k] - flagCur[k]) * Swift.min(1, dk * Float(n))
                k += 1
            }
            fl0 = flagCur[0]; fl1 = flagCur[1]; fl2 = flagCur[2]
        }
        // Наибольшая огибающая Sidechain в блоке — для приглушения на метрах MIX.
        var eMax: Float = 0
        if let eb = eBuf {
            var i = 0
            while i < n {
                if eb[i] > eMax { eMax = eb[i] }
                i += 1
            }
        }
        let lv = levels
        // Громкость с p-lock играющего шага MIX (как liveMixer веба).
        let lockMask: UInt16 = mixLockMask?.pointee ?? 0
        let lockGain: UnsafeMutablePointer<Float>? = mixLockGain
        let mf = Sampler.maxFrames
        var oi = 0
        while oi < d.trackCount {
            let t: Int = d.eqOrder[oi]
            oi += 1
            let ol = outL + t * mf
            let or = outR + t * mf
            var vt: Float = d.gain[t]
            if lockMask & (UInt16(1) << UInt16(t)) != 0, let g = lockGain { vt = g[t] }
            let gt: Float = d.open[t] != 0 ? 1 : 0
            let at: Float = t == source ? 0 : Swift.max(0, Swift.min(1, d.scAmount[t] / 100))
            if volCur[t] < 0 { volCur[t] = vt }
            if gateCur[t] < 0 { gateCur[t] = gt }
            let meter: UnsafeMutablePointer<Float>? = lv?.current(t)
            let loud: Bool = lv?.loudness.listens(t) ?? false
            if used[t] == 0 {
                volCur[t] = vt
                gateCur[t] = gt
                duckCur[t] = at
                meter?[2] = at * eMax
                ol.update(repeating: 0, count: n)
                or.update(repeating: 0, count: n)
                idleEq(t, d, n)
                continue
            }
            trackEq(t, d, n, sends: rack != nil)
            let bl = busL + t * Sampler.maxFrames
            let br = busR + t * Sampler.maxFrames
            let ml = meterL, mr = meterR
            var vol = volCur[t]
            var gate = gateCur[t]
            var amt = duckCur[t]
            var pl: Float = 0, pr: Float = 0
            if let r = rack, let eb = eBuf {
                let s0L = sendL + t * 3 * Sampler.maxFrames, s0R = sendR + t * 3 * Sampler.maxFrames
                let i0L = r.inL, i0R = r.inR
                var i = 0
                while i < n {
                    vol += (vt - vol) * vk
                    gate += (gt - gate) * gk
                    amt += (at - amt) * dk
                    let g: Float = vol * gate
                    let de: Float = amt * eb[i]
                    // Метр — после громкости и Sidechain, до mute/solo (узел vol веба).
                    let pv: Float = vol * (1 - de)
                    let xl: Float = bl[i] * pv
                    let xr: Float = br[i] * pv
                    ol[i] = xl
                    or[i] = xr
                    left[i] += xl * gate
                    right[i] += xr * gate
                    let al: Float = xl < 0 ? -xl : xl
                    let ar: Float = xr < 0 ? -xr : xr
                    if al > pl { pl = al }
                    if ar > pr { pr = ar }
                    if loud {
                        ml[i] = xl
                        mr[i] = xr
                    }
                    // Посылы Reverb, Delay, Drive.
                    var gs: Float = g * (1 - fl0 * de)
                    i0L[i] += s0L[i] * gs
                    i0R[i] += s0R[i] * gs
                    gs = g * (1 - fl1 * de)
                    i0L[mf + i] += s0L[mf + i] * gs
                    i0R[mf + i] += s0R[mf + i] * gs
                    gs = g * (1 - fl2 * de)
                    i0L[2 * mf + i] += s0L[2 * mf + i] * gs
                    i0R[2 * mf + i] += s0R[2 * mf + i] * gs
                    i += 1
                }
            } else {
                var i = 0
                while i < n {
                    vol += (vt - vol) * vk
                    gate += (gt - gate) * gk
                    let xl: Float = bl[i] * vol
                    let xr: Float = br[i] * vol
                    ol[i] = xl
                    or[i] = xr
                    left[i] += xl * gate
                    right[i] += xr * gate
                    let al: Float = xl < 0 ? -xl : xl
                    let ar: Float = xr < 0 ? -xr : xr
                    if al > pl { pl = al }
                    if ar > pr { pr = ar }
                    if loud {
                        ml[i] = xl
                        mr[i] = xr
                    }
                    i += 1
                }
            }
            volCur[t] = vol
            gateCur[t] = gate
            duckCur[t] = amt
            if let m = meter {
                m[0] = pl
                m[1] = pr
                m[2] = amt * eMax
            }
            if loud, let l = lv { l.loudness.process(UnsafePointer(ml), UnsafePointer(mr), n) }
        }
        // Дорожек нет — выходы молчат (источник удалённой дорожки не держит последний блок).
        var t = d.trackCount
        while t < SoundData.maxTracks {
            (outL + t * mf).update(repeating: 0, count: n)
            (outR + t * mf).update(repeating: 0, count: n)
            t += 1
        }
    }
}
