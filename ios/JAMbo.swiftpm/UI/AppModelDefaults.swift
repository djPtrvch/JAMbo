import Foundation

// Свои значения ручек по умолчанию (KnobDefaults): SHIFT + удержание ручки — запомнить, двойной тап — сбросить;
// SETTINGS → DEFAULTS — забыть все.

extension AppModel {
    static let knobDefaultsKey = "knobDefaults"

    /// Область ручки slot на текущей странице (MIX — нет).
    func defaultScope(_ slot: Int) -> String? {
        switch channel {
        case .mix: return nil
        case .master: return "mst"
        case .track:
            if modMode { return "mod" }
            if fxMode { return "fx" }
            return KnobDefaults.soundScope(track.sample)
        }
    }

    /// Значение ручки без p-lock (то, что запоминается и сбрасывается).
    private func baseValue(_ p: ParamDef) -> Double {
        if channel == .master { return masterValue(p) }
        if fxMode { return fxValue(p) }
        return track.params[p.id] ?? p.def
    }

    /// Значение спутника (Dly Sync, синхронизация LFO) на текущей странице.
    private func companionValue(_ id: String) -> Double {
        if fxMode { return project.fx[id] ?? Params.byId[id]?.def ?? 0 }
        return track.params[id] ?? 0
    }

    private func storeDefaults(_ change: (inout KnobDefaults) -> Void) {
        change(&knobDefaults)
        UserDefaults.standard.set(knobDefaults.encode(), forKey: AppModel.knobDefaultsKey)
    }

    /// SHIFT + удержание: значение ручки — своё по умолчанию (на ручке на секунду SAVED).
    func saveKnobDefault(_ slot: Int) {
        guard let scope = defaultScope(slot), let p = param(slot), !p.id.isEmpty else { return }
        let v: Double = baseValue(p)
        let c: String? = KnobDefaults.companion(p.id)
        let cv: Double? = c.map { companionValue($0) }
        storeDefaults { d in
            d.values[KnobDefaults.key(scope, p.id)] = v
            if let c = c, let cv = cv { d.values[KnobDefaults.key(scope, c)] = cv }
        }
        defaultFlash = slot
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if self.defaultFlash == slot { self.defaultFlash = nil }
        }
    }

    /// Двойной тап: к своему значению по умолчанию; уже на нём (или своего нет) — к заводскому.
    func resetKnob(_ slot: Int) {
        guard let scope = defaultScope(slot), let p = param(slot), !p.id.isEmpty else { return }
        let c: String? = KnobDefaults.companion(p.id)
        let cur: Double = baseValue(p)
        let curC: Double? = c.map { companionValue($0) }
        var v: Double = p.def
        var cv: Double? = c.map { Params.byId[$0]?.def ?? 0 }
        // RATE: режим PTCH / TSTR сбрасывается только к своему по умолчанию (заводской сброс его не трогает).
        if p.id == "rate" { cv = curC }
        if let own = knobDefaults.value(scope, p.id) {
            let ownC: Double? = c.flatMap { knobDefaults.value(scope, $0) }
            let same: Bool = abs(own - cur) < 1e-9 && (ownC == nil || ownC == curC)
            if !same {
                v = own
                if let oc = ownC { cv = oc }
            }
        }
        // Заводское Dly Time — пункт по темпу.
        if p.id == "dly.time" && cv == 1 && v != v.rounded() { v = v.rounded() }
        let i: Int = selectedTrack
        let id: String = p.id
        switch channel {
        case .master:
            edit { pr in pr.master[id] = v }
        case .track where fxMode:
            edit { pr in
                pr.fx[id] = v
                if let c = c, let cv = cv { pr.fx[c] = cv }
                writeLead(&pr)
            }
        default:
            edit { pr in
                pr.tracks[i].params[id] = v
                if let c = c, let cv = cv { pr.tracks[i].params[c] = cv }
            }
        }
    }

    /// SETTINGS → DEFAULTS: сколько своих значений запомнено.
    var knobDefaultsCount: Int {
        return knobDefaults.values.keys.filter { k in
            !(k.hasSuffix("/dly.sync") || k.hasSuffix("/" + Params.rateModeId)
              || Params.lfoSyncIds.contains { k.hasSuffix("/" + $0) })
        }.count
    }

    func clearKnobDefaults() {
        storeDefaults { d in d.values.removeAll() }
    }
}
