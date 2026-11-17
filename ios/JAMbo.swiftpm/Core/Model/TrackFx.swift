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

// MARK: — MORPH эффектов дорожки (17.11): исходное — в Track.morphOrig под ключом «fx:» + id (возврат — в клип, который
// тогда играет на дорожке), точка MORPH на дорожке и RETURN — как у ручек дорожки.

extension Project {
    static let morphFxKey: String = "fx:"

    /// Ключ MORPH эффекта id (nil — не эффект дорожки).
    public static func morphFxId(_ key: String) -> String? {
        return key.hasPrefix(morphFxKey) ? String(key.dropFirst(morphFxKey.count)) : nil
    }

    /// Эффект id дорожки t меняют в режиме MORPH: исходное — при первом изменении.
    public mutating func morphFx(track t: Int, _ id: String) {
        guard t >= 0 && t < tracks.count else { return }
        tracks[t].morphEdited = true
        let key: String = Project.morphFxKey + id
        if tracks[t].morphOrig[key] == nil { tracks[t].morphOrig[key] = fxValue(track: t, id) }
    }

    /// MORPH на все дорожки на сетке FX: эффект выбранной дорожки sel — на norm, у остальных дорожек с клипом — сдвиг
    /// на ту же долю хода от их исходного (как morphShift у ручек).
    public mutating func morphShiftFx(from sel: Int, def p: ParamDef, norm: Double) {
        guard sel >= 0 && sel < tracks.count else { return }
        let key: String = Project.morphFxKey + p.id
        let o0: Double = tracks[sel].morphOrig[key] ?? fxValue(track: sel, p.id)
        let delta: Double = norm - p.toNorm(o0)
        for i in tracks.indices where i != sel && fxClip(i) >= 0 {
            morphFx(track: i, p.id)
            let o: Double = tracks[i].morphOrig[key] ?? fxValue(track: i, p.id)
            let n: Double = Swift.min(1, Swift.max(0, p.toNorm(o) + delta))
            setFx(track: i, p.id, p.fromNorm(n))
        }
    }

    /// Вернуть всё, что меняли в режиме MORPH на дорожке i: эффекты — в клип, ручки и назначения — Track.undoMorph.
    public mutating func undoMorph(track i: Int) {
        guard i >= 0 && i < tracks.count else { return }
        for (key, v) in tracks[i].morphOrig {
            if let id = Project.morphFxId(key) { setFx(track: i, id, v) }
        }
        tracks[i].undoMorph()
    }

    /// Значение ключа MORPH на дорожке i сейчас (эффект — из клипа).
    func morphValue(_ i: Int, _ key: String) -> Double? {
        if let id = Project.morphFxId(key) { return fxValue(track: i, id) }
        return tracks[i].params[key]
    }

    /// Поставить значение ключа MORPH на дорожке i.
    mutating func setMorphValue(_ i: Int, _ key: String, _ v: Double) {
        if let id = Project.morphFxId(key) {
            setFx(track: i, id, v)
        } else {
            tracks[i].params[key] = v
        }
    }
}
