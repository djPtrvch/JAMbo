import SwiftUI

/// AUTO в аранжировщике (S15f2): под выбранной дорожкой — строки её кривых и строка «+».
struct ArrAutoView: Equatable {
    var track: Int = -1
    var lanes: Int = 0
}

extension AppModel {
    /// Строки кривых: AUTO включён и выбрана дорожка — её кривые и «+».
    var arrAutoView: ArrAutoView {
        guard arrAuto, channel == .track, selectedTrack < project.tracks.count else { return ArrAutoView() }
        return ArrAutoView(track: selectedTrack, lanes: project.tracks[selectedTrack].autos.count + 1)
    }

    /// Ручки сетки дорожки, которые можно автоматизировать: id и подпись (в порядке сетки).
    func arrAutoKnobs(_ t: Int) -> [(id: String, label: String)] {
        guard t >= 0 && t < project.tracks.count else { return [] }
        let grid: [ParamDef] = Params.grid(sound: project.tracks[t].sample)
        var out: [(id: String, label: String)] = []
        for p in grid where !p.id.isEmpty && ArrAutoTarget.index(p.id) != nil { out.append((p.id, p.label)) }
        return out
    }

    func arrAutoLabel(_ t: Int, _ id: String) -> String {
        for k in arrAutoKnobs(t) where k.id == id { return k.label }
        return Params.byId[id]?.label ?? id
    }

    /// «+»: кривая ручки id (пустая — точки ставят тапом); уже есть — ничего.
    func arrAutoAdd(track t: Int, _ id: String) {
        guard t >= 0 && t < project.tracks.count, project.tracks[t].autoLane(id) == nil else { return }
        edit { p in p.tracks[t].setAuto(id, []) }
    }

    func arrAutoDelete(track t: Int, _ id: String) {
        guard t >= 0 && t < project.tracks.count else { return }
        edit { p in p.tracks[t].deleteAuto(id) }
    }

    func arrAutoClear(track t: Int, _ id: String) {
        guard t >= 0 && t < project.tracks.count else { return }
        edit { p in p.tracks[t].setAuto(id, []) }
    }

    /// Точки кривой (тап, перетаскивание, удаление; при перетаскивании — внутри жеста, одна запись UNDO).
    func arrAutoSet(track t: Int, _ id: String, _ points: [ArrAutoPoint]) {
        guard t >= 0 && t < project.tracks.count else { return }
        edit { p in p.tracks[t].setAuto(id, points) }
    }

    /// Шаг точки: с магнитом — целый шаг, без — четверть шага.
    func arrAutoSnap(_ x: Double) -> Double {
        let q: Double = project.arrange.snap ? 1 : 4
        return max(0, (x * q).rounded() / q)
    }
}
