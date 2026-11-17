import Foundation

// Эффекты дорожек (17.11, решения пользователя): Reverb, Delay, Drive — свои у дорожки и хранятся в её клипах
// (Clip.fx; у клипа без своего значения — общее Project.fx); Duck (sc.*) — общий: FX клипа, запущенного последним
// (Project.fx, как прежде). Сетка FX дорожки показывает и правит FX клипа, который на ней играет (нет — открытого).

extension Project {
    /// FX дорожки (Reverb, Delay, Drive), а не общий (Duck).
    public static func trackFx(_ id: String) -> Bool {
        return !id.hasPrefix("sc.")
    }

    /// Клип дорожки t, FX которого показывает и правит сетка FX: играющий, иначе открытый; нет клипа — −1.
    public func fxClip(_ t: Int) -> Int {
        guard t >= 0 && t < tracks.count else { return -1 }
        let tr: Track = tracks[t]
        if tr.slot >= 0 && tr.slot < tr.clips.count && tr.clips[tr.slot] != nil { return tr.slot }
        if tr.open >= 0 && tr.open < tr.clips.count && tr.clips[tr.open] != nil { return tr.open }
        return -1
    }

    /// Значение FX id на дорожке t: у FX дорожки — клипа (без своего — общее), у Duck — общее.
    public func fxValue(track t: Int, _ id: String) -> Double {
        let common: Double = fx[id] ?? Params.byId[id]?.def ?? 0
        guard Project.trackFx(id) else { return common }
        let k: Int = fxClip(t)
        guard k >= 0, let v = tracks[t].clips[k]?.fx?[id] else { return common }
        return v
    }

    /// Записать FX id дорожки t (в её клип; Duck — в общие). У дорожки нет клипа — в общие (их берут клипы без своего
    /// значения и игра с клавиатуры без клипа).
    public mutating func setFx(track t: Int, _ id: String, _ v: Double) {
        guard Project.trackFx(id) else {
            fx[id] = v
            return
        }
        let k: Int = fxClip(t)
        guard k >= 0 else {
            fx[id] = v
            return
        }
        var f: [String: Double] = tracks[t].clips[k]?.fx ?? [:]
        f[id] = v
        tracks[t].clips[k]?.fx = f
    }

    /// Версия 10 (17.11): прежде FX были общими — звучали FX клипа, запущенного последним (Project.fx). Всем клипам
    /// всех дорожек — эти значения Reverb, Delay, Drive: проект звучит как прежде (решение пользователя).
    mutating func migrateTrackFx() {
        var common: [String: Double] = [:]
        for id in Params.fxIds where Project.trackFx(id) { common[id] = fx[id] ?? Params.byId[id]?.def ?? 0 }
        for i in 0..<tracks.count {
            for k in 0..<tracks[i].clips.count {
                guard var c = tracks[i].clips[k] else { continue }
                var f: [String: Double] = c.fx ?? [:]
                for (id, v) in common { f[id] = v }
                c.fx = f
                tracks[i].clips[k] = c
            }
        }
    }
}
