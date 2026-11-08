import Foundation

// Тип фильтра голоса (9.11, решение пользователя): ручка Filter — частота на всём ходу (Fmt.filterHz), SHIFT + тап
// по ней — тип. У всех движков и сэмплера — LP → HP → BP (12 dB); у SUB — LP → LADDER → BP. По умолчанию — LP.
// Значение звука дорожки (скрытое, Params.filterTypeId) и пресета, с пресет-локом; без p-lock шага, без LFO/ENV.

public enum FilterType {
    public static let lp = 0
    public static let hp = 1
    public static let bp = 2
    /// Лестничный фильтр 24 dB (Moog): только у SUB; GRIT — перегруз его входа.
    public static let ladder = 3
    public static let names: [String] = ["LP", "HP", "BP", "LAD"]

    /// Тип по значению звука (0…3; другое — LP).
    public static func of(_ v: Double?) -> Int {
        guard let v = v, v.isFinite else { return lp }
        let i: Int = Int(v.rounded())
        return i >= 0 && i <= ladder ? i : lp
    }

    /// Тип, который звучит у движка: LADDER — только у SUB (у других — LP).
    public static func effective(_ type: Int, sound: String) -> Int {
        if type == ladder && SynthKey.engine(sound) != Jambo.sub { return lp }
        return type
    }

    /// Следующий тип по SHIFT + тапу: SUB — LP → LADDER → BP, остальные — LP → HP → BP; back — предыдущий (SHIFT +
    /// двойной тап отменяет первый тап).
    public static func next(_ type: Int, sound: String, back: Bool = false) -> Int {
        let order: [Int] = SynthKey.engine(sound) == Jambo.sub ? [lp, ladder, bp] : [lp, hp, bp]
        let cur: Int = effective(type, sound: sound)
        guard let i = order.firstIndex(of: cur) else { return order[0] }
        return order[(i + (back ? order.count - 1 : 1)) % order.count]
    }

    /// Значение ручки при смене типа: открытый фильтр — открытый и у нового типа (BP — середина), иначе частота
    /// прежняя.
    public static func valueAfterSwitch(_ v: Double, from: Int, to: Int) -> Double {
        if Fmt.filterOpen(v, type: from) { return Params.filterDef(to).def }
        return v
    }
}

/// Перевод прежней двухполярной ручки Filter (до 9.11: влево — LP 20 кГц → 30 Гц, вправо — HP 20 Гц → 10 кГц,
/// в центре — выкл.) в тип и частоту на всём ходу. Частота та же; значения противоположного типа (LP при HP
/// дорожки и наоборот) — открытый фильтр (решение пользователя).
public enum FilterMigration {
    /// Тип прежнего значения: nil — выключен (центр).
    public static func oldType(_ v: Double) -> Int? {
        if Swift.abs(v) < 0.5 { return nil }
        return v < 0 ? FilterType.lp : FilterType.hp
    }

    /// Новое значение прежней ручки v у звука с типом type.
    public static func value(_ v: Double, type: Int) -> Double {
        guard let t = oldType(v), t == type else { return Params.filterDef(type).def }
        // LP: 20000·(30/20000)^(−v/100) Гц, HP: 20·500^(v/100) Гц → 100·log1000(Гц / 20).
        let n: Double = t == FilterType.lp ? 100 + v * log(20000.0 / 30) / log(1000) : v * log(500) / log(1000)
        return Swift.min(100, Swift.max(0, n))
    }

    /// Тип звука: по ручке звука; выключен — по большинству прежних значений шагов и кривых (HP — если их больше).
    public static func soundType(base: Double?, others: [Double]) -> Int {
        if let b = base, let t = oldType(b) { return t }
        var lp: Int = 0
        var hp: Int = 0
        for v in others {
            if let t = oldType(v) {
                if t == FilterType.lp { lp += 1 } else { hp += 1 }
            }
        }
        return hp > lp ? FilterType.hp : FilterType.lp
    }

    /// Ручки звука (дорожка, звук клипа, пресет): Filter — по типу, тип — в Params.filterTypeId.
    static func params(_ p: inout [String: Double], type: Int) {
        p[Params.filterTypeId] = Double(type)
        // Нет ручки — прежний центр (выкл.): открытый фильтр своего типа.
        p["filter"] = value(p["filter"] ?? 0, type: type)
    }

    /// Пресет: тип — по его ручке Filter (нет ручки — ничего не меняется).
    static func preset(_ p: inout [String: Double]) {
        guard p["filter"] != nil else { return }
        params(&p, type: soundType(base: p["filter"], others: []))
    }

    /// P-lock шага: Filter по типу звука; у пресет-лока — по своей ручке, тип — в его p-lock.
    static func locks(_ s: inout Step, type: Int) {
        guard let v = s.locks["filter"] else { return }
        if var sl = s.soundLocks, sl.contains("filter") {
            let own: Int = soundType(base: v, others: [])
            s.locks["filter"] = value(v, type: own)
            s.locks[Params.filterTypeId] = Double(own)
            if !sl.contains(Params.filterTypeId) { sl.append(Params.filterTypeId) }
            s.soundLocks = sl
            return
        }
        s.locks["filter"] = value(v, type: type)
    }

    static func clip(_ c: inout Clip, type: Int) {
        for p in 0..<c.pages.count {
            for k in 0..<c.pages[p].count { locks(&c.pages[p][k], type: type) }
        }
    }

    /// Кривые Filter (y 0…1 = ручка −100…100 → 0…100).
    static func lanes(_ ls: inout [ArrAutoLane], type: Int) {
        for k in 0..<ls.count where ls[k].param == "filter" {
            for i in 0..<ls[k].points.count {
                let v: Double = ls[k].points[i].y * 200 - 100
                ls[k].points[i].y = value(v, type: type) / 100
            }
        }
    }

    /// Прежние значения шагов (без пресет-локов) и кривых — для типа звука, у которого ручка выключена.
    static func used(_ t: Track) -> [Double] {
        var out: [Double] = []
        let add: (Clip) -> Void = { c in
            for page in c.pages {
                for s in page where !(s.soundLocks ?? []).contains("filter") {
                    if let v = s.locks["filter"] { out.append(v) }
                }
            }
        }
        for c in t.clips { if let c = c, c.src == nil { add(c) } }
        for b in t.blocks { if let c = b.pattern { add(c) } }
        var lanes: [ArrAutoLane] = t.autos
        for b in t.blocks { lanes += b.autos }
        for l in lanes where l.param == "filter" {
            for p in l.points { out.append(p.y * 200 - 100) }
        }
        return out
    }
}

extension Project {
    /// Версия 9 (9.11): ручка Filter — частота на всём ходу и тип фильтра (FilterMigration).
    mutating func migrateFilter() {
        for i in 0..<tracks.count {
            var t = tracks[i]
            let type: Int = FilterMigration.soundType(base: t.params["filter"], others: FilterMigration.used(t))
            for k in 0..<t.clips.count {
                guard var c = t.clips[k] else { continue }
                if var src = c.src {
                    var others: [Double] = []
                    for page in c.pages { for s in page { if let v = s.locks["filter"] { others.append(v) } } }
                    let st: Int = FilterMigration.soundType(base: src.params["filter"], others: others)
                    FilterMigration.params(&src.params, type: st)
                    FilterMigration.clip(&c, type: st)
                    c.src = src
                } else {
                    FilterMigration.clip(&c, type: type)
                }
                t.clips[k] = c
            }
            for k in 0..<t.blocks.count {
                if var c = t.blocks[k].pattern {
                    FilterMigration.clip(&c, type: type)
                    t.blocks[k].pattern = c
                }
                FilterMigration.lanes(&t.blocks[k].autos, type: type)
            }
            FilterMigration.lanes(&t.autos, type: type)
            if let v = t.morphOrig["filter"] { t.morphOrig["filter"] = FilterMigration.value(v, type: type) }
            if var h = t.home {
                FilterMigration.params(&h.params, type: FilterMigration.soundType(base: h.params["filter"], others: []))
                t.home = h
            }
            FilterMigration.params(&t.params, type: type)
            tracks[i] = t
        }
    }
}
