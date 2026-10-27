import Foundation

// Варпинг в снимке звука и в голосе (WARP, Warp.swift). Голос в Rate Stretch ведёт указатель в «отсчётах темпа
// файла» (u = доля · отсчётов на долю: без меток совпадает с отсчётом сэмпла) — скорость, края и огибающая прежние;
// отсчёт сэмпла — по карте меток (между метками — линейно, за крайними — наклон 1). Таймстретч получает позицию
// и скорость куска по карте.

extension SoundSnapshot {
    static let maxWarps = 8192

    static func allocWarp(_ d: inout SoundData) {
        let e = SoundData.maxEntries
        let w = maxWarps
        let s = UnsafeMutablePointer<Int32>.allocate(capacity: e)
        s.initialize(repeating: 0, count: e)
        let c = UnsafeMutablePointer<Int32>.allocate(capacity: e)
        c.initialize(repeating: 0, count: e)
        let u = UnsafeMutablePointer<Double>.allocate(capacity: w)
        u.initialize(repeating: 0, count: w)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: w)
        p.initialize(repeating: 0, count: w)
        d.eWarpStart = s
        d.eWarpCount = c
        d.warpU = u
        d.warpP = p
    }

    static func freeWarp(_ d: SoundData) {
        d.eWarpStart?.deallocate()
        d.eWarpCount?.deallocate()
        d.warpU?.deallocate()
        d.warpP?.deallocate()
    }

    /// Метки сэмпла s записи e (info — только у дорожки в TSTR; nil — без варпинга): свой BPM файла — в eBpm (с метками —
    /// и определённый сам или 120), метки — с позиции w таблиц.
    static func putWarp(_ d: inout SoundData, _ e: Int, _ w: inout Int, _ info: WarpInfo?, _ s: SampleData) {
        d.eWarpStart![e] = Int32(w)
        d.eWarpCount![e] = 0
        guard let wi = info else { return }
        if wi.marks.isEmpty {
            if let b = wi.bpm { d.eBpm[e] = b }
            return
        }
        let bpm: Double = WarpMap.bpm(wi, detected: s.loopBpm)
        d.eBpm[e] = bpm
        let map = WarpMap(wi, frames: s.frames, bpm: bpm)
        var n = 0
        while n < map.pos.count && w + n < maxWarps {
            d.warpU![w + n] = map.beats[n] * map.perBeat
            d.warpP![w + n] = map.pos[n]
            n += 1
        }
        d.eWarpCount![e] = Int32(n)
        w += n
    }
}

extension Sampler {
    /// Отсчёт сэмпла голоса v для указателя x (карта меток; без меток — сам x).
    @inline(__always)
    func warpPos(_ v: Int, _ x: Double) -> Double {
        let n = warpN[v]
        if n == 0 { return x }
        let us = warpU + v * Sampler.warpCap
        let ps = warpP + v * Sampler.warpCap
        if x <= us[0] { return ps[0] - (us[0] - x) }
        if x >= us[n - 1] { return ps[n - 1] + (x - us[n - 1]) }
        var k = 1
        while us[k] < x { k += 1 }
        let f: Double = (x - us[k - 1]) / Swift.max(1e-9, us[k] - us[k - 1])
        return ps[k - 1] + f * (ps[k] - ps[k - 1])
    }

    /// Указатель для отсчёта сэмпла p (обратная карта).
    func warpInv(_ v: Int, _ p: Double) -> Double {
        let n = warpN[v]
        if n == 0 { return p }
        let us = warpU + v * Sampler.warpCap
        let ps = warpP + v * Sampler.warpCap
        if p <= ps[0] { return us[0] - (ps[0] - p) }
        if p >= ps[n - 1] { return us[n - 1] + (p - ps[n - 1]) }
        var k = 1
        while ps[k] < p { k += 1 }
        let f: Double = (p - ps[k - 1]) / Swift.max(1e-9, ps[k] - ps[k - 1])
        return us[k - 1] + f * (us[k] - us[k - 1])
    }
}

extension Sampler {
    /// Метки записи e снимка d — в голос v (копия: снимок может смениться, пока голос звучит); указатель u — от
    /// начального отсчёта.
    func setupWarp(_ v: Int, _ d: SoundData, _ e: Int, _ ts: Bool) {
        var n = 0
        if ts, let cs = d.eWarpCount, let ss = d.eWarpStart, let us = d.warpU, let ps = d.warpP {
            let a = Int(ss[e])
            let c = Swift.min(Int(cs[e]), Sampler.warpCap)
            let b = v * Sampler.warpCap
            while n < c {
                warpU[b + n] = us[a + n]
                warpP[b + n] = ps[a + n]
                n += 1
            }
        }
        warpN[v] = n
        uPos[v] = warpInv(v, pos[v])
    }

    /// Кусок m отсчётов с варпингом: отсчёт сэмпла в начале — по карте, u — вперёд на rate·m; скорость в отсчётах сэмпла.
    func warpChunk(_ v: Int, _ rate: Double, _ m: Int) -> Double {
        let u0: Double = uPos[v]
        let u1: Double = u0 + rate * Double(m)
        let p0: Double = warpPos(v, u0)
        let p1: Double = warpPos(v, u1)
        pos[v] = p0
        uPos[v] = u1
        return (p1 - p0) / Double(m)
    }
}
