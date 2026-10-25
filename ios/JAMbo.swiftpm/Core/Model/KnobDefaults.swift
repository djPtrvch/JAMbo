import Foundation

// Свои значения по умолчанию ручек (решение пользователя): SHIFT + удержание ручки — запомнить значение, двойной тап —
// сбросить к нему (уже на нём — к заводскому). Общие для проектов (UserDefaults). Действуют при сбросе, в новом
// проекте (NEW) и на новой дорожке (ADD TRACK); сохранённые проекты не меняются.

public struct KnobDefaults: Codable, Equatable, Sendable {
    /// Ключ «область/id»: звук дорожки — sampler или synthN (у движков одни id с разным смыслом), mod, fx, mst.
    public var values: [String: Double] = [:]

    public init() {}

    /// Область ручек звука дорожки.
    public static func soundScope(_ sound: String) -> String {
        if let e = SynthKey.engine(sound) { return "synth\(e)" }
        return "sampler"
    }

    public static func key(_ scope: String, _ id: String) -> String {
        return scope + "/" + id
    }

    /// Вместе со значением ручки запоминается то, от чего зависит его смысл: Dly Time — Dly Sync, Speed — синхронизация LFO.
    public static func companion(_ id: String) -> String? {
        if id == "dly.time" { return "dly.sync" }
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
    }

    /// Ручки звука дорожки (сэмплер или движок синта) — по своим значениям его области.
    public func applySound(to t: inout Track) {
        let scope: String = KnobDefaults.soundScope(t.sample)
        for p in Params.grid(sound: t.sample) where !p.id.isEmpty {
            if let v = value(scope, p.id) { t.params[p.id] = v }
        }
    }

    /// Новый проект: FX, мастер и дорожки.
    public func apply(to p: inout Project) {
        for id in Params.fxIds {
            if let v = value("fx", id) { p.fx[id] = v }
        }
        for d in Params.masterGrid where !d.id.isEmpty {
            if let v = value("mst", d.id) { p.master[d.id] = v }
        }
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
