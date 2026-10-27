import Foundation

// Свои значения по умолчанию ручек (решение пользователя): SHIFT + удержание ручки — запомнить значение, двойной тап —
// сбросить к нему (уже на нём — к заводскому); SAVE DEFAULT в PRESETS окон модулей мастера — все параметры модуля,
// в PRESETS EQ — полосы EQ дорожки или мастера. Общие для проектов (UserDefaults). Действуют при сбросе, в новом
// проекте (NEW) и на новой дорожке (ADD TRACK); сохранённые проекты не меняются.

public struct KnobDefaults: Codable, Equatable, Sendable {
    /// Ключ «область/id»: звук дорожки — sampler или synthN (у движков одни id с разным смыслом), mod, fx, mst.
    public var values: [String: Double] = [:]
    /// Свой EQ по умолчанию (SAVE DEFAULT в PRESETS EQ): полосы EQ дорожки и EQ мастера; nil — нет своего.
    public var eqTrack: [EqBand?]? = nil
    public var eqMaster: [EqBand?]? = nil

    public init() {}

    /// Ничего своего не запомнено.
    public var isEmpty: Bool { return values.isEmpty && eqTrack == nil && eqMaster == nil }

    /// SAVE DEFAULT в PRESETS EQ: полосы EQ мастера или дорожки.
    public mutating func setEq(_ bands: [EqBand?], master: Bool) {
        if master { eqMaster = bands } else { eqTrack = bands }
    }

    /// Полосы по умолчанию как пресет (для Eq.apply).
    static func eqPreset(_ bands: [EqBand?]) -> EqPreset {
        return EqPreset(name: "", bands: bands)
    }

    /// Область ручек звука дорожки.
    public static func soundScope(_ sound: String) -> String {
        if let e = SynthKey.engine(sound) { return "synth\(e)" }
        return "sampler"
    }

    public static func key(_ scope: String, _ id: String) -> String {
        return scope + "/" + id
    }

    /// Вместе со значением ручки запоминается то, от чего зависит его смысл: Dly Time — Dly Sync, Speed — синхронизация LFO,
    /// RATE — режим PTCH / TSTR.
    public static func companion(_ id: String) -> String? {
        if id == "dly.time" { return "dly.sync" }
        if id == "rate" { return Params.rateModeId }
        for (l, sid) in Params.lfoSyncIds.enumerated() where id == "lfo\(l + 1).speed" { return sid }
        return nil
    }

    public func value(_ scope: String, _ id: String) -> Double? {
        return values[KnobDefaults.key(scope, id)]
    }

    /// Звук и MOD дорожки — по своим значениям.
    public func apply(to t: inout Track) {
        applySound(to: &t)
        for id in Params.modIds + Params.lfoSyncIds {
            if let v = value("mod", id) { t.params[id] = v }
        }
        if let b = eqTrack { t.eq.apply(KnobDefaults.eqPreset(b), tracks: 0) }
    }

    /// Ручки звука дорожки (сэмплер или движок синта) — по своим значениям его области.
    public func applySound(to t: inout Track) {
        let scope: String = KnobDefaults.soundScope(t.sample)
        for p in Params.grid(sound: t.sample) where !p.id.isEmpty {
            if let v = value(scope, p.id) { t.params[p.id] = v }
            if p.id == "rate", let m = value(scope, Params.rateModeId) { t.params[Params.rateModeId] = m }
        }
    }

    /// Новый проект: FX, мастер и дорожки.
    public func apply(to p: inout Project) {
        for id in Params.fxIds {
            if let v = value("fx", id) { p.fx[id] = v }
        }
        // Ручки MST и параметры модулей мастера (SAVE DEFAULT в PRESETS окон SAT, COMP, CLIP, LIM).
        let ids: [String] = Params.masterGrid.map { $0.id } + MasterChain.ids.map { $0.id }
        for id in ids where !id.isEmpty {
            if let v = value("mst", id) { p.master[id] = v }
        }
        if let b = eqMaster { p.masterEq.apply(KnobDefaults.eqPreset(b), tracks: 0) }
        for i in p.tracks.indices { apply(to: &p.tracks[i]) }
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data?) -> KnobDefaults {
        guard let d = data, let k = try? JSONDecoder().decode(KnobDefaults.self, from: d) else { return KnobDefaults() }
        return k
    }
}
