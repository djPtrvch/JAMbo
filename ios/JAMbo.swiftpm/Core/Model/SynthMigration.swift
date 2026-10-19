import Foundation

// Версия 4 (S12, этап 2): ручки своих движков после появления 1.4. Звук прежний, кроме суба ANALOG (убран; дорожки
// с SUB > 0 — в сообщении при открытии) и длины клика KICK (CLICK ≠ 50 % — до 1 мс короче или длиннее).
// Переводятся ручки дорожек и звуков перехода MIX, p-lock шагов, назначения LFO/ENV и пресеты (fmt < 3).

public enum SynthMigration {
    /// Ручки 1.1–1.4 (0…100) движка e после S12 по прежним 1.1–1.3; lostSub — у ANALOG был суб.
    public static func knobs(_ e: Int, _ h: Double, _ t: Double, _ m: Double) -> (h: Double, t: Double, m: Double,
                                                                                  p4: Double, lostSub: Bool) {
        switch e {
        case Jambo.drum:
            // CLICK — прежний уровень клика (он шёл от DRIVE).
            return (h, t, m, m, false)
        case Jambo.analog:
            // A и B — прежний WAVE, DETUNE — прежний (с 1.2 на 1.3), MIX 50 %; SUB пропадает.
            return (h, h, t, 50, m > 0)
        case Jambo.wtable:
            // UNISON до 25 % — один голос (середина пункта 1), выше — три (пункт 3); DETUNE — прежние центы.
            if m <= 25 { return (h, t, 100.0 / 6, 50, false) }
            let cents: Double = Jambo.wtUnisonOld * (m - 25) / 75
            return (h, t, 50, cents / Jambo.wtDetune * 100, false)
        default:
            return (h, t, m, 50, false)
        }
    }

    /// Ручки звука (дорожка, пресет): по движку звука; true — пропал суб ANALOG.
    @discardableResult
    static func params(_ sound: String, _ p: inout [String: Double]) -> Bool {
        guard let e = SynthKey.engine(sound) else { return false }
        let r = knobs(e, p["harm"] ?? 50, p["timbre"] ?? 50, p["morph"] ?? 50)
        p["harm"] = r.h
        p["timbre"] = r.t
        p["morph"] = r.m
        p["p4"] = r.p4
        return r.lostSub
    }

    /// P-lock шага, который звучит движком e: переводятся только поставленные ручки.
    static func locks(_ e: Int, _ l: inout [String: Double]) {
        let has: [Bool] = ["harm", "timbre", "morph"].map { l[$0] != nil }
        if !has.contains(true) { return }
        let r = knobs(e, l["harm"] ?? 0, l["timbre"] ?? 0, l["morph"] ?? 0)
        switch e {
        case Jambo.drum:
            if has[2] { l["p4"] = r.p4 }
        case Jambo.analog:
            l["timbre"] = has[0] ? r.t : nil
            l["morph"] = has[1] ? r.m : nil
        case Jambo.wtable:
            if has[2] {
                l["morph"] = r.m
                l["p4"] = r.p4
            }
        default:
            break
        }
    }

    /// Назначения LFO/ENV: ANALOG — DETUNE с 1.2 на 1.3, SUB снимается; WTABLE — UNISON → DETUNE;
    /// KICK — DRIVE ещё и на CLICK.
    static func assigns(_ e: Int, _ a: inout [String: ModAssign]) {
        switch e {
        case Jambo.drum:
            if let m = a["morph"] { a["p4"] = m }
        case Jambo.analog:
            a["morph"] = a["timbre"]
            a["timbre"] = nil
        case Jambo.wtable:
            a["p4"] = a["morph"]
            a["morph"] = nil
        default:
            break
        }
    }
}

extension Project {
    /// Версия 4: ручки своих движков (SynthMigration); дорожки, где пропал суб ANALOG, — в notice.
    mutating func migrateSynthKnobs() {
        var lost: [String] = []
        for i in 0..<tracks.count {
            var t = tracks[i]
            let e: Int? = SynthKey.engine(t.sample)
            if SynthMigration.params(t.sample, &t.params) { lost.append(t.name) }
            if let e = e { SynthMigration.assigns(e, &t.assigns) }
            if var h = t.home {
                SynthMigration.params(h.sample, &h.params)
                if let he = SynthKey.engine(h.sample) { SynthMigration.assigns(he, &h.assigns) }
                t.home = h
            }
            for k in 0..<t.clips.count {
                guard var c = t.clips[k] else { continue }
                if var src = c.src {
                    SynthMigration.params(src.sample, &src.params)
                    if let se = SynthKey.engine(src.sample) { SynthMigration.assigns(se, &src.assigns) }
                    c.src = src
                }
                for p in 0..<c.pages.count {
                    for s in 0..<c.pages[p].count {
                        let own: String? = c.pages[p][s].sound
                        guard let se = SynthKey.engine(own ?? t.sample) else { continue }
                        SynthMigration.locks(se, &c.pages[p][s].locks)
                    }
                }
                t.clips[k] = c
            }
            tracks[i] = t
        }
        if !lost.isEmpty { notice = "SUB removed (ANALOG): " + lost.joined(separator: ", ") }
    }
}
