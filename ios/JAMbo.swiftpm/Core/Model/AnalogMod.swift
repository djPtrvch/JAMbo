import Foundation

// ANALOG (решение пользователя, 8.11): модуляция B осциллятором A и октава B — скрытые значения звука (без p-lock шага,
// в проекте и пресете синта, переходят с пресет-локом). SHIFT + тап по WAVE A — модуляция вкл./выкл., по WAVE B —
// B на октаву ниже, по 1.3 (при включённой модуляции) — следующий режим; 1.3 тогда — AMOUNT (то же значение ручки,
// что DETUNE). Подписи режимов — здесь (одна таблица).

public enum AnalogMod {
    /// Режим модуляции: 0 — нет; 1 SYNC, 2 FM, 3 RING, 4 AM — включена; −1…−4 — выключена, помнит выбранный режим
    /// (вкл. снова — он же); 0 — выключена, при включении — SYNC. AM (14.11, решение пользователя) — номер 4, чтобы
    /// старые проекты с SYNC, FM, RING звучали как прежде; порядок по SHIFT + тап: SYNC, AM, FM, RING.
    public static let modId = "analog.mod"
    /// Октава B: 1 — на октаву ниже.
    public static let octId = "analog.oct"
    public static let ids: [String] = [modId, octId]
    /// Имена режимов SYNC, FM, RING, AM (подпись ручки 1.3 при включённой модуляции).
    public static let names: [String] = ["Sync", "FM", "Ring", "AM"]
    /// AM — номер режима; порядок режимов по SHIFT + тап по 1.3.
    public static let am = 4
    static let order: [Int] = [1, 4, 2, 3]
    /// SYNC: AMOUNT 0 → 100 % — высота B 0 → +24 полутона.
    public static let syncSt = 24.0

    /// Действующий режим по значению: 0 — нет, 1…4 — SYNC, FM, RING, AM.
    @inline(__always) public static func mode(_ v: Double) -> Int {
        if v < 0.5 { return 0 }
        return Swift.min(4, Int(v + 0.5))
    }

    /// SHIFT + тап по WAVE A: вкл. ↔ выкл. (выбранный режим запоминается).
    public static func toggled(_ v: Double) -> Double {
        let m: Int = mode(v)
        if m > 0 { return -Double(m) }
        let last: Int = Int(-v + 0.5)
        return Double(last >= 1 && last <= 4 ? last : 1)
    }

    /// SHIFT + тап по 1.3: следующий режим (back — предыдущий: второй тап двойного отменяет первый); выключена — как есть.
    public static func cycled(_ v: Double, back: Bool = false) -> Double {
        let m: Int = mode(v)
        if m == 0 { return v }
        let at: Int = order.firstIndex(of: m) ?? 0
        let next: Int = back ? (at + 3) % 4 : (at + 1) % 4
        return Double(order[next])
    }

    /// Ручка 1.3 при включённой модуляции: AMOUNT с подписью режима (SYNC — полутоны, FM и RING — проценты).
    static let amount: [ParamDef] = (0..<4).map { k in
        let label: String = names[k]
        if k == 0 {
            return ParamDef(id: "morph", label: label, min: 0, max: 100, def: 50) { v in
                "+" + String(format: "%.1f", v / 100 * syncSt) + " st"
            }
        }
        return ParamDef(id: "morph", label: label, min: 0, max: 100, def: 50, format: Fmt.pct)
    }

    /// WAVE B на октаву ниже: пункт и под ним «−1» (вторая строка на ручке — подпись не длинная; решение пользователя).
    static let waveBLow: ParamDef = {
        let o: [String] = SynthEngines.waves
        return ParamDef(id: "timbre", label: "Wave B", kind: .stepped, min: 0, max: 100, def: 50, steps: o.count) { v in
            o[Params.stepIndex(v / 100, o.count)] + "\n−1"
        }
    }()

    /// Ручка 1.1–1.4 синта с учётом режима ANALOG (иначе — p как есть).
    public static func knob(_ p: ParamDef, engine: Int, params: [String: Double]) -> ParamDef {
        if engine != Jambo.analog { return p }
        if p.id == "timbre" && (params[octId] ?? 0) >= 0.5 { return waveBLow }
        if p.id == "morph" {
            let m: Int = mode(params[modId] ?? 0)
            if m > 0 { return amount[m - 1] }
        }
        return p
    }
}
