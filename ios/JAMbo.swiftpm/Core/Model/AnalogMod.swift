import Foundation

// ANALOG (решение пользователя, 8.11): модуляция B осциллятором A и октава B — скрытые значения звука (без p-lock шага,
// в проекте и пресете синта, переходят с пресет-локом). SHIFT + тап по WAVE A — модуляция вкл./выкл., по WAVE B —
// B на октаву ниже, по 1.3 (при включённой модуляции) — следующий режим; 1.3 тогда — AMOUNT (то же значение ручки,
// что DETUNE). Подписи режимов — здесь (одна таблица).

public enum AnalogMod {
    /// Режим модуляции: 0 — нет; 1 SYNC, 2 FM, 3 RING — включена; −1…−3 — выключена, помнит выбранный режим
    /// (вкл. снова — он же); 0 — выключена, при включении — SYNC.
    public static let modId = "analog.mod"
    /// Октава B: 1 — на октаву ниже.
    public static let octId = "analog.oct"
    public static let ids: [String] = [modId, octId]
    /// Имена режимов SYNC, FM, RING (подпись ручки 1.3 при включённой модуляции).
    public static let names: [String] = ["Sync", "FM", "Ring"]
    /// SYNC: AMOUNT 0 → 100 % — высота B 0 → +24 полутона.
    public static let syncSt = 24.0

    /// Действующий режим по значению: 0 — нет, 1…3 — SYNC, FM, RING.
    @inline(__always) public static func mode(_ v: Double) -> Int {
        if v < 0.5 { return 0 }
        return Swift.min(3, Int(v + 0.5))
    }

    /// SHIFT + тап по WAVE A: вкл. ↔ выкл. (выбранный режим запоминается).
    public static func toggled(_ v: Double) -> Double {
        let m: Int = mode(v)
        if m > 0 { return -Double(m) }
        let last: Int = Int(-v + 0.5)
        return Double(last >= 1 && last <= 3 ? last : 1)
    }

    /// SHIFT + тап по 1.3: следующий режим (back — предыдущий: второй тап двойного отменяет первый); выключена — как есть.
    public static func cycled(_ v: Double, back: Bool = false) -> Double {
        let m: Int = mode(v)
        if m == 0 { return v }
        let n: Int = back ? (m + 1) % 3 + 1 : m % 3 + 1
        return Double(n)
    }

    /// Ручка 1.3 при включённой модуляции: AMOUNT с подписью режима (SYNC — полутоны, FM и RING — проценты).
    static let amount: [ParamDef] = (0..<3).map { k in
        let label: String = names[k]
        if k == 0 {
            return ParamDef(id: "morph", label: label, min: 0, max: 100, def: 50) { v in
                "+" + String(format: "%.1f", v / 100 * syncSt) + " st"
            }
        }
        return ParamDef(id: "morph", label: label, min: 0, max: 100, def: 50, format: Fmt.pct)
    }

    /// WAVE B на октаву ниже: пункт с пометкой «−1» (через неразрывный пробел — на ручке в одну строку).
    static let waveBLow: ParamDef = {
        let o: [String] = SynthEngines.waves
        return ParamDef(id: "timbre", label: "Wave B", kind: .stepped, min: 0, max: 100, def: 50, steps: o.count) { v in
            o[Params.stepIndex(v / 100, o.count)] + "\u{00A0}−1"
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
