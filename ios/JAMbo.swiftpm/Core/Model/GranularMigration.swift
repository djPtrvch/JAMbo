import Foundation

// Версия 6 (ТЗ «Granular»): ручки GRANULAR по новым формулам, звук — как раньше (решение пользователя). Прежние
// формулы: SIZE 0,005·100^v (5…500 мс), DENSITY 2·40^v зёрен в секунду, SPRAY — разброс позиции ±0,35·SPRAY.
// Новые: SIZE 0,01·80^v (10…800 мс), DENSITY 0,5·48^v зёрен одновременно (= частота · длина), SPRAY — позиция
// ±0,2·SPRAY². Переводятся: длина зерна (короче 10 мс — 10 мс), частота зёрен (одновременно = частота · длина; вне
// 0,5…24 — край), разброс позиции (sp' = √(1,75·sp); выше 57 % — край 100 %). POSITION не меняется. Назначения LFO/ENV
// (глубина) не переводятся. Где: ручки дорожек, звуков перехода MIX и MORPH, p-lock шагов (паттерны и блоки
// аранжировки), кривые аранжировки, пресеты (fmt < 4).

public enum GranularMigration {
    /// Новые SIZE, DENSITY, SPRAY (0…100) по прежним.
    public static func knobs(size s: Double, density d: Double, spray p: Double) -> (s: Double, d: Double, p: Double) {
        let sec: Double = 0.005 * pow(100, s / 100)
        let rate: Double = 2 * pow(40, d / 100)
        let ns: Double = 100 * log(Swift.max(0.01, sec) / 0.01) / log(80)
        let nd: Double = 100 * log(Swift.max(0.5, rate * sec) / 0.5) / log(48)
        let np: Double = 100 * (1.75 * Swift.max(0, p) / 100).squareRoot()
        let c: (Double) -> Double = { Swift.min(100, Swift.max(0, $0)) }
        return (c(ns), c(nd), c(np))
    }

    /// Ручки звука (дорожка, пресет) GRANULAR.
    static func params(_ sound: String, _ p: inout [String: Double]) {
        guard SynthKey.engine(sound) == Jambo.granular else { return }
        let r = knobs(size: p["timbre"] ?? 50, density: p["morph"] ?? 50, spray: p["p4"] ?? 50)
        if p["timbre"] != nil { p["timbre"] = r.s }
        if p["morph"] != nil { p["morph"] = r.d }
        if p["p4"] != nil { p["p4"] = r.p }
    }

    /// P-lock шага: поставленные ручки; base — прежние ручки звука (SIZE для DENSITY без своего SIZE).
    static func locks(_ l: inout [String: Double], base: [String: Double]) {
        let hs = l["timbre"] != nil, hd = l["morph"] != nil, hp = l["p4"] != nil
        if !hs && !hd && !hp { return }
        let r = knobs(size: l["timbre"] ?? base["timbre"] ?? 50, density: l["morph"] ?? 50, spray: l["p4"] ?? 0)
        if hs { l["timbre"] = r.s }
        if hd { l["morph"] = r.d }
        if hp { l["p4"] = r.p }
    }

    /// Кривые ручек (y 0…1 = ручка 0…100); base — прежние ручки звука.
    static func lanes(_ ls: inout [ArrAutoLane], base: [String: Double]) {
        for k in 0..<ls.count {
            let id = ls[k].param
            if id != "timbre" && id != "morph" && id != "p4" { continue }
            for i in 0..<ls[k].points.count {
                let v: Double = ls[k].points[i].y * 100
                let r = knobs(size: id == "timbre" ? v : base["timbre"] ?? 50, density: v, spray: v)
                let n: Double = id == "timbre" ? r.s : (id == "morph" ? r.d : r.p)
                ls[k].points[i].y = n / 100
            }
        }
    }

    static func clip(_ c: inout Clip, own sample: String, base: [String: Double]) {
        for p in 0..<c.pages.count {
            for s in 0..<c.pages[p].count {
                guard SynthKey.engine(c.pages[p][s].sound ?? sample) == Jambo.granular else { continue }
                locks(&c.pages[p][s].locks, base: base)
            }
        }
    }
}

extension Project {
    /// Версия 6: ручки GRANULAR (GranularMigration). Шаги и кривые — по прежним ручкам звука, потом сами ручки.
    mutating func migrateGranular() {
        for i in 0..<tracks.count {
            var t = tracks[i]
            let base: [String: Double] = t.params
            for k in 0..<t.clips.count {
                guard var c = t.clips[k] else { continue }
                let snd: String = c.src?.sample ?? t.sample
                let b: [String: Double] = c.src?.params ?? base
                GranularMigration.clip(&c, own: snd, base: b)
                if var src = c.src {
                    GranularMigration.params(src.sample, &src.params)
                    c.src = src
                }
                t.clips[k] = c
            }
            for k in 0..<t.blocks.count {
                if var c = t.blocks[k].pattern {
                    GranularMigration.clip(&c, own: t.sample, base: base)
                    t.blocks[k].pattern = c
                }
                if SynthKey.engine(t.sample) == Jambo.granular {
                    GranularMigration.lanes(&t.blocks[k].autos, base: base)
                }
            }
            if SynthKey.engine(t.sample) == Jambo.granular {
                GranularMigration.lanes(&t.autos, base: base)
                // MORPH: исходные ручки — в тех же единицах.
                var mo: [String: Double] = t.morphOrig
                let had = (mo["timbre"], mo["morph"], mo["p4"])
                var full: [String: Double] = base.merging(mo) { _, v in v }
                GranularMigration.params(t.sample, &full)
                if had.0 != nil { mo["timbre"] = full["timbre"] }
                if had.1 != nil { mo["morph"] = full["morph"] }
                if had.2 != nil { mo["p4"] = full["p4"] }
                t.morphOrig = mo
            }
            GranularMigration.params(t.sample, &t.params)
            if var h = t.home {
                GranularMigration.params(h.sample, &h.params)
                t.home = h
            }
            tracks[i] = t
        }
    }
}
