import Foundation

// MORPH (S9, решение пользователя): ручки на все дорожки и плавный возврат после выключения режима.

/// Возврат после выключения MORPH: OFF (сразу), 1/4, 1/2 такта, такт, 2 такта (в долях, такт — 4 доли).
public enum MorphReturn {
    public static let beats: [Double] = [0, 1, 2, 4, 8]
    public static let names: [String] = ["OFF", "1/4", "1/2", "1 BAR", "2 BARS"]

    /// Длительность возврата, с.
    public static func seconds(_ k: Int, bpm: Double) -> Double {
        guard k >= 0 && k < beats.count else { return 0 }
        return beats[k] * 60 / Swift.max(1, bpm)
    }
}

/// Точка возврата: дорожка (Track.id), параметр, значение сейчас и исходное.
public struct MorphPoint: Equatable, Sendable {
    public let track: Int
    public let param: String
    public let from: Double
    public let to: Double
}

extension Project {
    /// MORPH на все дорожки: ручку id выбранной дорожки sel поставили на norm (доля хода 0…1) — у остальных дорожек,
    /// где эта ручка есть на сетке их звука (или MOD), — сдвиг на ту же долю хода от их значения на момент включения режима
    /// (у края шкалы упирается; вернув ручку, получаем прежнее соотношение).
    /// def — описание ручки у выбранной дорожки (у движков синта диапазон своей ручки может отличаться от общего).
    public mutating func morphShift(from sel: Int, def p0: ParamDef, norm: Double) {
        let id: String = p0.id
        guard sel >= 0 && sel < tracks.count else { return }
        let o0: Double = tracks[sel].morphOrig[id] ?? tracks[sel].params[id] ?? p0.def
        let delta: Double = norm - p0.toNorm(o0)
        for i in tracks.indices where i != sel {
            let defs: [ParamDef] = (Params.grid(sound: tracks[i].sample) + Params.modGrid).filter { !$0.id.isEmpty }
            guard let p = defs.first(where: { $0.id == id }) else { continue }
            tracks[i].morphParam(id)
            let o: Double = tracks[i].morphOrig[id] ?? p.def
            let n: Double = Swift.min(1, Swift.max(0, p.toNorm(o) + delta))
            tracks[i].params[id] = p.fromNorm(n)
        }
    }

    /// UNDO / REDO не трогают MORPH (8.11, решение пользователя): снимок истории получает от текущего проекта то, что
    /// накручено в режиме MORPH (значения, назначения и их исходные); исходное — из снимка (к нему MORPH вернётся).
    public mutating func keepMorph(from cur: Project) {
        for i in tracks.indices {
            guard let c = cur.tracks.first(where: { $0.id == tracks[i].id }) else { continue }
            tracks[i].keepMorph(from: c)
        }
    }
}

extension Track {
    /// Снимок дорожки (self) с MORPH дорожки cur: исходное — значение снимка без его MORPH, сейчас — как у cur.
    public mutating func keepMorph(from cur: Track) {
        var orig: [String: Double] = [:]
        for (id, _) in cur.morphOrig {
            orig[id] = morphOrig[id] ?? params[id] ?? Params.byId[id]?.def ?? 0
        }
        for (id, b) in morphOrig where cur.morphOrig[id] == nil { params[id] = b }
        for (id, _) in cur.morphOrig { params[id] = cur.params[id] }
        var origA: [String: ModAssign?] = [:]
        for (id, _) in cur.morphOrigAssign {
            if let a = morphOrigAssign[id] { origA[id] = a } else { origA[id] = .some(assigns[id]) }
        }
        for (id, a) in morphOrigAssign where !cur.morphOrigAssign.keys.contains(id) {
            if let x = a { assigns[id] = x } else { assigns.removeValue(forKey: id) }
        }
        for (id, _) in cur.morphOrigAssign {
            if let x = cur.assigns[id] { assigns[id] = x } else { assigns.removeValue(forKey: id) }
        }
        morphOrig = orig
        morphOrigAssign = origA
        morphEdited = cur.morphEdited
    }
}

extension Project {
    /// Что вернуть при выключении MORPH: изменённые ручки всех дорожек.
    public func morphReturnPoints() -> [MorphPoint] {
        var out: [MorphPoint] = []
        for t in tracks where t.morphEdited {
            for (id, to) in t.morphOrig {
                let from: Double = t.params[id] ?? to
                if from != to { out.append(MorphPoint(track: t.id, param: id, from: from, to: to)) }
            }
        }
        return out
    }

    /// Возврат на долю f (0…1): ручки — между значением при выключении и исходным (по ходу ручки).
    public mutating func applyMorphReturn(_ pts: [MorphPoint], _ f: Double) {
        let k: Double = Swift.min(1, Swift.max(0, f))
        for pt in pts {
            guard let i = tracks.firstIndex(where: { $0.id == pt.track }), let p = Params.byId[pt.param] else { continue }
            let a: Double = p.toNorm(pt.from)
            let b: Double = p.toNorm(pt.to)
            tracks[i].params[pt.param] = k >= 1 ? pt.to : p.fromNorm(a + (b - a) * k)
        }
    }
}
